import Foundation

/// 番茄钟的时长设置，单位分钟。rounds 是每轮几个专注，最后一个之后长休。
public struct PomodoroConfig: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var rounds: Int

    public init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 15, rounds: Int = 4) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.rounds = rounds
    }
}

/// rawValue 是串口 T 行里的 st 字段。
public enum PomodoroPhase: String, Codable, Sendable {
    case idle, focus, short, long
}

public enum PomodoroEvent: Equatable, Sendable {
    /// at 是这一段本该结束的时刻（Mac 睡眠醒来补算时也按它记账）
    case focusCompleted(seconds: Int, at: Date)
    case breakEnded(at: Date)
}

/// 番茄钟状态机。时间都从外面传进来，按真实时间走：记“预计结束时刻”，暂停时记剩余秒数。
/// 只有专注要手动开始；专注走完自动进入休息，休息走完回到空闲。
public struct Pomodoro: Equatable, Sendable {
    public var config: PomodoroConfig
    public private(set) var phase: PomodoroPhase = .idle
    public private(set) var isRunning = false
    /// 从 1 起；专注和空闲时是当前或下一个，休息时是刚做完的那个
    public private(set) var round = 1
    /// 只有走着时非 nil
    public private(set) var endsAt: Date?

    /// 本段总秒数，进入这一段时按当时的设置定下，之后改设置不影响
    private var segmentTotal = 0
    private var pausedRemaining = 0
    /// 过了零点：下次回到空闲时从第 1 个算起
    private var restartRoundPending = false

    public init(config: PomodoroConfig = .init()) {
        self.config = config
    }

    /// 本段总秒数；空闲时是下一段专注的时长（跟着设置走）。
    public func total(now: Date) -> Int {
        phase == .idle ? config.focusMinutes * 60 : segmentTotal
    }

    public func remaining(now: Date) -> Int {
        if phase == .idle { return total(now: now) }
        if let endsAt { return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up))) }
        return pausedRemaining
    }

    /// 只在空闲时有效。
    public mutating func start(now: Date) {
        guard phase == .idle else { return }
        enter(.focus, total: config.focusMinutes * 60, from: now)
    }

    public mutating func pause(now: Date) {
        guard isRunning, endsAt != nil else { return }
        pausedRemaining = remaining(now: now)
        endsAt = nil
        isRunning = false
    }

    public mutating func resume(now: Date) {
        guard phase != .idle, !isRunning else { return }
        endsAt = now + TimeInterval(pausedRemaining)
        isRunning = true
    }

    /// 快捷键的语义：空闲→开始，走着→暂停，暂停→继续。
    public mutating func toggle(now: Date) {
        if phase == .idle {
            start(now: now)
        } else if isRunning {
            pause(now: now)
        } else {
            resume(now: now)
        }
    }

    /// 专注中跳过：放弃这个番茄，轮次不变；休息中跳过：提前结束休息，轮次照常前进。
    public mutating func skip(now: Date) {
        switch phase {
        case .idle: return
        case .focus: goIdle()
        case .short, .long: finishBreak()
        }
    }

    public mutating func resetRound() {
        goIdle()
        round = 1
        restartRoundPending = false
    }

    public mutating func restartRoundWhenIdle() {
        if phase == .idle {
            round = 1
        } else {
            restartRoundPending = true
        }
    }

    /// 推进到 now；Mac 睡眠醒来时可能一次跨过几段，事件按发生顺序返回。
    public mutating func advance(now: Date) -> [PomodoroEvent] {
        var events: [PomodoroEvent] = []
        while isRunning, let end = endsAt, end <= now {
            switch phase {
            case .focus:
                events.append(.focusCompleted(seconds: segmentTotal, at: end))
                let long = round >= config.rounds
                // 下一段从上一段的结束时刻算起，不从 now 算
                enter(long ? .long : .short,
                      total: (long ? config.longBreakMinutes : config.shortBreakMinutes) * 60, from: end)
            case .short, .long:
                events.append(.breakEnded(at: end))
                finishBreak()
            case .idle:
                return events
            }
        }
        return events
    }

    private mutating func enter(_ next: PomodoroPhase, total: Int, from start: Date) {
        phase = next
        segmentTotal = total
        endsAt = start + TimeInterval(total)
        isRunning = true
    }

    private mutating func finishBreak() {
        round = phase == .long ? 1 : round + 1
        goIdle()
    }

    private mutating func goIdle() {
        phase = .idle
        isRunning = false
        endsAt = nil
        pausedRemaining = 0
        if restartRoundPending {
            round = 1
            restartRoundPending = false
        }
    }
}
