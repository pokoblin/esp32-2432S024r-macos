import CoreGraphics
import Foundation

/// 距上一次键盘或鼠标输入过了多少秒；读不到时返回 nil。
/// CGEventSource 的这个查询不需要“辅助功能”或“输入监控”权限。
/// 如果哪天发现它会弹权限窗，改读 IORegistry 里 IOHIDSystem 的 HIDIdleTime（纳秒），同样不需要权限。
public func readIdleSeconds() -> TimeInterval? {
    guard let anyInput = CGEventType(rawValue: ~0) else { return nil }
    let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    return seconds.isFinite && seconds >= 0 ? seconds : nil
}
