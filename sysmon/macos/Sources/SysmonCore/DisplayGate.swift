/// 显示器睡眠、锁屏、切换用户、系统睡眠任一成立时，副屏应熄灭、停止发送数据。
public struct DisplayGate: Equatable, Sendable {
    public var screensAsleep = false
    public var locked = false
    public var sessionInactive = false
    public var systemSleeping = false

    public init() {}

    public var active: Bool {
        !(screensAsleep || locked || sessionInactive || systemSleeping)
    }
}
