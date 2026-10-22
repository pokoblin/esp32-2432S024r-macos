// 发给 ESP32 副屏的一行文本协议，和固件 lib/sysmon_core/protocol.h 对应。
//   数据行：S cpu=<0-100> mem=<0-100> lvl=<1|2|4> rx=<B/s> tx=<B/s>
//   熄屏：  OFF
//   页面：  P <sys|cl|gpt> i=<当前序号,从1起> n=<启用页数>
//   用量：  U svc=<cl|gpt> st=<ok|exp|err|none> [age=<秒> plan=<套餐> h5=<0-100|-1> h5r=<秒>
//           wk=<0-100|-1> wkd=<1-7,周一为1> wkt=<HHMM> md=<模型名> mw=<0-100|-1>
//           op=<0-100|-1> so=<0-100|-1>]
//   点击：  TAP（固件 → Mac，整行恰好为 TAP）

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
