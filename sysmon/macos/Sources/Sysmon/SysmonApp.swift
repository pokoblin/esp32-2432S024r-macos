import SwiftUI
import SysmonCore

@main
struct SysmonApp: App {
    @StateObject private var monitor = MonitorController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor, summary: monitor.summary,
                        preferences: monitor.preferences, usage: monitor.usage)
        } label: {
            Image(nsImage: BoardIcon.image(connected: monitor.portPath != nil))
        }

        Settings {
            SettingsView(monitor: monitor, preferences: monitor.preferences, usage: monitor.usage)
        }
    }
}

/// 菜单内容单独成视图：连接状态、系统摘要、每个开启服务的用量摘要，然后是「设置…」和「退出」。
struct MenuContent: View {
    @ObservedObject var monitor: MonitorController
    @ObservedObject var summary: SummaryModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var usage: UsageController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(monitor.portPath.map { "已连接 \($0)" } ?? "未找到设备")
        Text(summary.text)
        ForEach(enabledServices, id: \.self) { service in
            Text(menuSummary(service, usage.states[service] ?? UsageState(), now: Date()))
        }
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

    private var enabledServices: [UsageService] {
        var services: [UsageService] = []
        if preferences.claudeEnabled { services.append(.claude) }
        if preferences.chatgptEnabled { services.append(.chatgpt) }
        return services
    }
}
