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
