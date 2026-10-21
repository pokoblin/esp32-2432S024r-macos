import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 一个全局快捷键：虚拟键码 + Carbon 修饰键掩码。display 是给人看的文字，例如 "⌃⌥S"。
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    /// 修饰键按标准顺序 ⌃⌥⇧⌘ 拼在键名前面。
    static func display(carbonModifiers m: UInt32, keyName: String) -> String {
        var s = ""
        if m & UInt32(controlKey) != 0 { s += "⌃" }
        if m & UInt32(optionKey) != 0 { s += "⌥" }
        if m & UInt32(shiftKey) != 0 { s += "⇧" }
        if m & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName
    }

    /// 非字符键的名字；字符键返回 nil，由按键事件里的字符决定。
    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "PgUp", UInt32(kVK_PageDown): "PgDn",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    /// 从按键事件构造。至少要有 ⌃⌥⌘ 之一，只有 ⇧ 不行（否则会吃掉正常打字）。
    init?(event: NSEvent) {
        var m: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        guard m & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }
        let code = UInt32(event.keyCode)
        let name = Self.specialKeyNames[code]
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? "#\(code)"
        self.init(keyCode: code, carbonModifiers: m,
                  display: Self.display(carbonModifiers: m, keyName: name))
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }
}

// Carbon 的 C 回调不能捕获上下文，所以按热键 id 在全局表里找对应的 HotKeyCenter。
private final class WeakCenter: @unchecked Sendable {
    weak var center: HotKeyCenter?
    init(_ center: HotKeyCenter) { self.center = center }
}
private let centersLock = NSLock()
nonisolated(unsafe) private var centers: [UInt32: WeakCenter] = [:]
nonisolated(unsafe) private var nextHotKeyID: UInt32 = 1
nonisolated(unsafe) private var handlerInstalled = false

private let hotKeySignature: OSType = 0x5359_534D  // 'SYSM'

private func hotKeyHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr, id.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    centersLock.lock()
    let box = centers[id.id]
    centersLock.unlock()
    Task { @MainActor in box?.center?.onPress?() }
    return noErr
}

/// 全局快捷键：Carbon RegisterEventHotKey，不需要辅助功能权限。
@MainActor
final class HotKeyCenter {
    var onPress: (() -> Void)?

    private let id: UInt32
    private var ref: EventHotKeyRef?

    init() {
        centersLock.lock()
        defer { centersLock.unlock() }
        id = nextHotKeyID
        nextHotKeyID += 1
        centers[id] = WeakCenter(self)
    }

    /// 先注销旧的再注册新的。失败（例如组合已被占用）返回 false；传 nil 只注销。
    func register(_ combo: HotKeyCombo?) -> Bool {
        unregister()
        guard let combo else { return true }
        installHandlerIfNeeded()
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers,
                                         EventHotKeyID(signature: hotKeySignature, id: id),
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else { return false }
        ref = newRef
        return true
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerIfNeeded() {
        centersLock.lock()
        defer { centersLock.unlock() }
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        if InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil) == noErr {
            handlerInstalled = true
        }
    }
}

/// 快捷键录制控件：点一下进入录制，捕获下一次带 ⌃⌥⌘ 的按键；Esc 取消。
/// 只改绑定的值，注册和失败提示由使用方负责。
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo?
    @State private var recording = false
    @State private var monitor = MonitorBox()

    var body: some View {
        HStack {
            Button(recording ? "按下快捷键…（Esc 取消）" : (combo?.display ?? "点击录制")) {
                recording ? stop() : start()
            }
            Button("清除") {
                stop()
                combo = nil
            }
            .disabled(combo == nil)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor.token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            // 没带 ⌃⌥⌘ 的按键忽略，继续等
            guard let captured = HotKeyCombo(event: event) else { return nil }
            combo = captured
            stop()
            return nil
        }
    }

    private func stop() {
        if let token = monitor.token { NSEvent.removeMonitor(token) }
        monitor.token = nil
        recording = false
    }
}

private final class MonitorBox {
    var token: Any?
}
