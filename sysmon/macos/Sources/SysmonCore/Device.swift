/// 在 /dev 的文件名里找 CH340 串口（Apple 自带驱动或 WCH 驱动的命名）。
public func pickSerialDevice(from names: [String]) -> String? {
    names.sorted()
        .first { $0.hasPrefix("cu.usbserial-") || $0.hasPrefix("cu.wchusbserial") }
        .map { "/dev/" + $0 }
}
