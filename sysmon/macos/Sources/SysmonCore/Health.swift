import Foundation

/// 健康提醒的设置，间隔单位分钟。
public struct HealthConfig: Codable, Equatable, Sendable {
    public var sitEnabled: Bool
    public var sitMinutes: Int
    public var waterEnabled: Bool
    public var waterMinutes: Int

    public init(sitEnabled: Bool = true, sitMinutes: Int = 50, waterEnabled: Bool = true, waterMinutes: Int = 60) {
        self.sitEnabled = sitEnabled
        self.sitMinutes = sitMinutes
        self.waterEnabled = waterEnabled
        self.waterMinutes = waterMinutes
    }
}

public enum HealthKind: String, Codable, CaseIterable, Sendable {
    case sit, water
}

/// 久坐和喝水两个计时器，只累计“在用电脑”的时间。
/// 离开时长 = 距最后一次键鼠输入过了多久；gate 关闭（锁屏、显示器睡眠等）期间不认输入，
/// 所以闲置和熄屏首尾相接时自然合在一起算。一段离开满 5 分钟久坐清零，满 30 分钟喝水清零。
public struct HealthTracker: Equatable, Sendable {
    public static let sitAwayReset: TimeInterval = 300
    public static let waterAwayReset: TimeInterval = 1800
    /// 闲置不到 60 秒算“在用”
    public static let inUseIdleLimit: TimeInterval = 60
    /// 两次 tick 间隔超过它不累计（睡眠、卡顿）
    public static let maxTickGap: TimeInterval = 10

    public var config: HealthConfig {
        didSet { dropDisabled() }
    }
    /// 到点且还没处理
    public private(set) var due: Set<HealthKind> = []

    private var sitSeconds: TimeInterval = 0
    private var waterSeconds: TimeInterval = 0
    private var lastInput: Date?
    private var lastTick: Date?

    public init(config: HealthConfig = .init()) {
        self.config = config
    }

    public func minutes(_ kind: HealthKind) -> Int {
        Int(seconds(kind) / 60)
    }

    public func awaySeconds(now: Date) -> TimeInterval {
        guard let lastInput else { return 0 }
        let away = now.timeIntervalSince(lastInput)
        return away < Self.inUseIdleLimit ? 0 : away
    }

    public mutating func tick(now: Date, idleSeconds: TimeInterval, gateActive: Bool) {
        if gateActive {
            let input = now - idleSeconds
            if let last = lastInput {
                // 新的输入比上一次晚了一大截：中间那段离开刚结束
                resetAfterAway(input.timeIntervalSince(last))
                lastInput = max(last, input)
            } else {
                lastInput = input
            }
        } else if lastInput == nil {
            lastInput = now
        }
        resetAfterAway(awaySeconds(now: now))

        if gateActive, idleSeconds < Self.inUseIdleLimit, let lastTick {
            let dt = now.timeIntervalSince(lastTick)
            if dt > 0, dt <= Self.maxTickGap {
                sitSeconds += dt
                waterSeconds += dt
            }
        }
        lastTick = now

        if config.sitEnabled, sitSeconds >= TimeInterval(config.sitMinutes * 60) { due.insert(.sit) }
        if config.waterEnabled, waterSeconds >= TimeInterval(config.waterMinutes * 60) { due.insert(.water) }
    }

    public mutating func acknowledge(_ kind: HealthKind) {
        switch kind {
        case .sit: sitSeconds = 0
        case .water: waterSeconds = 0
        }
        due.remove(kind)
    }

    private func seconds(_ kind: HealthKind) -> TimeInterval {
        kind == .sit ? sitSeconds : waterSeconds
    }

    private mutating func resetAfterAway(_ away: TimeInterval) {
        if away >= Self.sitAwayReset { acknowledge(.sit) }
        if away >= Self.waterAwayReset { acknowledge(.water) }
    }

    private mutating func dropDisabled() {
        if !config.sitEnabled { due.remove(.sit) }
        if !config.waterEnabled { due.remove(.water) }
    }
}
