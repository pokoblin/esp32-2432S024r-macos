import Testing
@testable import SysmonCore

private let ticksA = CPUTicks(user: 100, system: 100, idle: 800, nice: 0)
private let ticksB = CPUTicks(user: 150, system: 150, idle: 900, nice: 0)

@Test func samplerNeedsBaselineThenProducesSample() {
    var s = MetricsSampler()
    #expect(s.sample(cpu: ticksA, counters: ["en0": IfCounters(rx: 1000, tx: 0)],
                     memory: (51, 1), now: 10) == nil)
    let out = s.sample(cpu: ticksB, counters: ["en0": IfCounters(rx: 3000, tx: 500)],
                       memory: (51, 1), now: 12)
    #expect(out == Sample(cpu: 50, mem: 51, level: 1, rx: 1000, tx: 250))
}

@Test func samplerSkipsWhenAReadingIsMissing() {
    var s = MetricsSampler()
    _ = s.sample(cpu: ticksA, counters: [:], memory: (51, 1), now: 10)
    #expect(s.sample(cpu: ticksB, counters: [:], memory: nil, now: 12) == nil)
    #expect(s.sample(cpu: nil, counters: [:], memory: (51, 1), now: 14) == nil)
}

@Test func samplerResetDropsBaseline() {
    var s = MetricsSampler()
    _ = s.sample(cpu: ticksA, counters: [:], memory: (51, 1), now: 10)
    s.reset()
    #expect(s.sample(cpu: ticksB, counters: [:], memory: (51, 1), now: 12) == nil)
}
