import Foundation

/// 副屏页面。rawValue 是串口 P 行里的页面标识。
public enum Page: String, Codable, CaseIterable, Sendable {
    case sys
    case pomodoro = "pomo"
    case claude = "cl"
    case chatgpt = "gpt"
}

/// 参与轮换的页面，顺序固定 sys → pomo → cl → gpt，且始终以 sys 开头。
public func enabledPages(pomodoro: Bool, claude: Bool, chatgpt: Bool) -> [Page] {
    var pages: [Page] = [.sys]
    if pomodoro { pages.append(.pomodoro) }
    if claude { pages.append(.claude) }
    if chatgpt { pages.append(.chatgpt) }
    return pages
}

/// 轮换到下一页；current 不在 enabled 里时从头开始（回到 sys）。
public func nextPage(after current: Page, enabled: [Page]) -> Page {
    guard let i = enabled.firstIndex(of: current) else { return enabled.first ?? .sys }
    return enabled[(i + 1) % enabled.count]
}

/// 当前页已被关掉时退回 sys。
public func resolvePage(_ current: Page, enabled: [Page]) -> Page {
    enabled.contains(current) ? current : .sys
}

/// P 行：i 是当前页在启用页里的序号（从 1 起），n 是启用页总数。
public func encodePage(_ page: Page, enabled: [Page]) -> String {
    let i = (enabled.firstIndex(of: page) ?? 0) + 1
    return "P \(page.rawValue) i=\(i) n=\(enabled.count)\n"
}

/// 固件回传的点击行：去掉首尾空白后必须恰好是 "TAP"（排除启动日志里混入的片段）。
public func isTapLine(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespacesAndNewlines) == "TAP"
}

/// 秒数转 Int 并限制在 0...Int32.max，Double 太大或非有限时不会崩溃。
private func clampedSeconds(_ seconds: Double) -> Int {
    guard seconds.isFinite else { return 0 }
    return Int(min(Double(Int32.max), max(0, seconds.rounded(.down))))
}

/// 窗口百分比：已过重置时刻的窗口数据作废，编码成 -1。
private func windowPercent(_ w: UsageWindow, now: Date) -> Int {
    if let r = w.resetsAt, r < now { return -1 }
    return w.percent
}

/// 只留 keep 认可的字符，最多 10 个。
private func protocolToken(_ s: String, keep: (Unicode.Scalar) -> Bool) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.filter(keep).prefix(10)))
}

/// U 行，字段顺序固定：svc st age plan h5 h5r wk wkd wkt md mw op so。
/// 没有快照时只有 svc 和 st；缺失的窗口、重置时间对应字段整体省略。
public func encodeUsage(_ service: UsageService, status: UsageStatus, snapshot: UsageSnapshot?,
                        now: Date, calendar: Calendar) -> String {
    var line = "U svc=\(service.rawValue) st=\(status.rawValue)"
    if let s = snapshot {
        line += " age=\(clampedSeconds(now.timeIntervalSince(s.fetchedAt)))"
        if let plan = s.plan {
            let p = protocolToken(plan) { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
            if !p.isEmpty { line += " plan=\(p)" }
        }
        if let w = s.fiveHour {
            line += " h5=\(windowPercent(w, now: now))"
            if let r = w.resetsAt, r >= now {
                line += " h5r=\(clampedSeconds(r.timeIntervalSince(now)))"
            }
        }
        if let w = s.week {
            line += " wk=\(windowPercent(w, now: now))"
            if let r = w.resetsAt, r >= now {
                let c = calendar.dateComponents([.weekday, .hour, .minute], from: r)
                // Calendar 的 weekday 周日为 1，换算成周一为 1
                let wkd = ((c.weekday ?? 1) + 5) % 7 + 1
                line += " wkd=\(wkd) wkt=\((c.hour ?? 0) * 100 + (c.minute ?? 0))"
            }
        }
        if let m = s.modelWeek {
            // 模型名保留大小写，板子上直接拼成“本周 <名>”
            let name = protocolToken(m.name) {
                ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
            }
            if !name.isEmpty { line += " md=\(name) mw=\(windowPercent(m.window, now: now))" }
        }
        if let w = s.opus { line += " op=\(windowPercent(w, now: now))" }
        if let w = s.sonnet { line += " so=\(windowPercent(w, now: now))" }
    }
    return line + "\n"
}
