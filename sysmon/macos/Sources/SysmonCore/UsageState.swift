/// 用量数据的状态，rawValue 是串口 U 行里 st= 的取值。
public enum UsageStatus: String, Codable, Sendable {
    case ok
    case expired = "exp"
    case error = "err"
    case missing = "none"
}
