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

// MARK: - 横幅规则、今日统计、跨日

private let shanghai: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}()

private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    shanghai.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
}

/// 每 2 秒 tick 一次，覆盖 [from, from+seconds]；返回结束时刻。
@discardableResult
private func run(_ r: inout Routine, from: Date, seconds: Int,
                 idle: TimeInterval = 0, gate: Bool = true) -> Date {
    var s = 0
    while s <= seconds {
        r.tick(now: from + TimeInterval(s), idleSeconds: idle, gateActive: gate, calendar: shanghai)
        s += 2
    }
    return from + TimeInterval(seconds)
}

private func shortRoutine() -> Routine {
    Routine(pomodoro: Pomodoro(config: PomodoroConfig(focusMinutes: 1, shortBreakMinutes: 1)))
}

@Test func focusDoneBannerCarriesSuppressedReminders() {
    var r = Routine()
    r.health.config.sitMinutes = 10
    run(&r, from: t0, seconds: 0)
    r.start(now: t0)
    run(&r, from: t0 + 2, seconds: 11 * 60)
    #expect(r.health.due.contains(.sit) && r.banner == nil)
    run(&r, from: t0 + 2 + 11 * 60 + 2, seconds: 1500 - 11 * 60 - 4)
    #expect(r.banner == Banner(kind: .focusDone, minutes: nil, extras: [.sit]))
    #expect(r.health.due.isEmpty)
    #expect(r.stats.count == 1 && r.stats.focusSeconds == 1500)
}

@Test func pausedFocusStillSuppresses() {
    var r = Routine()
    r.health.config.waterMinutes = 1
    r.start(now: t0)
    r.pause(now: t0 + 1)
    run(&r, from: t0 + 2, seconds: 120)
    #expect(r.health.due.contains(.water) && r.banner == nil)
}

@Test func healthBannerShownBeforeFocusIsHiddenOnceFocusStarts() {
    var r = Routine()
    r.health.config.waterMinutes = 1
    let now = run(&r, from: t0, seconds: 62)
    #expect(r.banner?.kind == .water && r.banner?.minutes == 1)
    r.start(now: now)
    #expect(r.banner == nil)
    run(&r, from: now + 2, seconds: 1500)
    #expect(r.banner == Banner(kind: .focusDone, minutes: nil, extras: [.water]))
}

@Test func skipFocusReleasesSuppressed() {
    var r = Routine()
    r.health.config.sitMinutes = 1
    r.start(now: t0)
    let now = run(&r, from: t0, seconds: 70)
    #expect(r.banner == nil)
    r.skip(now: now)
    #expect(r.banner?.kind == .sit)
}

@Test func breakEndedReplacesFocusDoneAndClearsOnStart() {
    var r = Routine()
    r.start(now: t0)
    run(&r, from: t0, seconds: 1500)
    #expect(r.banner?.kind == .focusDone)
    let now = run(&r, from: t0 + 1502, seconds: 298)
    #expect(r.banner?.kind == .breakEnded)
    r.start(now: now)
    #expect(r.banner == nil)
}

@Test func priorityOrder() {
    var r = shortRoutine()
    r.health.config.sitMinutes = 1
    r.health.config.waterMinutes = 1
    r.start(now: t0)
    run(&r, from: t0, seconds: 130)
    #expect(r.banner?.kind == .breakEnded && r.health.due == [.sit, .water])
    var dismissed = [r.dismissBanner()]
    #expect(r.banner?.kind == .sit)
    dismissed.append(r.dismissBanner())
    #expect(r.banner?.kind == .water)
    dismissed.append(r.dismissBanner())
    #expect(r.banner == nil)
    dismissed.append(r.dismissBanner())
    #expect(dismissed == [true, true, true, false])
}

@Test func dismissSitAcknowledges() {
    var r = Routine()
    r.health.config.sitMinutes = 1
    run(&r, from: t0, seconds: 62)
    #expect(r.banner?.kind == .sit)
    r.dismissBanner()
    #expect(r.health.minutes(.sit) == 0 && r.banner == nil)
}

@Test func longGateCloseExpiresBreakEndedAndWater() {
    for (closedMinutes, expected) in [(31, nil), (10, BannerKind.breakEnded)] as [(Int, BannerKind?)] {
        var r = shortRoutine()
        r.health.config.waterMinutes = 1
        r.start(now: t0)
        var now = run(&r, from: t0, seconds: 130)
        #expect(r.banner?.kind == .breakEnded)
        now = run(&r, from: now + 2, seconds: closedMinutes * 60, gate: false)
        run(&r, from: now + 2, seconds: 0)
        #expect(r.banner?.kind == expected)
    }
}

@Test func sleepingThroughFocusAndBreakShowsOnlyBreakEnded() {
    var r = Routine()
    r.start(now: t0)
    r.tick(now: t0, idleSeconds: 0, gateActive: true, calendar: shanghai)
    r.tick(now: t0 + 2400, idleSeconds: 0, gateActive: true, calendar: shanghai)
    #expect(r.stats.count == 1 && r.banner?.kind == .breakEnded)
}

@Test func midnightResetsStatsAndRound() {
    var r = Routine(pomodoro: Pomodoro(config: PomodoroConfig(focusMinutes: 35)))
    let start = local(2026, 10, 22, 23, 30)
    run(&r, from: start, seconds: 0)
    r.start(now: start)
    run(&r, from: start + 2, seconds: 35 * 60)
    // 跨零点的专注算在结束那天
    #expect(r.stats == TodayStats(day: "2026-10-23", count: 1, focusSeconds: 2100))

    var q = shortRoutine()
    var now = local(2026, 10, 22, 23, 50)
    for _ in 1...2 {
        q.start(now: now)
        now = run(&q, from: now, seconds: 122) + 2
    }
    #expect(q.pomodoro.round == 3 && q.stats.count == 2)
    run(&q, from: now, seconds: 15 * 60)
    #expect(q.pomodoro.round == 1 && q.stats.count == 0 && q.stats.day == "2026-10-23")
}

// MARK: - 番茄页、T/B 行、菜单文案

@Test func pageCycleIncludesPomodoro() {
    let all = enabledPages(pomodoro: true, claude: true, chatgpt: true)
    #expect(all == [.sys, .pomodoro, .claude, .chatgpt])
    #expect(nextPage(after: .sys, enabled: all) == .pomodoro)
    #expect(encodePage(.pomodoro, enabled: all) == "P pomo i=2 n=4\n")
    #expect(enabledPages(pomodoro: false, claude: true, chatgpt: false) == [.sys, .claude])
}

/// 第 2 个专注走到还剩 754 秒，本地 14:52 结束
private func secondFocus() -> (Pomodoro, Date) {
    let end = local(2026, 10, 22, 14, 52)
    var p = Pomodoro()
    p.start(now: end - 4000)
    _ = p.advance(now: end - 2000)
    p.start(now: end - 1500)
    return (p, end - 754)
}

@Test func encodesTimerLine() {
    let (p, now) = secondFocus()
    let stats = TodayStats(day: "2026-10-22", count: 5, focusSeconds: 7500)
    let line = encodeTimer(p, stats: stats, hasHotKey: true, now: now, calendar: shanghai)
    #expect(line == "T st=focus run=1 rem=754 tot=1500 end=1452 rd=2 rn=4 dn=5 dm=125 key=1\n")
    #expect(line.utf8.count <= 128)
}

@Test func timerLinePausedAndIdleHaveNoEnd() {
    var (p, now) = secondFocus()
    p.pause(now: now)
    let paused = encodeTimer(p, stats: TodayStats(), hasHotKey: true, now: now, calendar: shanghai)
    #expect(paused.contains(" run=0 rem=754 ") && !paused.contains("end="))
    let idle = encodeTimer(Pomodoro(), stats: TodayStats(), hasHotKey: false, now: now, calendar: shanghai)
    #expect(idle == "T st=idle run=0 rem=1500 tot=1500 rd=1 rn=4 dn=0 dm=0 key=0\n")
}

@Test func encodesBannerLines() {
    #expect(encodeBanner(nil, led: true) == "B k=none\n")
    #expect(encodeBanner(Banner(kind: .focusDone, minutes: nil, extras: [.sit, .water]), led: true)
            == "B k=done xw=1 xs=1 led=1\n")
    #expect(encodeBanner(Banner(kind: .sit, minutes: 52, extras: []), led: false) == "B k=sit min=52 led=0\n")
    #expect(encodeBanner(Banner(kind: .breakEnded, minutes: nil, extras: []), led: true) == "B k=brk led=1\n")
}

@Test func menuStatusText() {
    var (p, now) = secondFocus()
    let stats = TodayStats(day: "2026-10-22", count: 5, focusSeconds: 7500)
    #expect(pomodoroMenuStatus(p, stats: stats, now: now) == "番茄 · 专注 12:34（第 2/4 个）")
    p.pause(now: now)
    #expect(pomodoroMenuStatus(p, stats: stats, now: now) == "番茄 · 已暂停 12:34")
    p.resume(now: now)
    _ = p.advance(now: now + 754)
    #expect(pomodoroMenuStatus(p, stats: stats, now: now + 755) == "番茄 · 短休 4:59")
    #expect(pomodoroMenuStatus(Pomodoro(), stats: stats, now: now) == "番茄 · 今天 5 个")
}

// MARK: - 快捷键冲突

@Test func hotKeyConflictDetection() {
    #expect(hotKeyConflicts(keyCode: 35, modifiers: 2304, otherKeyCode: 35, otherModifiers: 2304))
    #expect(!hotKeyConflicts(keyCode: 35, modifiers: 2304, otherKeyCode: 35, otherModifiers: 256))
    #expect(!hotKeyConflicts(keyCode: 35, modifiers: 2304, otherKeyCode: nil, otherModifiers: nil))
}

// MARK: - 审查补充：合盖过夜、改小每轮个数

@Test func overnightSleepWithoutTickAtCloseExpiresBreakEnded() {
    // 合盖时赶不上 tick：醒来第一次 tick 已经是 7 小时后（锁屏中），10 秒后解锁（t0 是上海 16:00，不跨零点）
    var r = Routine()
    r.tick(now: t0, idleSeconds: 0, gateActive: true, calendar: shanghai)
    r.start(now: t0)
    r.tick(now: t0 + 7 * 3600, idleSeconds: 0, gateActive: false, calendar: shanghai)
    r.tick(now: t0 + 7 * 3600 + 10, idleSeconds: 0, gateActive: true, calendar: shanghai)
    #expect(r.banner == nil && r.stats.count == 1)
}

@Test func overnightSleepWakingUnlockedExpiresBreakEnded() {
    // 关闭时打过点，醒来不锁屏，gate 直接打开
    var r = Routine()
    r.tick(now: t0, idleSeconds: 0, gateActive: true, calendar: shanghai)
    r.start(now: t0)
    r.tick(now: t0 + 60, idleSeconds: 0, gateActive: false, calendar: shanghai)
    r.tick(now: t0 + 8 * 3600, idleSeconds: 0, gateActive: true, calendar: shanghai)
    #expect(r.banner == nil)
}

@Test func loweringRoundsClampsRound() {
    var p = Pomodoro()
    var now = t0
    for _ in 1...2 {
        p.start(now: now)
        now += 1800
        _ = p.advance(now: now)
    }
    #expect(p.phase == .idle && p.round == 3)
    p.config.rounds = 2
    #expect(p.round == 2)
    p.start(now: now)
    _ = p.advance(now: now + 1500)
    #expect(p.phase == .long)
}
