import Foundation
import Testing
@testable import SysmonCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

// MARK: - 番茄钟状态机

@Test func focusRunsThenBreakStartsAutomatically() {
    var p = Pomodoro()
    p.start(now: t0)
    #expect(p.phase == .focus && p.isRunning && p.remaining(now: t0 + 1) == 1499)
    let ev = p.advance(now: t0 + 1500)
    #expect(ev == [.focusCompleted(seconds: 1500, at: t0 + 1500)])
    #expect(p.phase == .short && p.isRunning && p.round == 1 && p.total(now: t0 + 1500) == 300)
    #expect(p.advance(now: t0 + 1800) == [.breakEnded(at: t0 + 1800)])
    // 只有专注要手动开始
    #expect(p.phase == .idle && !p.isRunning && p.round == 2)
}

@Test func fourthFocusGoesToLongBreakThenRoundOne() {
    var p = Pomodoro()
    var now = t0
    for round in 1...3 {
        p.start(now: now)
        now += 1500
        _ = p.advance(now: now)
        #expect(p.phase == .short && p.round == round)
        now += 300
        _ = p.advance(now: now)
    }
    #expect(p.round == 4)
    p.start(now: now)
    now += 1500
    _ = p.advance(now: now)
    #expect(p.phase == .long && p.total(now: now) == 900)
    now += 900
    #expect(p.advance(now: now) == [.breakEnded(at: now)])
    #expect(p.phase == .idle && p.round == 1)
}

@Test func sleepingThroughFocusAndBreakEmitsBothInOrder() {
    var p = Pomodoro()
    p.start(now: t0)
    let ev = p.advance(now: t0 + 3 * 3600)
    #expect(ev == [.focusCompleted(seconds: 1500, at: t0 + 1500), .breakEnded(at: t0 + 1800)])
    // 不会自动开始下一个专注
    #expect(p.phase == .idle && !p.isRunning)
}

@Test func pauseFreezesRemaining() {
    var p = Pomodoro()
    p.start(now: t0)
    p.pause(now: t0 + 100)
    #expect(!p.isRunning && p.endsAt == nil)
    #expect(p.remaining(now: t0 + 1000) == 1400)
    #expect(p.advance(now: t0 + 5000) == [])
    p.resume(now: t0 + 5000)
    #expect(p.isRunning && p.endsAt == t0 + 6400)
}

@Test func toggleCyclesStartPauseResume() {
    var p = Pomodoro()
    p.toggle(now: t0)
    #expect(p.phase == .focus && p.isRunning)
    p.toggle(now: t0 + 10)
    #expect(p.phase == .focus && !p.isRunning && p.remaining(now: t0 + 99) == 1490)
    p.toggle(now: t0 + 20)
    #expect(p.isRunning && p.endsAt == t0 + 1510)
}

@Test func skipFocusDoesNotAdvanceRound() {
    var p = Pomodoro()
    p.start(now: t0)
    p.skip(now: t0 + 60)
    #expect(p.phase == .idle && p.round == 1 && !p.isRunning)
    #expect(p.advance(now: t0 + 5000) == [])
}

@Test func skipBreakAdvancesRound() {
    var p = Pomodoro()
    p.start(now: t0)
    _ = p.advance(now: t0 + 1500)
    p.skip(now: t0 + 1510)
    #expect(p.phase == .idle && p.round == 2)
}

@Test func configChangeOnlyAffectsNextSegment() {
    var p = Pomodoro()
    p.start(now: t0)
    p.config.focusMinutes = 50
    p.config.shortBreakMinutes = 10
    #expect(p.total(now: t0 + 10) == 1500 && p.remaining(now: t0 + 10) == 1490)
    _ = p.advance(now: t0 + 1500)
    // 休息用新时长
    #expect(p.total(now: t0 + 1500) == 600)
    _ = p.advance(now: t0 + 2100)
    #expect(p.phase == .idle && p.total(now: t0 + 2100) == 3000 && p.remaining(now: t0 + 2100) == 3000)
}

@Test func restartRoundWhenIdleWaitsForIdle() {
    var p = Pomodoro()
    var now = t0
    for _ in 1...2 {
        p.start(now: now)
        now += 1500
        _ = p.advance(now: now)
        now += 300
        _ = p.advance(now: now)
    }
    p.start(now: now)
    #expect(p.round == 3)
    p.restartRoundWhenIdle()
    #expect(p.round == 3)
    now += 1800
    _ = p.advance(now: now)
    #expect(p.phase == .idle && p.round == 1)

    var q = Pomodoro()
    q.start(now: t0)
    _ = q.advance(now: t0 + 1800)
    #expect(q.round == 2)
    q.restartRoundWhenIdle()
    #expect(q.round == 1)
}

// MARK: - 健康计时

/// 从 from 起每 2 秒 tick 一次，共 seconds 秒；idle 按距 from 的秒数给出闲置秒数。返回结束时刻。
@discardableResult
private func run(_ h: inout HealthTracker, from: Date, seconds: Int,
                 idle: (Int) -> TimeInterval = { _ in 0 }, gate: Bool = true) -> Date {
    var s = 0
    while s <= seconds {
        h.tick(now: from + TimeInterval(s), idleSeconds: idle(s), gateActive: gate)
        s += 2
    }
    return from + TimeInterval(seconds)
}

@Test func sitBecomesDueAfterFiftyActiveMinutes() {
    var h = HealthTracker()
    let end = run(&h, from: t0, seconds: 50 * 60 - 2)
    #expect(!h.due.contains(.sit))
    run(&h, from: end + 2, seconds: 0)
    #expect(h.due.contains(.sit) && h.minutes(.sit) == 50)
}

@Test func shortIdleOnlyPausesAccrual() {
    var h = HealthTracker()
    var now = run(&h, from: t0, seconds: 30 * 60)
    // 闲置 4 分钟：不清零
    now = run(&h, from: now + 2, seconds: 240, idle: { TimeInterval($0) })
    #expect(h.minutes(.sit) >= 30)
    run(&h, from: now + 2, seconds: 20 * 60)
    #expect(h.due.contains(.sit))
}

@Test func fiveMinutesAwayResetsSitAndClearsDue() {
    var h = HealthTracker()
    let now = run(&h, from: t0, seconds: 50 * 60)
    #expect(h.due.contains(.sit))
    run(&h, from: now + 2, seconds: 300, idle: { TimeInterval($0) })
    #expect(!h.due.contains(.sit) && h.minutes(.sit) == 0)
    #expect(h.minutes(.water) >= 50)   // 喝水不受 5 分钟离开影响
}

@Test func gateClosedTimeJoinsIdleAsAway() {
    var h = HealthTracker()
    var now = run(&h, from: t0, seconds: 20 * 60)
    let lastInput = now
    now = run(&h, from: now + 2, seconds: 178, idle: { TimeInterval($0 + 2) })
    #expect(h.minutes(.sit) == 20)   // 闲置前 60 秒仍算在用
    now = run(&h, from: now + 2, seconds: 180, gate: false)
    #expect(h.awaySeconds(now: now) == now.timeIntervalSince(lastInput))
    #expect(h.awaySeconds(now: now) == 362)
    #expect(h.minutes(.sit) == 0)
}

@Test func lockInputDoesNotCountWhileGateClosed() {
    var h = HealthTracker()
    var now = run(&h, from: t0, seconds: 10 * 60)
    // 锁屏界面上敲密码，idleSeconds 是 0，但 gate 关着
    now = run(&h, from: now + 2, seconds: 4 * 60, gate: false)
    #expect(h.awaySeconds(now: now) == 242)
    #expect(h.minutes(.water) == 10)
}

@Test func waterSurvivesShortAwayResetsAfterThirty() {
    var h = HealthTracker()
    var now = run(&h, from: t0, seconds: 40 * 60)
    now = run(&h, from: now + 2, seconds: 10 * 60, gate: false)
    #expect(h.minutes(.water) == 40 && h.minutes(.sit) == 0)
    run(&h, from: now + 2, seconds: 20 * 60, gate: false)
    #expect(h.minutes(.water) == 0)
}

@Test func acknowledgeResets() {
    var h = HealthTracker()
    run(&h, from: t0, seconds: 60 * 60)
    #expect(h.due == [.sit, .water])
    h.acknowledge(.water)
    #expect(h.due == [.sit] && h.minutes(.water) == 0 && h.minutes(.sit) == 60)
}

@Test func disabledKindNeverDue() {
    var h = HealthTracker(config: HealthConfig(sitEnabled: false))
    let now = run(&h, from: t0, seconds: 2 * 3600)
    #expect(h.due == [.water])
    h.config.waterEnabled = false
    run(&h, from: now + 2, seconds: 0)
    #expect(h.due.isEmpty)
}

@Test func longTickGapCountsAsAway() {
    var h = HealthTracker()
    let now = run(&h, from: t0, seconds: 10 * 60)
    // Mac 睡了一小时，醒来第一次 tick 闲置读数是 0：这一小时不能算成在用
    h.tick(now: now + 3600, idleSeconds: 0, gateActive: true)
    #expect(h.minutes(.sit) == 0 && h.minutes(.water) == 0)
    // 定时器卡了 30 秒：不累计，也不算离开
    var g = HealthTracker()
    let end = run(&g, from: t0, seconds: 10 * 60)
    g.tick(now: end + 30, idleSeconds: 0, gateActive: true)
    #expect(g.minutes(.sit) == 10)
}
