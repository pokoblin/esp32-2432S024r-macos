import SwiftUI

@main
struct SysmonApp: App {
    @StateObject private var monitor = MonitorController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor, summary: monitor.summary)
        } label: {
            Image(systemName: monitor.portPath == nil ? "display.trianglebadge.exclamationmark" : "display")
        }
    }
}

/// 菜单内容单独成视图，以后在这里加「设置…」（SettingsLink）。
struct MenuContent: View {
    @ObservedObject var monitor: MonitorController
    @ObservedObject var summary: SummaryModel

    var body: some View {
        Text(monitor.portPath.map { "已连接 \($0)" } ?? "未找到设备")
        Text(summary.text)
        Divider()
        Toggle("开机时启动", isOn: Binding(
            get: { monitor.launchAtLogin },
            set: { monitor.setLaunchAtLogin($0) }
        ))
        Divider()
        Button("退出") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
