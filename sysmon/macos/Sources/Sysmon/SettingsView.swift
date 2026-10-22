import AppKit
import SwiftUI
import SysmonCore

/// 设置窗口：切屏快捷键、番茄钟、健康提醒、RGB 灯、两块用量屏的开关、数据来源说明、开机启动。
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
                if monitor.hotKeyConflict {
                    Text("和另一个快捷键重复了，换一个")
                        .foregroundStyle(.red)
                }
                Text("也可以直接点一下副屏")
                    .foregroundStyle(.secondary)
            }

            Section("番茄钟") {
                Toggle("番茄屏", isOn: Binding(
                    get: { preferences.pomodoroEnabled },
                    set: { monitor.setPomodoroEnabled($0) }
                ))
                LabeledContent("开始 / 暂停") {
                    HotKeyRecorder(combo: Binding(
                        get: { preferences.pomodoroHotKey },
                        set: { monitor.setPomodoroHotKey($0) }
                    ))
                }
                if monitor.pomodoroHotKeyFailed {
                    Text("这个快捷键被占用了，换一个")
                        .foregroundStyle(.red)
                }
                minutesStepper("专注", \.pomodoroConfig.focusMinutes, 5...90, unit: "分钟")
                minutesStepper("短休", \.pomodoroConfig.shortBreakMinutes, 1...30, unit: "分钟")
                minutesStepper("长休", \.pomodoroConfig.longBreakMinutes, 1...60, unit: "分钟")
                minutesStepper("每轮", \.pomodoroConfig.rounds, 2...8, unit: "个")
            }

            Section("健康提醒") {
                Toggle("久坐提醒", isOn: configBinding(\.healthConfig.sitEnabled))
                if preferences.healthConfig.sitEnabled {
                    minutesStepper("每隔", \.healthConfig.sitMinutes, 10...180, unit: "分钟")
                }
                Toggle("喝水提醒", isOn: configBinding(\.healthConfig.waterEnabled))
                if preferences.healthConfig.waterEnabled {
                    minutesStepper("每隔", \.healthConfig.waterMinutes, 10...180, unit: "分钟")
                }
                Text("离开电脑 5 分钟就算起来过；专注时不打扰，休息时再提醒")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("RGB 灯", isOn: $preferences.ledEnabled)
                Text("横幅出现时板子背面的灯会跟着呼吸")
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

    /// 设置项的绑定：改完同步进番茄钟和健康提醒（正在走的这一段不受影响）。
    private func configBinding<T>(_ path: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { preferences[keyPath: path] },
            set: {
                preferences[keyPath: path] = $0
                monitor.routine.applyConfig()
            }
        )
    }

    private func minutesStepper(_ title: String, _ path: ReferenceWritableKeyPath<Preferences, Int>,
                                _ range: ClosedRange<Int>, unit: String) -> some View {
        let value = configBinding(path)
        return Stepper("\(title) \(value.wrappedValue) \(unit)", value: value, in: range)
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
                    Text(settingsStatus(usage.states[service] ?? UsageState(), now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
