import Darwin

/// 只写的 USB 串口（115200 8N1）。
///
/// ESP32 开发板用 CH340 的 DTR/RTS 驱动 EN 和 GPIO0 做自动复位。macOS 打开串口时会同时拉起
/// DTR 和 RTS，两者同时有效不会触发复位；打开后立即把两者同时清掉，并关掉 HUPCL，
/// 这样关闭串口时也不会再拉线。实机验证：打开、发送、关闭都不会让板子重启。
///
/// 一直保持非阻塞：设备还在但不收数据（USB 卡住）时，写不出去的行直接丢弃，
/// 不会卡住调用方所在的主线程；丢掉的半行固件会当作坏行忽略。
public final class SerialPort {
    public let path: String
    private var fd: Int32
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

    public func close() {
        guard fd >= 0 else { return }
        // 丢掉没发出去的数据，避免 close 等待排空
        tcflush(fd, TCOFLUSH)
        Darwin.close(fd)
        fd = -1
    }
}
