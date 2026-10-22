import SwiftUI

@main
struct SysmonApp: App {
    @StateObject private var monitor = MonitorController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor, routine: monitor.routine)
        } label: {
            Image(nsImage: BoardIcon.image(connected: monitor.portPath != nil))
        }

        Settings {
            SettingsView(monitor: monitor, preferences: monitor.preferences, usage: monitor.usage)
        }
    }
}

/// 菜单内容单独成视图：连接状态、番茄钟，然后是「设置…」和「退出」。
struct MenuContent: View {
    @ObservedObject var monitor: MonitorController
    @ObservedObject var routine: RoutineController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(monitor.portPath.map { "已连接 \($0)" } ?? "未找到设备")
        Divider()
        // routine 每 2 秒发布一次，菜单开着时这一行也跟着走
        Text(routine.menuStatus(now: Date()))
        pomodoroButtons
        Divider()
        // 菜单栏程序没有 Dock 图标：每次点击都先激活 App 再打开设置，窗口才会成为 key 并在最前
        // （用 SettingsLink 的话菜单项上的手势不会触发，也就没法在点击时激活）
        Button("设置…") {
            forceActivate()
            openSettings()
        }
        Divider()
        Button("退出") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension MenuContent {
    /// 按当前状态只列出能用的操作。
    @ViewBuilder private var pomodoroButtons: some View {
        let p = routine.routine.pomodoro
        if p.phase == .idle {
            Button("开始专注") { routine.start() }
        } else {
            if p.isRunning {
                Button("暂停") { routine.pause() }
            } else {
                Button("继续") { routine.resume() }
            }
            Button("跳过") { routine.skip() }
        }
        Button("重置轮次") { routine.resetRound() }
    }
}

/// 强制把 App 切到前台。
/// macOS 14 起 NSApp.activate() 是“协作式”的：要当前前台程序让出才生效。
/// 菜单栏菜单由系统代为显示，点菜单项不算点了本 App，请求会被直接拒绝（实测前台仍是原来的程序），
/// 临时切成 .regular 也一样。只有已标记弃用的 activate(ignoringOtherApps:) 还能立即切过来。
/// 经协议调用，避免弃用警告。
@MainActor
private func forceActivate() {
    (NSApp as LegacyActivation).activate(ignoringOtherApps: true)
}

@MainActor
private protocol LegacyActivation {
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: LegacyActivation {}
