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
    #expect(s.fiveHour?.percent == 8)
    #expect(s.week?.percent == 23)
    // 真实响应里这个账号没有 Opus / Sonnet 单独的额度
    #expect(s.opus == nil && s.sonnet == nil)
    // 小数秒被舍弃前后的差别不超过 1 秒
    let reset = try #require(s.fiveHour?.resetsAt)
    #expect(abs(reset.timeIntervalSince(iso("2026-10-21T09:09:59Z"))) < 1)
    let weekReset = try #require(s.week?.resetsAt)
    #expect(abs(weekReset.timeIntervalSince(iso("2026-10-24T11:59:59Z"))) < 1)
    #expect(s.fiveHour?.minutes == 300 && s.week?.minutes == 10080)
    #expect(s.plan == "max")
    #expect(s.fetchedAt == Date(timeIntervalSince1970: 0))
    // limits 里按模型单独计算的每周额度
    #expect(s.modelWeek == ModelWindow(
        name: "Fable", window: UsageWindow(percent: 0, resetsAt: iso("2026-10-24T12:00:00Z"), minutes: 10080)))
}

@Test func claudeModelWeekTakesFirstModelScopedLimit() throws {
    func modelWeek(_ limits: String) throws -> ModelWindow? {
        let json = #"{"five_hour":{"utilization":1,"resets_at":null},"limits":"# + limits + "}"
        return try parseClaudeUsage(Data(json.utf8), plan: nil, now: .init(timeIntervalSince1970: 0)).modelWeek
    }
    let surface = #"{"kind":"weekly_scoped","percent":40,"scope":{"model":null,"surface":{"display_name":"Cowork"}}}"#
    let noName = #"{"kind":"weekly_scoped","percent":30,"scope":{"model":{"display_name":""}}}"#
    let noPercent = #"{"kind":"weekly_scoped","scope":{"model":{"display_name":"Opus"}}}"#
    let fable = #"{"kind":"weekly_scoped","percent":61.6,"resets_at":"2026-10-24T12:00:00+00:00","scope":{"model":{"display_name":"Fable"}}}"#
    let other = #"{"kind":"weekly_scoped","percent":5,"scope":{"model":{"display_name":"Sonnet"}}}"#
    let weeklyAll = #"{"kind":"weekly_all","percent":23,"scope":null}"#
    // 只认按模型的 weekly_scoped，跳过没有名字或百分比的，取第一条
    #expect(try modelWeek("[\(weeklyAll),\(surface),\(noName),\(noPercent),\(fable),\(other)]")
        == ModelWindow(name: "Fable", window: UsageWindow(percent: 62, resetsAt: iso("2026-10-24T12:00:00Z"), minutes: 10080)))
    #expect(try modelWeek("[\(weeklyAll),\(surface)]") == nil)
    #expect(try modelWeek("null") == nil)
    #expect(try modelWeek(#""oops""#) == nil)
}

@Test func snapshotWithoutModelWeekDecodesFromOldPersistedJSON() throws {
    // 升级前持久化的快照没有 modelWeek 字段，照样能读出来
    let old = #"{"plan":"max","fetchedAt":0,"fiveHour":{"percent":5}}"#
    let s = try JSONDecoder().decode(UsageSnapshot.self, from: Data(old.utf8))
    #expect(s.modelWeek == nil && s.fiveHour?.percent == 5)
}

@Test func parsesClaudeOpusAndSonnetWindows() throws {
    let json = #"{"five_hour":{"utilization":10,"resets_at":"2026-10-21T14:00:00+00:00"},"seven_day":{"utilization":20,"resets_at":"2026-10-23T06:00:00+00:00"},"seven_day_opus":{"utilization":5.0,"resets_at":"2026-10-23T06:00:00+00:00"},"seven_day_sonnet":{"utilization":8.4,"resets_at":"2026-10-23T06:00:00+00:00"}}"#
    let s = try parseClaudeUsage(Data(json.utf8), plan: nil, now: .init(timeIntervalSince1970: 0))
    #expect(s.opus?.percent == 5)
    #expect(s.sonnet?.percent == 8)
    #expect(s.opus?.minutes == 10080 && s.sonnet?.minutes == 10080)
    #expect(s.opus?.resetsAt == iso("2026-10-23T06:00:00Z"))
}

@Test func claudeNullWindowsAreOmitted() throws {
    let s = try parseClaudeUsage(Data(UsageFixtures.claudeNulls.utf8), plan: nil, now: .init(timeIntervalSince1970: 0))
    #expect(s.opus == nil)
    #expect(s.sonnet != nil && s.sonnet?.resetsAt == nil)
    #expect(s.sonnet?.percent == 23)
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
    // now 取夹具采集当天，reset_at 才落在「现在起一年内」
    let now = Date(timeIntervalSince1970: 1_792_570_000)
    let s = try parseCodexUsage(Data(UsageFixtures.codex.utf8), now: now)
    #expect(s.fiveHour?.minutes == 300 && s.week?.minutes == 10080)
    #expect(s.fiveHour?.percent == 0)
    #expect(s.week?.percent == 1)
    #expect(s.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_792_581_976))
    #expect(s.week?.resetsAt == Date(timeIntervalSince1970: 1_793_090_928))
    #expect(s.plan == "plus")
    #expect(s.opus == nil && s.sonnet == nil)
    #expect(s.fetchedAt == now)
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

@Test func codexHugeNumbersDoNotTrap() throws {
    // 远端给出超出 Int / 合理日期范围的数字时不能崩溃：窗口长度当作未知，重置时间当作没有
    let json = #"""
    {"plan_type":"plus","rate_limit":{
      "primary_window":{"used_percent":10,"limit_window_seconds":1e30,"reset_at":1e300},
      "secondary_window":{"used_percent":20,"limit_window_seconds":604800,"reset_at":-1e300}}}
    """#
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let s = try parseCodexUsage(Data(json.utf8), now: now)
    #expect(s.fiveHour?.percent == 10 && s.fiveHour?.minutes == nil && s.fiveHour?.resetsAt == nil)
    #expect(s.week?.percent == 20 && s.week?.resetsAt == nil)
}

@Test func codexResetAtOutsideSaneRangeIsIgnored() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func reset(_ v: String) throws -> Date? {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":1,"limit_window_seconds":18000,"reset_at":\#(v)}}}"#
        return try parseCodexUsage(Data(json.utf8), now: now).fiveHour?.resetsAt
    }
    #expect(try reset("1800003600") == Date(timeIntervalSince1970: 1_800_003_600))
    #expect(try reset("1900000000") == nil)   // 超过 now + 1 年
    #expect(try reset("900000000") == nil)    // 早于 2000 年
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
    let all = enabledPages(pomodoro: false, claude: true, chatgpt: true)
    #expect(all == [.sys, .claude, .chatgpt])
    #expect(nextPage(after: .sys, enabled: all) == .claude)
    #expect(nextPage(after: .chatgpt, enabled: all) == .sys)
    let noClaude = enabledPages(pomodoro: false, claude: false, chatgpt: true)
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

@Test func encodesModelWeek() {
    let thursday = shanghai.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 14))!
    var snap = UsageSnapshot(
        plan: "max",
        week: UsageWindow(percent: 67, resetsAt: thursday),
        fetchedAt: protoNow)
    snap.modelWeek = ModelWindow(name: "Fable", window: UsageWindow(percent: 4, resetsAt: thursday))
    var line = encodeUsage(.claude, status: .ok, snapshot: snap, now: protoNow, calendar: shanghai)
    #expect(line == "U svc=cl st=ok age=0 plan=max wk=67 wkd=4 wkt=1400 md=Fable mw=4\n")
    // 模型名只留 ASCII 字母数字（保留大小写），最多 10 个字符；过了重置时刻编码成 -1
    snap.modelWeek = ModelWindow(name: "Claude Fable-5.5 Ultra", window: UsageWindow(percent: 9, resetsAt: protoNow - 1))
    line = encodeUsage(.claude, status: .ok, snapshot: snap, now: protoNow, calendar: shanghai)
    #expect(line.hasSuffix(" md=ClaudeFabl mw=-1\n"))
    // 名字清洗后为空就整条不发
    snap.modelWeek = ModelWindow(name: "模型", window: UsageWindow(percent: 9))
    line = encodeUsage(.claude, status: .ok, snapshot: snap, now: protoNow, calendar: shanghai)
    #expect(!line.contains("md=") && !line.contains("mw="))
}

@Test func longestUsageLineFitsTheFirmwareBuffer() {
    // 固件每行内容最多 128 字节（不含换行）
    let far = protoNow.addingTimeInterval(Double(Int32.max) * 2)
    let w = UsageWindow(percent: 100, resetsAt: far)
    let snap = UsageSnapshot(plan: "abcdefghijklmn", fiveHour: w, week: w, opus: w, sonnet: w,
                             fetchedAt: Date(timeIntervalSince1970: -1e300))
    var s = snap
    s.modelWeek = ModelWindow(name: "ABCDEFGHIJKLMN", window: w)
    let line = encodeUsage(.chatgpt, status: .missing, snapshot: s, now: protoNow, calendar: shanghai)
    #expect(line.utf8.count - 1 <= 128)
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

@Test func usageEncodingNeverTrapsOnFarFutureReset() {
    // 恢复自持久化快照的 resetsAt 可能极远，h5r 必须落在 Int32 范围内
    let far = Date(timeIntervalSince1970: 1e300)
    let snap = UsageSnapshot(
        fiveHour: UsageWindow(percent: 5, resetsAt: far),
        week: UsageWindow(percent: 6, resetsAt: far),
        fetchedAt: protoNow)
    let line = encodeUsage(.claude, status: .ok, snapshot: snap, now: protoNow, calendar: shanghai)
    let h5r = line.split(separator: " ").first { $0.hasPrefix("h5r=") }.flatMap { Int($0.dropFirst(4)) }
    #expect(h5r != nil && (0...Int(Int32.max)).contains(h5r!))
    // 极端的 fetchedAt 也不能让 age 溢出
    let old = UsageSnapshot(fiveHour: UsageWindow(percent: 5), fetchedAt: Date(timeIntervalSince1970: -1e300))
    let l2 = encodeUsage(.claude, status: .error, snapshot: old, now: protoNow, calendar: shanghai)
    #expect(l2.hasPrefix("U svc=cl st=err age="))
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

// MARK: - 状态归并、调度、请求

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private let usageNow = Date(timeIntervalSince1970: 1_000_000)
private let usageSnap = UsageSnapshot(
    plan: "max",
    fiveHour: UsageWindow(percent: 42, resetsAt: usageNow + 3600, minutes: 300),
    week: UsageWindow(percent: 67, resetsAt: usageNow + 86400, minutes: 10080),
    fetchedAt: usageNow)

@Test func reduceKeepsSnapshotOnFailure() {
    let snap = usageSnap
    let ok = reduce(UsageState(), .success(snap))
    #expect(ok == UsageState(status: .ok, snapshot: snap))
    #expect(reduce(ok, .unauthorized) == UsageState(status: .expired, snapshot: snap))
    #expect(reduce(ok, .credentialExpired).status == .expired)
    #expect(reduce(ok, .failed) == UsageState(status: .error, snapshot: snap))
    #expect(reduce(ok, .rateLimited).status == .error)
    #expect(reduce(ok, .noCredential) == UsageState(status: .expired, snapshot: snap))   // 以前成功过 → 当作过期
    #expect(reduce(UsageState(), .noCredential) == UsageState(status: .missing, snapshot: nil))
    #expect(reduce(UsageState(), .credentialExpired) == UsageState(status: .expired, snapshot: nil))
}

@Test func scheduleIntervalAndBackoff() {
    var s = UsageSchedule()
    #expect(s.isDue(now: t0))
    s.record(.success(usageSnap), now: t0)
    #expect(!s.isDue(now: t0 + 119))
    #expect(s.isDue(now: t0 + 120))
    s.record(.rateLimited, now: t0 + 120)
    #expect(!s.isDue(now: t0 + 719))
    #expect(s.isDue(now: t0 + 720))
    s.forceNext()
    #expect(s.isDue(now: t0 + 121))
}

@Test func statusClassification() {
    #expect(classify(statusCode: 200) == nil)
    #expect(classify(statusCode: 204) == nil)
    #expect(classify(statusCode: 401) == .unauthorized)
    #expect(classify(statusCode: 403) == .unauthorized)
    #expect(classify(statusCode: 429) == .rateLimited)
    #expect(classify(statusCode: 500) == .failed)
    #expect(classify(statusCode: 302) == .failed)
}

@Test func requestsCarryRequiredHeaders() {
    let claudeCred = ClaudeCredential(accessToken: "fake-claude", expiresAt: usageNow + 3600, plan: "max")
    let codexCred = CodexCredential(accessToken: "fake-codex", accountID: "acct-123")
    let r = claudeUsageRequest(claudeCred)
    #expect(r.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(r.httpMethod == "GET")
    #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer fake-claude")
    #expect(r.value(forHTTPHeaderField: "User-Agent") == "Sysmon")
    #expect(r.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(r.timeoutInterval == 15)
    let c = codexUsageRequest(codexCred)
    #expect(c.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
    #expect(c.httpMethod == "GET")
    #expect(c.value(forHTTPHeaderField: "ChatGPT-Account-Id") == codexCred.accountID)
    #expect(c.value(forHTTPHeaderField: "Authorization") == "Bearer fake-codex")
    #expect(c.value(forHTTPHeaderField: "User-Agent") == "Sysmon")
    #expect(c.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(c.timeoutInterval == 15)
}

@Test func settingsStatusText() {
    func ok(ageSeconds: TimeInterval) -> String {
        let snap = UsageSnapshot(fetchedAt: usageNow - ageSeconds)
        return settingsStatus(UsageState(status: .ok, snapshot: snap), now: usageNow)
    }
    #expect(ok(ageSeconds: 0) == "正常 · 刚刚更新")
    #expect(ok(ageSeconds: 59) == "正常 · 刚刚更新")
    #expect(ok(ageSeconds: 60) == "正常 · 1 分钟前更新")
    #expect(ok(ageSeconds: 3599) == "正常 · 59 分钟前更新")
    #expect(ok(ageSeconds: 3600) == "正常 · 1 小时前更新")
    #expect(ok(ageSeconds: 86399) == "正常 · 23 小时前更新")
    #expect(ok(ageSeconds: 86400 * 3) == "正常 · 3 天前更新")
    // 时钟回拨（fetchedAt 在未来）按刚刚处理
    #expect(ok(ageSeconds: -30) == "正常 · 刚刚更新")

    let snap = usageSnap
    #expect(settingsStatus(UsageState(status: .expired, snapshot: snap), now: usageNow) == "已过期")
    #expect(settingsStatus(UsageState(status: .error, snapshot: snap), now: usageNow) == "读取失败")
    #expect(settingsStatus(UsageState(), now: usageNow) == "未登录")
    // ok 但没有快照（不应出现）→ 按读取失败处理
    #expect(settingsStatus(UsageState(status: .ok, snapshot: nil), now: usageNow) == "读取失败")
}

@Test func processOutputIsCaptured() {
    let data = runCapturingStdout("/bin/echo", arguments: ["hello"], timeout: 5)
    #expect(data.map { String(decoding: $0, as: UTF8.self) } == "hello\n")
    #expect(runCapturingStdout("/usr/bin/false", arguments: [], timeout: 5) == nil)
    #expect(runCapturingStdout("/nonexistent/binary", arguments: [], timeout: 5) == nil)
}

@Test func hungProcessIsTerminatedAfterTimeout() {
    let start = Date()
    let data = runCapturingStdout("/bin/sleep", arguments: ["30"], timeout: 0.5)
    #expect(data == nil)
    #expect(Date().timeIntervalSince(start) < 5)
}
