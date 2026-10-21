import Darwin

/// 只写的 USB 串口（115200 8N1）。
///
/// ESP32 开发板用 CH340 的 DTR/RTS 驱动 EN 和 GPIO0 做自动复位。macOS 打开串口时会同时拉起
/// DTR 和 RTS，两者同时有效不会触发复位；打开后立即把两者同时清掉，并关掉 HUPCL，
/// 这样关闭串口时也不会再拉线。实机验证：打开、发送、关闭都不会让板子重启。
public final class SerialPort {
    public let path: String
    private var fd: Int32

    public init?(path: String) {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        self.path = path
        self.fd = fd

        guard ioctl(fd, TIOCEXCL) == 0,
              fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) == 0 else {
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

    /// 设备拔出（EIO/ENXIO）、已关闭或写不全时返回 false，调用方应关闭后重连。
    public func write(_ s: String) -> Bool {
        guard fd >= 0 else { return false }
        let bytes = Array(s.utf8)
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { return false }
            offset += n
        }
        return true
    }

    public func close() {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }
}
