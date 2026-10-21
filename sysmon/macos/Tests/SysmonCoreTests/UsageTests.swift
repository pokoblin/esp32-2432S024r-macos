import Foundation
import Testing
@testable import SysmonCore

private func iso(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

@Test func parsesClaudeUsage() throws {
    let s = try parseClaudeUsage(Data(UsageFixtures.claude.utf8), plan: "max", now: .init(timeIntervalSince1970: 0))
    #expect(s.fiveHour?.percent == 37)
    #expect(s.week?.percent == 12)
    #expect(s.opus?.percent == 5)
    #expect(s.sonnet?.percent == 8)
    #expect(s.fiveHour?.resetsAt != nil)
    // 小数秒被舍弃前后的差别不超过 1 秒
    let reset = try #require(s.fiveHour?.resetsAt)
    #expect(abs(reset.timeIntervalSince(iso("2026-10-21T14:00:00Z"))) < 1)
    #expect(s.fiveHour?.minutes == 300 && s.week?.minutes == 10080)
    #expect(s.opus?.minutes == 10080 && s.sonnet?.minutes == 10080)
    #expect(s.plan == "max")
    #expect(s.fetchedAt == Date(timeIntervalSince1970: 0))
}

@Test func claudeNullWindowsAreOmitted() throws {
    let s = try parseClaudeUsage(Data(UsageFixtures.claudeNulls.utf8), plan: nil, now: .init(timeIntervalSince1970: 0))
    #expect(s.opus == nil)
    #expect(s.sonnet != nil && s.sonnet?.resetsAt == nil)
    #expect(s.sonnet?.percent == 8)
    #expect(s.plan == nil)
}

@Test func claudeAcceptsResetsWithoutFractionalSeconds() throws {
    let json = #"{"five_hour":{"utilization":10,"resets_at":"2026-10-21T14:00:00Z"},"seven_day":{"utilization":20,"resets_at":"2026-10-23T06:00:00+00:00"}}"#
    let s = try parseClaudeUsage(Data(json.utf8), plan: nil, now: .init(timeIntervalSince1970: 0))
    #expect(s.fiveHour?.resetsAt == iso("2026-10-21T14:00:00Z"))
    #expect(s.week?.resetsAt == iso("2026-10-23T06:00:00Z"))
}

@Test func claudeNormalizesPlan() throws {
    let s = try parseClaudeUsage(Data(UsageFixtures.claude.utf8), plan: "Max", now: .init(timeIntervalSince1970: 0))
    #expect(s.plan == "max")
    let empty = try parseClaudeUsage(Data(UsageFixtures.claude.utf8), plan: "", now: .init(timeIntervalSince1970: 0))
    #expect(empty.plan == nil)
}

@Test func claudeAcceptsOneMainWindow() throws {
    let json = #"{"five_hour":{"utilization":10,"resets_at":null},"seven_day":null}"#
    let s = try parseClaudeUsage(Data(json.utf8), plan: nil, now: .init(timeIntervalSince1970: 0))
    #expect(s.fiveHour?.percent == 10)
    #expect(s.week == nil)
}

@Test func parsesCodexUsage() throws {
    let s = try parseCodexUsage(Data(UsageFixtures.codex.utf8), now: .init(timeIntervalSince1970: 0))
    #expect(s.fiveHour?.minutes == 300 && s.week?.minutes == 10080)
    #expect(s.fiveHour?.percent == 0)
    #expect(s.week?.percent == 1)
    #expect(s.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_792_581_976))
    #expect(s.week?.resetsAt == Date(timeIntervalSince1970: 1_793_090_928))
    #expect(s.plan == "plus")
    #expect(s.opus == nil && s.sonnet == nil)
    #expect(s.fetchedAt == Date(timeIntervalSince1970: 0))
}

@Test func codexClassifiesWindowsByLength() throws {
    // primary / secondary 顺序颠倒时，仍按长度归类
    let json = #"""
    {"plan_type":"Pro","rate_limit":{
      "primary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_at":1000},
      "secondary_window":{"used_percent":7,"limit_window_seconds":18000,"reset_at":2000}}}
    """#
    let s = try parseCodexUsage(Data(json.utf8), now: .init(timeIntervalSince1970: 0))
    #expect(s.fiveHour?.percent == 7 && s.fiveHour?.minutes == 300)
    #expect(s.week?.percent == 40 && s.week?.minutes == 10080)
    #expect(s.plan == "pro")
}

@Test func codexUnknownWindowLengthFallsBackToPosition() throws {
    let json = #"""
    {"plan_type":"plus","rate_limit":{
      "primary_window":{"used_percent":10,"limit_window_seconds":3600,"reset_at":1000},
      "secondary_window":{"used_percent":20,"limit_window_seconds":86400,"reset_at":2000}}}
    """#
    let s = try parseCodexUsage(Data(json.utf8), now: .init(timeIntervalSince1970: 0))
    #expect(s.fiveHour?.percent == 10 && s.fiveHour?.minutes == 60)
    #expect(s.week?.percent == 20 && s.week?.minutes == 1440)
}

@Test func usageParseRejectsGarbage() {
    #expect(throws: UsageParseError.self) { try parseClaudeUsage(Data("{}".utf8), plan: nil, now: .now) }
    #expect(throws: UsageParseError.self) { try parseClaudeUsage(Data("nope".utf8), plan: nil, now: .now) }
    #expect(throws: UsageParseError.self) { try parseCodexUsage(Data("nope".utf8), now: .now) }
    #expect(throws: UsageParseError.self) { try parseCodexUsage(Data(#"{"plan_type":"plus","rate_limit":null}"#.utf8), now: .now) }
}

@Test func percentIsRoundedAndClamped() throws {
    let json = #"{"five_hour":{"utilization":42.6,"resets_at":null},"seven_day":{"utilization":130,"resets_at":null},"seven_day_opus":{"utilization":-1,"resets_at":null}}"#
    let s = try parseClaudeUsage(Data(json.utf8), plan: nil, now: .init(timeIntervalSince1970: 0))
    #expect(s.fiveHour?.percent == 43)
    #expect(s.week?.percent == 100)
    #expect(s.opus?.percent == 0)
}

@Test func usageServiceRawValues() {
    #expect(UsageService.claude.rawValue == "cl")
    #expect(UsageService.chatgpt.rawValue == "gpt")
    #expect(UsageService.allCases.count == 2)
}

// MARK: - 凭据解析（只读）

@Test func parsesClaudeKeychain() {
    let c = parseClaudeKeychainJSON(Data(UsageFixtures.claudeKeychain.utf8))
    #expect(c?.accessToken == "sk-ant-oat01-FAKE-ACCESS-TOKEN")
    #expect(c?.plan == "max")
    #expect(c?.expiresAt == Date(timeIntervalSince1970: 1_800_000_000_000 / 1000))
}

@Test func claudeKeychainIgnoresExtraTopLevelKeys() {
    // 真实钥匙串里除了 claudeAiOauth 还有 mcpOAuth 之类的顶层键
    let json = #"{"mcpOAuth":{"x":{"accessToken":"other"}},"claudeAiOauth":{"accessToken":"t","expiresAt":1800000000000,"subscriptionType":"Max"}}"#
    let c = parseClaudeKeychainJSON(Data(json.utf8))
    #expect(c?.accessToken == "t")
    #expect(c?.plan == "max")
}

@Test func parsesCodexAuth() {
    let c = parseCodexAuthJSON(Data(UsageFixtures.codexAuth.utf8))
    #expect(c?.accessToken.hasPrefix("eyJ") == true)
    #expect(c?.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    #expect(c?.accountID == "00000000-0000-0000-0000-000000000000")
}

@Test func malformedJWTHasUnknownExpiry() {
    #expect(jwtExpiry("not-a-jwt") == nil)
    #expect(jwtExpiry("a.e30.c") == nil)   // payload 是 {}，没有 exp
    #expect(jwtExpiry("a.!!!.c") == nil)   // payload 不是合法 base64
}

@Test func jwtExpiryHandlesBase64URLPadding() {
    // {"exp":1800000000} 的 base64url 无 padding 形式
    #expect(jwtExpiry("h.eyJleHAiOjE4MDAwMDAwMDB9.s") == Date(timeIntervalSince1970: 1_800_000_000))
    // {"exp":1,"a":"??>>"} 编码后含 "-" 和 "_"
    let payload = Data(#"{"exp":1,"a":"??>>~~"}"#.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    #expect(jwtExpiry("h.\(payload).s") == Date(timeIntervalSince1970: 1))
}

@Test func credentialDescriptionsHideTokens() {
    let c = parseClaudeKeychainJSON(Data(UsageFixtures.claudeKeychain.utf8))!
    #expect(!"\(c)".contains(c.accessToken))
    let x = parseCodexAuthJSON(Data(UsageFixtures.codexAuth.utf8))!
    #expect(!"\(x)".contains(x.accessToken))
}

@Test func missingFieldsGiveNil() {
    #expect(parseClaudeKeychainJSON(Data("{}".utf8)) == nil)
    #expect(parseClaudeKeychainJSON(Data("not json".utf8)) == nil)
    #expect(parseCodexAuthJSON(Data(#"{"tokens":{}}"#.utf8)) == nil)
    #expect(parseCodexAuthJSON(Data(#"{"tokens":{"access_token":"a"}}"#.utf8)) == nil)   // 缺 account_id
}

@Test func readCodexCredentialFromHome() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("sysmon-test-\(UUID().uuidString)")
    let dir = home.appendingPathComponent(".codex")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(readCodexCredential(home: home) == nil)   // 文件不存在
    try Data(UsageFixtures.codexAuth.utf8).write(to: dir.appendingPathComponent("auth.json"))
    #expect(readCodexCredential(home: home)?.accountID == "00000000-0000-0000-0000-000000000000")
}

// MARK: - 页面轮换与 P/U/TAP 协议行

private let shanghai: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}()

/// 2026-10-21 12:00:00 Asia/Shanghai，周三
private let protoNow = shanghai.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!

@Test func pageCycle() {
    let all = enabledPages(claude: true, chatgpt: true)
    #expect(all == [.sys, .claude, .chatgpt])
    #expect(nextPage(after: .sys, enabled: all) == .claude)
    #expect(nextPage(after: .chatgpt, enabled: all) == .sys)
    let noClaude = enabledPages(claude: false, chatgpt: true)
    #expect(nextPage(after: .sys, enabled: noClaude) == .chatgpt)
    #expect(nextPage(after: .sys, enabled: [.sys]) == .sys)
    #expect(resolvePage(.claude, enabled: noClaude) == .sys)
}

@Test func encodesPageLine() {
    #expect(encodePage(.claude, enabled: [.sys, .claude, .chatgpt]) == "P cl i=2 n=3\n")
    #expect(encodePage(.sys, enabled: [.sys]) == "P sys i=1 n=1\n")
}

@Test func encodesUsageLine() {
    let thursday = shanghai.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 14))!
    let snap = UsageSnapshot(
        plan: "max",
        fiveHour: UsageWindow(percent: 42, resetsAt: protoNow.addingTimeInterval(7980)),
        week: UsageWindow(percent: 67, resetsAt: thursday),
        opus: UsageWindow(percent: 12, resetsAt: thursday),
        sonnet: UsageWindow(percent: 28, resetsAt: thursday),
        fetchedAt: protoNow.addingTimeInterval(-60))
    let line = encodeUsage(.claude, status: .ok, snapshot: snap, now: protoNow, calendar: shanghai)
    #expect(line == "U svc=cl st=ok age=60 plan=max h5=42 h5r=7980 wk=67 wkd=4 wkt=1400 op=12 so=28\n")
    #expect(line.utf8.count <= 128)
}

@Test func usageWindowPastResetEncodesMinusOne() {
    let past = protoNow.addingTimeInterval(-10)
    let snap = UsageSnapshot(
        plan: "plus",
        fiveHour: UsageWindow(percent: 90, resetsAt: past),
        week: UsageWindow(percent: 50, resetsAt: past),
        fetchedAt: protoNow)
    let line = encodeUsage(.chatgpt, status: .ok, snapshot: snap, now: protoNow, calendar: shanghai)
    #expect(line.contains(" h5=-1") && !line.contains("h5r=") && line.contains(" wk=-1") && !line.contains("wkd="))
    #expect(!line.contains("wkt="))
}

@Test func usageWithoutSnapshotHasNoNumbers() {
    #expect(encodeUsage(.claude, status: .expired, snapshot: nil, now: protoNow, calendar: shanghai) == "U svc=cl st=exp\n")
}

@Test func usageOmitsMissingFields() {
    let snap = UsageSnapshot(
        plan: nil,
        fiveHour: UsageWindow(percent: 10, resetsAt: protoNow.addingTimeInterval(60)),
        week: nil,
        opus: nil,
        sonnet: UsageWindow(percent: 28, resetsAt: nil),
        fetchedAt: protoNow)
    let line = encodeUsage(.claude, status: .ok, snapshot: snap, now: protoNow, calendar: shanghai)
    #expect(line == "U svc=cl st=ok age=0 h5=10 h5r=60 so=28\n")
    #expect(!line.contains("op=") && !line.contains("plan=") && !line.contains("wk="))
}

@Test func usagePlanIsSanitized() {
    let snap = UsageSnapshot(plan: "Max-20x_Team Plus!", fetchedAt: protoNow)
    let line = encodeUsage(.claude, status: .ok, snapshot: snap, now: protoNow, calendar: shanghai)
    // 只留小写字母数字，最多 10 个字符（大写字母被丢弃）
    #expect(line == "U svc=cl st=ok age=0 plan=ax20xeamlu\n")
    let empty = UsageSnapshot(plan: "---", fetchedAt: protoNow)
    #expect(!encodeUsage(.claude, status: .ok, snapshot: empty, now: protoNow, calendar: shanghai).contains("plan="))
}

@Test func tapLineIsExact() {
    #expect(isTapLine("TAP"))
    #expect(isTapLine("TAP\r"))
    #expect(!isTapLine("xTAP"))
    #expect(!isTapLine("TAPx"))
    #expect(!isTapLine("rst:0x1 TAP"))
}
