import SwiftUI
import SysmonCore

@main
struct SysmonApp: App {
    @StateObject private var monitor = MonitorController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor)
        } label: {
            Image(nsImage: BoardIcon.image(connected: monitor.portPath != nil))
        }

        Settings {
            SettingsView(monitor: monitor, preferences: monitor.preferences, usage: monitor.usage)
        }
    }
}

/// 菜单内容单独成视图：连接状态，然后是「设置…」和「退出」。
struct MenuContent: View {
    @ObservedObject var monitor: MonitorController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(monitor.portPath.map { "已连接 \($0)" } ?? "未找到设备")
        Divider()
        // 菜单栏程序没有 Dock 图标：每次点击都先激活 App 再打开设置，窗口才会成为 key 并在最前
        // （用 SettingsLink 的话菜单项上的手势不会触发，也就没法在点击时激活）
        Button("设置…") {
            NSApp.activate()
            openSettings()
        }
        Divider()
        Button("退出") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
