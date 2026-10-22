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

/// 按模型单独计算的额度窗口，name 是接口给的模型显示名（例如 "Fable"）。
public struct ModelWindow: Equatable, Codable, Sendable {
    public var name: String
    public var window: UsageWindow

    public init(name: String, window: UsageWindow) {
        self.name = name
        self.window = window
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
    /// 只有 Claude 才有：limits 里第一条按模型的每周额度（升级前持久化的快照里没有，解码为 nil）
    public var modelWeek: ModelWindow?
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
func normalizePlan(_ plan: String?) -> String? {
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

func number(_ v: Any?) -> Double? {
    // JSONSerialization 的布尔也是 NSNumber，排除掉
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
}

private func claudeWindow(_ raw: Any?, minutes: Int) -> UsageWindow? {
    guard let d = raw as? [String: Any], let u = number(d["utilization"]) else { return nil }
    let reset = (d["resets_at"] as? String).flatMap(parseISO8601)
    return UsageWindow(percent: clampPercent(u), resetsAt: reset, minutes: minutes)
}

/// limits 里第一条按模型的每周额度（kind 为 weekly_scoped 且 scope.model 有名字和百分比）。
/// 按产品（scope.surface）分的额度不算。
private func claudeModelWeek(_ raw: Any?) -> ModelWindow? {
    guard let limits = raw as? [[String: Any]] else { return nil }
    for limit in limits where limit["kind"] as? String == "weekly_scoped" {
        let scope = limit["scope"] as? [String: Any]
        guard let model = scope?["model"] as? [String: Any],
              let name = model["display_name"] as? String, !name.isEmpty,
              let percent = number(limit["percent"]) else { continue }
        let reset = (limit["resets_at"] as? String).flatMap(parseISO8601)
        return ModelWindow(name: name, window: UsageWindow(percent: clampPercent(percent), resetsAt: reset,
                                                           minutes: weekMinutes))
    }
    return nil
}

/// 解析 api.anthropic.com/api/oauth/usage 的响应。套餐不在响应里，由调用方传入。
public func parseClaudeUsage(_ data: Data, plan: String?, now: Date) throws -> UsageSnapshot {
    let obj = try jsonObject(data)
    let five = claudeWindow(obj["five_hour"], minutes: fiveHourMinutes)
    let week = claudeWindow(obj["seven_day"], minutes: weekMinutes)
    guard five != nil || week != nil else { throw UsageParseError() }
    var snapshot = UsageSnapshot(
        plan: normalizePlan(plan),
        fiveHour: five,
        week: week,
        opus: claudeWindow(obj["seven_day_opus"], minutes: weekMinutes),
        sonnet: claudeWindow(obj["seven_day_sonnet"], minutes: weekMinutes),
        fetchedAt: now)
    snapshot.modelWeek = claudeModelWeek(obj["limits"])
    return snapshot
}

/// reset_at（Unix 秒）只接受 2000 年之后、不超过现在起一年的值；
/// 非有限数或离谱的数字当作没有，避免后面的日期换算溢出。
private func saneResetDate(_ seconds: Double?, now: Date) -> Date? {
    guard let seconds, seconds.isFinite else { return nil }
    let earliest = 946_684_800.0   // 2000-01-01 UTC
    let latest = now.timeIntervalSince1970 + 366 * 86400
    guard seconds >= earliest, seconds <= latest else { return nil }
    return Date(timeIntervalSince1970: seconds)
}

private func codexWindow(_ raw: Any?, now: Date) -> (window: UsageWindow, seconds: Int?)? {
    guard let d = raw as? [String: Any], let used = number(d["used_percent"]) else { return nil }
    // 超出 Int 范围或非有限数时 Int(exactly:) 返回 nil，按窗口长度未知处理
    let seconds = number(d["limit_window_seconds"]).flatMap { Int(exactly: $0) }
    let reset = saneResetDate(number(d["reset_at"]), now: now)
    return (UsageWindow(percent: clampPercent(used), resetsAt: reset, minutes: seconds.map { $0 / 60 }), seconds)
}

/// 解析 chatgpt.com/backend-api/wham/usage 的响应。
/// 窗口按长度归类（18000 秒 → 5 小时，604800 秒 → 本周）；
/// 长度不认识的窗口按 primary → 5 小时、secondary → 本周处理。
public func parseCodexUsage(_ data: Data, now: Date) throws -> UsageSnapshot {
    let obj = try jsonObject(data)
    guard let limit = obj["rate_limit"] as? [String: Any] else { throw UsageParseError() }
    let windows = [codexWindow(limit["primary_window"], now: now), codexWindow(limit["secondary_window"], now: now)]

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
