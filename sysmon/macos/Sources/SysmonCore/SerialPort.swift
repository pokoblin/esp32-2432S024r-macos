import Darwin
import Dispatch

/// 把串口读到的字节流切成行。纯值类型，不碰 fd，方便单测。
///
/// 去掉行尾的 "\r\n"；超过 `maxLine` 字节的行整行丢弃（连同后面直到下一个 "\n" 的字节），
/// 和固件 LineReader 的做法一致，不会把半行当成一行交出去。
/// 无法按 UTF-8 解码的行宽松解码（坏字节变成 U+FFFD），由上层按内容忽略。
public struct SerialLineBuffer: Sendable {
    public static let maxLine = 256
    private var pending: [UInt8] = []
    private var overflowed = false

    public init() {}

    /// 返回这次追加后已经凑齐的整行，不含 \r\n。
    public mutating func append(_ bytes: [UInt8]) -> [String] {
        var lines: [String] = []
        for b in bytes {
            if b == UInt8(ascii: "\n") {
                if !overflowed {
                    if pending.last == UInt8(ascii: "\r") { pending.removeLast() }
                    lines.append(String(decoding: pending, as: UTF8.self))
                }
                pending.removeAll(keepingCapacity: true)
                overflowed = false
            } else if !overflowed {
                pending.append(b)
                if pending.count > Self.maxLine {
                    pending.removeAll(keepingCapacity: true)
                    overflowed = true
                }
            }
        }
        return lines
    }
}

/// USB 串口（115200 8N1），主要用来写；也可以按行读板子发回来的内容（`startReading`）。
///
/// ESP32 开发板用 CH340 的 DTR/RTS 驱动 EN 和 GPIO0 做自动复位。macOS 打开串口时会同时拉起
/// DTR 和 RTS，两者同时有效不会触发复位；打开后立即把两者同时清掉，并关掉 HUPCL，
/// 这样关闭串口时也不会再拉线。实机验证：打开、发送、关闭都不会让板子重启。
///
/// 一直保持非阻塞：设备还在但不收数据（USB 卡住）时，写不出去的行直接丢弃，
/// 不会卡住调用方所在的主线程；丢掉的半行固件会当作坏行忽略。
///
/// 只能在主线程使用：`startReading`、`onLine`、`write`、`close` 都在主线程调用，
/// 读取用的 DispatchSource 也挂在主队列上，所以 `onLine` 在主线程回调。
public final class SerialPort {
    public let path: String
    private var fd: Int32
    private var readSource: DispatchSourceRead?
    private var lineBuffer = SerialLineBuffer()
    /// 每收到一整行，在主线程回调一次。
    public var onLine: (@MainActor (String) -> Void)?
    // 连续这么多次写不出去（每 2 秒一次，约 10 秒）就当作设备已失联
    private static let maxStalledWrites = 5
    private var stalledWrites = 0

    public init?(path: String) {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        self.path = path
        self.fd = fd

        guard ioctl(fd, TIOCEXCL) == 0 else {
            close()
            return nil
        }

        var t = termios()
        guard tcgetattr(fd, &t) == 0 else {
            close()
            return nil
        }
        cfmakeraw(&t)
        cfsetspeed(&t, speed_t(B115200))
        t.c_cflag &= ~tcflag_t(CSIZE | PARENB | CSTOPB | CRTSCTS | HUPCL)
        t.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        guard tcsetattr(fd, TCSANOW, &t) == 0 else {
            close()
            return nil
        }

        var lines = TIOCM_DTR | TIOCM_RTS
        _ = ioctl(fd, TIOCMBIC, &lines)
    }

    deinit { close() }

    /// 设备拔出（EIO/ENXIO 等）、已关闭，或连续多次写不出去时返回 false，调用方应关闭后重连。
    /// 输出缓冲满时这一行被丢弃，仍返回 true。
    public func write(_ s: String) -> Bool {
        guard fd >= 0 else { return false }
        let bytes = Array(s.utf8)
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                offset += n
                continue
            }
            if n < 0 && errno == EINTR { continue }
            guard n < 0 && errno == EAGAIN else { return false }
            stalledWrites += 1
            return stalledWrites < Self.maxStalledWrites
        }
        stalledWrites = 0
        return true
    }

    /// 端口是否还开着；读到 EOF/EIO 或调用过 `close()` 后为 false。供测试观察读路径的收尾。
    var isOpen: Bool { fd >= 0 }

    /// 在 fd 上建主队列的读事件，用非阻塞 read 喂给行缓冲，整行通过 `onLine` 交出去。
    /// 读到 EOF 或 EIO/ENXIO（设备拔出）就关闭端口，之后 `write` 返回 false，由调用方重连。
    public func startReading() {
        guard fd >= 0, readSource == nil else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.resume()
        readSource = source
    }

    private func readAvailable() {
        guard fd >= 0 else { return }
        var buf = [UInt8](repeating: 0, count: 512)
        let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if n > 0 {
            for line in lineBuffer.append(Array(buf[..<n])) {
                // 每行重新取回调：回调里可能关闭端口或改掉 onLine
                guard let callback = onLine else { break }
                // 事件处理器跑在主队列上，可以直接当作在主 actor 上
                MainActor.assumeIsolated { callback(line) }
            }
        } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
            close()
        }
    }

    /// 必须在主线程调用。先取消读事件，再关 fd，且只关一次：有读事件时 fd 由取消回调关闭，
    /// 保证取消之后事件处理器不会再碰已经关掉（甚至被复用）的 fd。
    public func close() {
        guard fd >= 0 else { return }
        let fd = self.fd
        self.fd = -1
        // 丢掉没发出去的数据，避免 close 等待排空
        tcflush(fd, TCOFLUSH)
        if let source = readSource {
            readSource = nil
            source.setCancelHandler { Darwin.close(fd) }
            source.cancel()
        } else {
            Darwin.close(fd)
        }
    }
}
