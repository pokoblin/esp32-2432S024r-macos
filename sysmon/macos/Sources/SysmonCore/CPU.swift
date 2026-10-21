import Darwin

/// 整机 CPU 累计时间片（所有核心之和）。
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// 两次采样之间的整机 CPU 占用百分比（0–100）。
public func cpuPercent(prev: CPUTicks, cur: CPUTicks) -> Int {
    // 内核计数是 32 位，回绕后按 2^32 补回
    func delta(_ a: UInt64, _ b: UInt64) -> UInt64 { b >= a ? b - a : b + (1 << 32) - a }
    let busy = delta(prev.user, cur.user) + delta(prev.system, cur.system) + delta(prev.nice, cur.nice)
    let total = busy + delta(prev.idle, cur.idle)
    guard total > 0 else { return 0 }
    let pct = (Double(busy) * 100 / Double(total)).rounded()
    return Int(min(max(pct, 0), 100))
}

public func readCPUTicks() -> CPUTicks? {
    var info = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }
    let t = info.cpu_ticks  // 依次是 CPU_STATE_USER / SYSTEM / IDLE / NICE
    return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
}
