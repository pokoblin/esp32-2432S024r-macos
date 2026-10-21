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

    var body: some View {
        Text(monitor.portPath.map { "已连接 \($0)" } ?? "未找到设备")
        Text(summary.text)
        ForEach(enabledServices, id: \.self) { service in
            Text(menuSummary(service, usage.states[service] ?? UsageState(), now: Date()))
        }
        Divider()
        SettingsLink { Text("设置…") }
            // 菜单栏程序没有 Dock 图标，打开设置时要主动把窗口带到最前
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
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
