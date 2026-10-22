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
