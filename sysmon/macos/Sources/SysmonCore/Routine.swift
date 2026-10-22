import Foundation

/// 今天完成了几个番茄、专注了多久。day 是本地日期 "yyyy-MM-dd"，过了零点清零。
public struct TodayStats: Codable, Equatable, Sendable {
    public var day: String
    public var count: Int
    public var focusSeconds: Int

    public init(day: String = "", count: Int = 0, focusSeconds: Int = 0) {
        self.day = day
        self.count = count
        self.focusSeconds = focusSeconds
    }
}

/// rawValue 是串口 B 行里的 k 字段。
public enum BannerKind: String, Sendable {
    case focusDone = "done", breakEnded = "brk", sit, water
}

public struct Banner: Equatable, Sendable {
    public var kind: BannerKind
    /// sit / water 的累计在用分钟数
    public var minutes: Int?
    /// 只用于 focusDone：专注期间被压住、并进来的提醒
    public var extras: Set<HealthKind>
}

/// 把番茄钟、健康计时、横幅规则和今日统计串在一起。Mac 端只持有这一份状态。
/// 横幅优先级：专注完成 > 休息结束 > 久坐 > 喝水；处在专注阶段（含暂停）时不出久坐和喝水。
public struct Routine: Equatable, Sendable {
    /// 熄屏满这么久，“休息结束”和喝水横幅作废
    public static let gateExpiry: TimeInterval = 1800

    public var pomodoro: Pomodoro
    public var health: HealthTracker
    public private(set) var stats: TodayStats

    /// 非 nil 表示专注完成横幅在
    private var focusDoneExtras: Set<HealthKind>?
    private var breakEndedPending = false
    private var gateClosedAt: Date?

    public init(pomodoro: Pomodoro = .init(), health: HealthTracker = .init(), stats: TodayStats = .init()) {
        self.pomodoro = pomodoro
        self.health = health
        self.stats = stats
    }

    public var banner: Banner? {
        if let extras = focusDoneExtras { return Banner(kind: .focusDone, minutes: nil, extras: extras) }
        if breakEndedPending { return Banner(kind: .breakEnded, minutes: nil, extras: []) }
        guard pomodoro.phase != .focus else { return nil }
        for kind in HealthKind.allCases where health.due.contains(kind) {
            return Banner(kind: kind == .sit ? .sit : .water, minutes: health.minutes(kind), extras: [])
        }
        return nil
    }

    public mutating func tick(now: Date, idleSeconds: TimeInterval, gateActive: Bool, calendar: Calendar) {
        let today = dayString(now, calendar)
        if stats.day.isEmpty {
            // 第一次 tick：只记下日期，不算跨日
            stats.day = today
        } else if stats.day != today {
            stats = TodayStats(day: today)
            pomodoro.restartRoundWhenIdle()
        }

        for event in pomodoro.advance(now: now) {
            switch event {
            case let .focusCompleted(seconds, at):
                // 睡过零点时补算出来的昨天的番茄不计入今天
                if dayString(at, calendar) == stats.day {
                    stats.count += 1
                    stats.focusSeconds += seconds
                }
                let extras = health.due
                extras.forEach { health.acknowledge($0) }
                focusDoneExtras = extras
            case let .breakEnded(at):
                focusDoneExtras = nil
                // 睡眠醒来补算出来的、早已过时的“休息结束”不再提醒（合盖时常常赶不上记下熄屏时刻）
                breakEndedPending = now.timeIntervalSince(at) < Self.gateExpiry
            }
        }

        // 放在 advance 之后：熄屏期间补算出来的横幅也要一起作废
        if !gateActive {
            if gateClosedAt == nil { gateClosedAt = now }
        } else if let closed = gateClosedAt {
            gateClosedAt = nil
            if now.timeIntervalSince(closed) >= Self.gateExpiry {
                breakEndedPending = false
                health.acknowledge(.water)
            }
        }

        health.tick(now: now, idleSeconds: idleSeconds, gateActive: gateActive)
    }

    public mutating func toggle(now: Date) {
        let wasIdle = pomodoro.phase == .idle
        pomodoro.toggle(now: now)
        if wasIdle { breakEndedPending = false }
    }

    public mutating func start(now: Date) {
        guard pomodoro.phase == .idle else { return }
        pomodoro.start(now: now)
        breakEndedPending = false
    }

    public mutating func pause(now: Date) { pomodoro.pause(now: now) }
    public mutating func resume(now: Date) { pomodoro.resume(now: now) }

    public mutating func skip(now: Date) {
        if pomodoro.phase == .short || pomodoro.phase == .long { focusDoneExtras = nil }
        pomodoro.skip(now: now)
    }

    public mutating func resetRound() {
        if pomodoro.phase != .focus { focusDoneExtras = nil }
        pomodoro.resetRound()
    }

    /// 关掉当前横幅；没有横幅时返回 false。
    @discardableResult
    public mutating func dismissBanner() -> Bool {
        guard let current = banner else { return false }
        switch current.kind {
        case .focusDone: focusDoneExtras = nil
        case .breakEnded: breakEndedPending = false
        case .sit: health.acknowledge(.sit)
        case .water: health.acknowledge(.water)
        }
        return true
    }

    private func dayString(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
