import AppKit
import SwiftUI
import SysmonCore

/// 设置窗口分四页：通用、番茄钟、健康提醒、用量。记住上次停在哪一页。
struct SettingsView: View {
    @ObservedObject var monitor: MonitorController
    @ObservedObject var preferences: Preferences
    @ObservedObject var usage: UsageController
    @AppStorage("settingsTab") private var tab = Tab.general

    enum Tab: String {
        case general, pomodoro, health, usage
    }

    var body: some View {
        TabView(selection: $tab) {
            page(general).tabItem { Label("通用", systemImage: "gearshape") }.tag(Tab.general)
            page(pomodoro).tabItem { Label("番茄钟", systemImage: "timer") }.tag(Tab.pomodoro)
            page(health).tabItem { Label("健康提醒", systemImage: "figure.walk") }.tag(Tab.health)
            page(usageTab).tabItem { Label("用量", systemImage: "chart.bar") }.tag(Tab.usage)
        }
    }

    /// 每页同宽，高度跟着内容走
    private func page(_ content: some View) -> some View {
        Form { content }
            .formStyle(.grouped)
            .frame(width: 440)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var general: some View {
        Section("切换副屏") {
            LabeledContent("快捷键") {
                HotKeyRecorder(combo: Binding(
                    get: { preferences.hotKey },
                    set: { monitor.setHotKey($0) }
                ))
            }
            hotKeyWarnings(failed: monitor.hotKeyFailed, conflict: monitor.pageHotKeyConflict)
            Text("按下这个快捷键就切到下一屏，也可以直接点一下副屏")
                .foregroundStyle(.secondary)
            hotKeyHelp
        }

        Section {
            Toggle("RGB 灯", isOn: $preferences.ledEnabled)
            Text("提醒横幅出现时，板子背面的灯会跟着呼吸")
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle("开机时启动", isOn: Binding(
                get: { monitor.launchAtLogin },
                set: { monitor.setLaunchAtLogin($0) }
            ))
        }
    }

    @ViewBuilder private var pomodoro: some View {
        Section {
            Toggle("番茄屏", isOn: Binding(
                get: { preferences.pomodoroEnabled },
                set: { monitor.setPomodoroEnabled($0) }
            ))
            LabeledContent("开始 / 暂停快捷键") {
                HotKeyRecorder(combo: Binding(
                    get: { preferences.pomodoroHotKey },
                    set: { monitor.setPomodoroHotKey($0) }
                ))
            }
            hotKeyWarnings(failed: monitor.pomodoroHotKeyFailed, conflict: monitor.pomodoroHotKeyConflict)
            Text("没开始时按一下开始专注，走着时暂停，暂停时继续")
                .foregroundStyle(.secondary)
            hotKeyHelp
        }

        Section("时长") {
            minutesStepper("专注", \.pomodoroConfig.focusMinutes, 5...90, unit: "分钟")
            minutesStepper("短休", \.pomodoroConfig.shortBreakMinutes, 1...30, unit: "分钟")
            minutesStepper("长休", \.pomodoroConfig.longBreakMinutes, 1...60, unit: "分钟")
            minutesStepper("每轮", \.pomodoroConfig.rounds, 2...8, unit: "个")
            Text("改了只影响下一段，正在走的这一段不变")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var health: some View {
        Section {
            Toggle("久坐提醒", isOn: configBinding(\.healthConfig.sitEnabled))
            if preferences.healthConfig.sitEnabled {
                minutesStepper("每隔", \.healthConfig.sitMinutes, 10...180, unit: "分钟")
            }
        }

        Section {
            Toggle("喝水提醒", isOn: configBinding(\.healthConfig.waterEnabled))
            if preferences.healthConfig.waterEnabled {
                minutesStepper("每隔", \.healthConfig.waterMinutes, 10...180, unit: "分钟")
            }
        }

        Section {
            Text("离开电脑 5 分钟就算起来过；专注时不打扰，休息时再提醒")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var usageTab: some View {
        Section("用量屏") {
            usageToggle("Claude 用量屏", .claude, isOn: preferences.claudeEnabled)
            usageToggle("ChatGPT 用量屏", .chatgpt, isOn: preferences.chatgptEnabled)
        }

        Section {
            Text("用量数据借用 Claude Code（终端里的 `claude`）和 Codex 的登录。Sysmon 只读，不会帮它们续期，所以不会把你登出。")
            Text("代价是：一段时间没用它们，登录就会过期，副屏会停在最后一次的数字上并标成“已过期”。Claude 在终端里运行一次 `claude` 就能恢复；ChatGPT 打开一次 Codex 就能恢复。")
        }
        .foregroundStyle(.secondary)
    }

    /// 录制框的用法说明
    private var hotKeyHelp: some View {
        Text("设置方法：点击右边的按钮，再按下想用的组合键，要包含 ⌃、⌥ 或 ⌘ 之一")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private func hotKeyWarnings(failed: Bool, conflict: Bool) -> some View {
        if failed {
            Text("这个快捷键被占用了，换一个")
                .foregroundStyle(.red)
        }
        if conflict {
            Text("和另一个快捷键重复了，换一个")
                .foregroundStyle(.red)
        }
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
