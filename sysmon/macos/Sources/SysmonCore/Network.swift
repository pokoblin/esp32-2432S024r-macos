import Darwin

/// 某个网卡的累计收发字节（内核 if_data 里是 32 位，会回绕）。
public struct IfCounters: Equatable, Sendable {
    public var rx: UInt32
    public var tx: UInt32

    public init(rx: UInt32, tx: UInt32) {
        self.rx = rx
        self.tx = tx
    }
}

/// 只算有线和 WiFi（en*，以太网类型）。utun/ipsec 等 VPN 接口会和 en* 重复计同一份流量，
/// awdl/llw/anpi/bridge 虽然也是以太网类型，但名字不是 en 开头，一并排除。
public func isPhysicalInterface(name: String, type: UInt8) -> Bool {
    type == UInt8(IFT_ETHER) && name.hasPrefix("en")
}

public func counterDelta(prev: UInt32, cur: UInt32) -> UInt64 {
    UInt64(cur &- prev)
}

/// 由累计计数算每秒速率。新出现的网卡这一轮记 0，消失的网卡直接忽略，避免插拔时出现尖刺。
/// 网卡在两次采样之间重新枚举时计数会归零，按 32 位回绕会算出接近 4 GB 的增量；
/// 超过 10 Gbit/s 线速的增量一律视为计数重置，记 0。
public struct RateMeter: Sendable {
    private static let maxBytesPerSecond = 1.25e9

    private var last: [String: IfCounters]?

    public init() {}

    /// 第一次调用或 elapsed <= 0 时返回 nil。
    public mutating func update(_ counters: [String: IfCounters], elapsed: Double) -> (rx: UInt64, tx: UInt64)? {
        defer { last = counters }
        guard let last, elapsed > 0 else { return nil }
        let ceiling = elapsed * Self.maxBytesPerSecond
        func plausible(_ delta: UInt64) -> UInt64 { Double(delta) > ceiling ? 0 : delta }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        for (name, cur) in counters {
            guard let prev = last[name] else { continue }
            rx += plausible(counterDelta(prev: prev.rx, cur: cur.rx))
            tx += plausible(counterDelta(prev: prev.tx, cur: cur.tx))
        }
        return (UInt64((Double(rx) / elapsed).rounded()), UInt64((Double(tx) / elapsed).rounded()))
    }
}

public func readPhysicalCounters() -> [String: IfCounters] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return [:] }
    defer { freeifaddrs(head) }

    var result: [String: IfCounters] = [:]
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let ifa = p.pointee
        guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
              let data = ifa.ifa_data else { continue }
        let d = data.assumingMemoryBound(to: if_data.self).pointee
        let name = String(cString: ifa.ifa_name)
        guard isPhysicalInterface(name: name, type: d.ifi_type) else { continue }
        result[name] = IfCounters(rx: d.ifi_ibytes, tx: d.ifi_obytes)
    }
    return result
}
