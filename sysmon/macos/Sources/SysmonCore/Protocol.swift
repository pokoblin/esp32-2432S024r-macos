// 发给 ESP32 副屏的一行文本协议，和固件 lib/sysmon_core/protocol.h 对应。
//   数据行：S cpu=<0-100> mem=<0-100> lvl=<1|2|4> rx=<B/s> tx=<B/s>
//   熄屏：  OFF
//   页面：  P <sys|pomo|cl|gpt> i=<当前序号,从1起> n=<启用页数>
//   用量：  U svc=<cl|gpt> st=<ok|exp|err|none> [age=<秒> plan=<套餐> h5=<0-100|-1> h5r=<秒>
//           wk=<0-100|-1> wkd=<1-7,周一为1> wkt=<HHMM> md=<模型名> mw=<0-100|-1>
//           op=<0-100|-1> so=<0-100|-1>]
//   番茄：  T st=<idle|focus|short|long> run=<0|1> rem=<秒> tot=<秒> [end=<HHMM>] rd=<第几个> rn=<每轮个数>
//           dn=<今天完成个数> dm=<今天专注分钟> key=<0|1>
//   横幅：  B k=<none|done|brk|sit|water> [min=<分钟>] [xw=1] [xs=1] led=<0|1>（k=none 时只有 k）
//   点击：  TAP（固件 → Mac，整行恰好为 TAP）

import Foundation

public struct Sample: Equatable, Sendable {
    public var cpu: Int
    public var mem: Int
    public var level: Int
    public var rx: UInt64
    public var tx: UInt64

    public init(cpu: Int, mem: Int, level: Int, rx: UInt64, tx: UInt64) {
        self.cpu = cpu
        self.mem = mem
        self.level = level
        self.rx = rx
        self.tx = tx
    }
}

/// 固件里速率是 uint32，超出的部分截到 UInt32.max。
public func encodeSample(_ s: Sample) -> String {
    let rx = min(s.rx, UInt64(UInt32.max))
    let tx = min(s.tx, UInt64(UInt32.max))
    return "S cpu=\(s.cpu) mem=\(s.mem) lvl=\(s.level) rx=\(rx) tx=\(tx)\n"
}

public let offLine = "OFF\n"

/// T 行，字段顺序固定：st run rem tot end rd rn dn dm key。end 只在走着时输出（本地时刻 HHMM）。
public func encodeTimer(_ p: Pomodoro, stats: TodayStats, hasHotKey: Bool, now: Date, calendar: Calendar) -> String {
    var line = "T st=\(p.phase.rawValue) run=\(p.isRunning ? 1 : 0)"
    line += " rem=\(p.remaining(now: now)) tot=\(p.total(now: now))"
    if let end = p.endsAt {
        let c = calendar.dateComponents([.hour, .minute], from: end)
        line += " end=\((c.hour ?? 0) * 100 + (c.minute ?? 0))"
    }
    line += " rd=\(p.round) rn=\(p.config.rounds) dn=\(stats.count) dm=\(stats.focusSeconds / 60)"
    return line + " key=\(hasHotKey ? 1 : 0)\n"
}

/// B 行，字段顺序固定：k min xw xs led；没有横幅时只发 k=none。
public func encodeBanner(_ b: Banner?, led: Bool) -> String {
    guard let b else { return "B k=none\n" }
    var line = "B k=\(b.kind.rawValue)"
    if let m = b.minutes { line += " min=\(m)" }
    if b.extras.contains(.water) { line += " xw=1" }
    if b.extras.contains(.sit) { line += " xs=1" }
    return line + " led=\(led ? 1 : 0)\n"
}

/// 菜单里的一行状态，例如“番茄 · 专注 12:34（第 2/4 个）”；空闲时写今天的个数。
public func pomodoroMenuStatus(_ p: Pomodoro, stats: TodayStats, now: Date) -> String {
    let rem = p.remaining(now: now)
    let clock = "\(rem / 60):" + String(format: "%02d", rem % 60)
    switch p.phase {
    case .idle: return "番茄 · 今天 \(stats.count) 个"
    case _ where !p.isRunning: return "番茄 · 已暂停 \(clock)"
    case .focus: return "番茄 · 专注 \(clock)（第 \(p.round)/\(p.config.rounds) 个）"
    case .short: return "番茄 · 短休 \(clock)"
    case .long: return "番茄 · 长休 \(clock)"
    }
}
