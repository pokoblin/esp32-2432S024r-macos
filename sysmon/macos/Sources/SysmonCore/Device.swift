import Foundation
import IOKit
import IOKit.serial

/// 系统里的一个串口（/dev/cu.*）及其所属 USB 设备的厂商 ID（非 USB 设备为 nil）。
public struct SerialDevice: Equatable, Sendable {
    public var path: String
    public var vendorID: Int?

    public init(path: String, vendorID: Int?) {
        self.path = path
        self.vendorID = vendorID
    }
}

/// WCH（沁恒）的 USB 厂商 ID，CH340、CH9102 等都用它。
let wchVendorID = 0x1a86

/// 只认 WCH 芯片的串口，按路径排序。FTDI 等其他 USB 转串口线也叫 cu.usbserial-*，
/// 不能按名字认，否则会独占别的设备、往里写协议文本。
public func boardCandidates(_ devices: [SerialDevice]) -> [String] {
    devices.filter { $0.vendorID == wchVendorID }.map(\.path).sorted()
}

public func listSerialDevices() -> [SerialDevice] {
    guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }

    var devices: [SerialDevice] = []
    var service = IOIteratorNext(iterator)
    while service != 0 {
        let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        // idVendor 在上层的 USB 设备节点上，沿父节点向上找
        let vendor = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "idVendor" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Int
        if let path { devices.append(SerialDevice(path: path, vendorID: vendor)) }
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
    return devices
}
