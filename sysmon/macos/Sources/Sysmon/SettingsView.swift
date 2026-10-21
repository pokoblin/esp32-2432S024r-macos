import AppKit
import SwiftUI
import SysmonCore

/// 设置窗口：切屏快捷键、两块用量屏的开关、数据来源说明、开机启动。
struct SettingsView: View {
    @ObservedObject var monitor: MonitorController
    @ObservedObject var preferences: Preferences
    @ObservedObject var usage: UsageController

    var body: some View {
        Form {
            Section("切换副屏") {
                HotKeyRecorder(combo: Binding(
                    get: { preferences.hotKey },
                    set: { monitor.setHotKey($0) }
                ))
                if monitor.hotKeyFailed {
                    Text("这个快捷键被占用了，换一个")
                        .foregroundStyle(.red)
                }
                Text("也可以直接点一下副屏")
                    .foregroundStyle(.secondary)
            }

            Section("用量屏") {
                usageToggle("Claude 用量屏", .claude, isOn: preferences.claudeEnabled)
                usageToggle("ChatGPT 用量屏", .chatgpt, isOn: preferences.chatgptEnabled)
            }

            Section {
                Text("用量数据借用 Claude Code（终端里的 `claude`）和 Codex 的登录。Sysmon 只读，不会帮它们续期，所以不会把你登出。")
                Text("代价是：一段时间没用它们，登录就会过期，副屏会停在最后一次的数字上并标成“已过期”。Claude 在终端里运行一次 `claude` 就能恢复；ChatGPT 打开一次 Codex 就能恢复。")
            }
            .foregroundStyle(.secondary)

            Section {
                Toggle("开机时启动", isOn: Binding(
                    get: { monitor.launchAtLogin },
                    set: { monitor.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func usageToggle(_ title: String, _ service: UsageService, isOn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: Binding(
                get: { isOn },
                set: { monitor.setUsageEnabled(service, $0) }
            ))
            if isOn {
                // 「N 分钟前更新」会随时间变化，每分钟重算一次
                TimelineView(.everyMinute) { context in
                    Text(statusText(service, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 灰字状态：正常时写新鲜度，其余复用 menuSummary 去掉服务名的部分。
    private func statusText(_ service: UsageService, now: Date) -> String {
        let state = usage.states[service] ?? UsageState()
        if state.status == .ok, let fetched = state.snapshot?.fetchedAt {
            return "正常 · \(ageText(now.timeIntervalSince(fetched)))更新"
        }
        let summary = menuSummary(service, state, now: now)
        return summary.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? summary
    }

    private func ageText(_ seconds: TimeInterval) -> String {
        switch Int(max(0, seconds)) {
        case ..<60: "刚刚"
        case ..<3600: "\(Int(seconds) / 60) 分钟前"
        case ..<86400: "\(Int(seconds) / 3600) 小时前"
        default: "\(Int(seconds) / 86400) 天前"
        }
    }
}
