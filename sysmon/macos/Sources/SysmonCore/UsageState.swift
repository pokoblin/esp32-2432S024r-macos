import Foundation

/// 用量数据的状态，rawValue 是串口 U 行里 st= 的取值。
public enum UsageStatus: String, Codable, Sendable {
    case ok
    case expired = "exp"
    case error = "err"
    case missing = "none"
}

/// 一个服务当前的用量状态：状态 + 最近一次成功拉取的快照。
public struct UsageState: Equatable, Codable, Sendable {
    public var status: UsageStatus
    /// 最近一次成功拉取的结果；失败时保留，方便副屏继续显示旧数据
    public var snapshot: UsageSnapshot?

    public init(status: UsageStatus = .missing, snapshot: UsageSnapshot? = nil) {
        self.status = status
        self.snapshot = snapshot
    }
}

/// 一次拉取的结果。
public enum FetchOutcome: Equatable, Sendable {
    case success(UsageSnapshot)
    case unauthorized
    case rateLimited
    case failed
    case noCredential
    case credentialExpired
}

/// 把一次拉取结果归并进状态。失败时保留旧快照。
public func reduce(_ state: UsageState, _ outcome: FetchOutcome) -> UsageState {
    var next = state
    switch outcome {
    case .success(let snapshot):
        next.status = .ok
        next.snapshot = snapshot
    case .unauthorized, .credentialExpired:
        next.status = .expired
    case .rateLimited, .failed:
        next.status = .error
    case .noCredential:
        // 以前成功过说明登录过，现在读不到凭据当作过期；从没成功过就是未登录
        next.status = state.snapshot != nil ? .expired : .missing
    }
    return next
}

/// 单个服务的拉取调度：正常每 2 分钟一次，收到 429 后退避 10 分钟。
public struct UsageSchedule: Sendable {
    public static let interval: TimeInterval = 120
    public static let backoff: TimeInterval = 600

    /// nil 表示马上就该拉取
    private var nextDue: Date?

    public init() {}

    public func isDue(now: Date) -> Bool {
        guard let nextDue else { return true }
        return now >= nextDue
    }

    public mutating func record(_ outcome: FetchOutcome, now: Date) {
        let wait = outcome == .rateLimited ? Self.backoff : Self.interval
        nextDue = now.addingTimeInterval(wait)
    }

    /// 启动、恢复亮屏、在设置里打开某个服务时调用
    public mutating func forceNext() {
        nextDue = nil
    }
}

/// 设置窗口里每个服务开关下面的灰字状态。
public func settingsStatus(_ state: UsageState, now: Date) -> String {
    switch state.status {
    case .ok:
        guard let fetched = state.snapshot?.fetchedAt else { return "读取失败" }
        return "正常 · \(ageText(now.timeIntervalSince(fetched)))更新"
    case .expired: return "已过期"
    case .error: return "读取失败"
    case .missing: return "未登录"
    }
}

/// 数据新鲜度：刚刚 / N 分钟前 / N 小时前 / N 天前。
private func ageText(_ seconds: TimeInterval) -> String {
    let s = Int(min(max(0, seconds), Double(Int32.max)))
    switch s {
    case ..<60: return "刚刚"
    case ..<3600: return "\(s / 60) 分钟前"
    case ..<86400: return "\(s / 3600) 小时前"
    default: return "\(s / 86400) 天前"
    }
}
