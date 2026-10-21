/// 把每次的原始读数（CPU 累计时间片、网卡累计字节、内存压力）变成一条 Sample。
/// CPU 和网速都要和上一次比较，所以第一次（或 reset 之后）只建立基线、返回 nil。
public struct MetricsSampler: Sendable {
    private var rateMeter = RateMeter()
    private var lastCPU: CPUTicks?
    private var lastTime: Double?

    public init() {}

    /// now 是单调时间（秒），用来算两次采样之间实际经过的时间。
    public mutating func sample(cpu ticks: CPUTicks?, counters: [String: IfCounters],
                                memory: (percent: Int, level: Int)?, now: Double) -> Sample? {
        let elapsed = lastTime.map { now - $0 } ?? 0
        let prevCPU = lastCPU
        lastTime = now
        lastCPU = ticks

        guard let rates = rateMeter.update(counters, elapsed: elapsed),
              let prevCPU, let ticks, let memory else { return nil }
        return Sample(cpu: cpuPercent(prev: prevCPU, cur: ticks), mem: memory.percent,
                      level: memory.level, rx: rates.rx, tx: rates.tx)
    }

    public mutating func reset() {
        self = MetricsSampler()
    }
}
