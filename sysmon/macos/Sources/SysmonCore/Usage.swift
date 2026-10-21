import Foundation

/// 用量屏对应的服务。rawValue 是串口协议里的服务标识。
public enum UsageService: String, CaseIterable, Codable, Sendable {
    case claude = "cl"
    case chatgpt = "gpt"
}

/// 一个用量窗口（5 小时或本周）。
public struct UsageWindow: Equatable, Codable, Sendable {
    /// 0...100，四舍五入并限幅
    public var percent: Int
    public var resetsAt: Date?
    /// 窗口长度（分钟），用来取标签；Claude 固定为 300 / 10080
    public var minutes: Int?

    public init(percent: Int, resetsAt: Date? = nil, minutes: Int? = nil) {
        self.percent = percent
        self.resetsAt = resetsAt
        self.minutes = minutes
    }
}

/// 某个服务一次拉取到的用量。
public struct UsageSnapshot: Equatable, Codable, Sendable {
    /// 小写 ASCII，例如 "max"、"plus"
    public var plan: String?
    public var fiveHour: UsageWindow?
    public var week: UsageWindow?
    /// 只有 Claude 才有
    public var opus: UsageWindow?
    public var sonnet: UsageWindow?
    public var fetchedAt: Date

    public init(plan: String? = nil, fiveHour: UsageWindow? = nil, week: UsageWindow? = nil,
                opus: UsageWindow? = nil, sonnet: UsageWindow? = nil, fetchedAt: Date) {
        self.plan = plan
        self.fiveHour = fiveHour
        self.week = week
        self.opus = opus
        self.sonnet = sonnet
        self.fetchedAt = fetchedAt
    }
}

/// 响应不是预期的 JSON，或两个主窗口都缺失。
public struct UsageParseError: Error {
    public init() {}
}

private let fiveHourMinutes = 300
private let weekMinutes = 10080

/// 套餐名规范化：小写、去空白、只留 ASCII 字母数字和 "-" "_"；空则为 nil。
private func normalizePlan(_ plan: String?) -> String? {
    guard let plan else { return nil }
    let cleaned = plan.lowercased().unicodeScalars.filter {
        $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
    }
    let s = String(String.UnicodeScalarView(cleaned))
    return s.isEmpty ? nil : s
}

private func clampPercent(_ v: Double) -> Int {
    guard v.isFinite else { return 0 }
    return Int(min(100, max(0, v.rounded())))
}

/// 解析 ISO8601，带不带小数秒都接受。
private func parseISO8601(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        throw UsageParseError()
    }
    return obj
}

private func number(_ v: Any?) -> Double? {
    // JSONSerialization 的布尔也是 NSNumber，排除掉
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
}

private func claudeWindow(_ raw: Any?, minutes: Int) -> UsageWindow? {
    guard let d = raw as? [String: Any], let u = number(d["utilization"]) else { return nil }
    let reset = (d["resets_at"] as? String).flatMap(parseISO8601)
    return UsageWindow(percent: clampPercent(u), resetsAt: reset, minutes: minutes)
}

/// 解析 api.anthropic.com/api/oauth/usage 的响应。套餐不在响应里，由调用方传入。
public func parseClaudeUsage(_ data: Data, plan: String?, now: Date) throws -> UsageSnapshot {
    let obj = try jsonObject(data)
    let five = claudeWindow(obj["five_hour"], minutes: fiveHourMinutes)
    let week = claudeWindow(obj["seven_day"], minutes: weekMinutes)
    guard five != nil || week != nil else { throw UsageParseError() }
    return UsageSnapshot(
        plan: normalizePlan(plan),
        fiveHour: five,
        week: week,
        opus: claudeWindow(obj["seven_day_opus"], minutes: weekMinutes),
        sonnet: claudeWindow(obj["seven_day_sonnet"], minutes: weekMinutes),
        fetchedAt: now)
}

private func codexWindow(_ raw: Any?) -> (window: UsageWindow, seconds: Int?)? {
    guard let d = raw as? [String: Any], let used = number(d["used_percent"]) else { return nil }
    let seconds = number(d["limit_window_seconds"]).map { Int($0) }
    let reset = number(d["reset_at"]).map { Date(timeIntervalSince1970: $0) }
    return (UsageWindow(percent: clampPercent(used), resetsAt: reset, minutes: seconds.map { $0 / 60 }), seconds)
}

/// 解析 chatgpt.com/backend-api/wham/usage 的响应。
/// 窗口按长度归类（18000 秒 → 5 小时，604800 秒 → 本周）；
/// 长度不认识的窗口按 primary → 5 小时、secondary → 本周处理。
public func parseCodexUsage(_ data: Data, now: Date) throws -> UsageSnapshot {
    let obj = try jsonObject(data)
    guard let limit = obj["rate_limit"] as? [String: Any] else { throw UsageParseError() }
    let windows = [codexWindow(limit["primary_window"]), codexWindow(limit["secondary_window"])]

    var five: UsageWindow?
    var week: UsageWindow?
    var unclassified: [(index: Int, window: UsageWindow)] = []
    for (i, entry) in windows.enumerated() {
        guard let entry else { continue }
        switch entry.seconds {
        case fiveHourMinutes * 60 where five == nil: five = entry.window
        case weekMinutes * 60 where week == nil: week = entry.window
        default: unclassified.append((i, entry.window))
        }
    }
    for (i, w) in unclassified {
        NSLog("Sysmon: Codex 用量窗口长度未知（%@ 分钟），按位置归类", w.minutes.map(String.init) ?? "?")
        if i == 0, five == nil { five = w } else if i == 1, week == nil { week = w }
    }
    guard five != nil || week != nil else { throw UsageParseError() }
    return UsageSnapshot(plan: normalizePlan(obj["plan_type"] as? String),
                         fiveHour: five, week: week, fetchedAt: now)
}
