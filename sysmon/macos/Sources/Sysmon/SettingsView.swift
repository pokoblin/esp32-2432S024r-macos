import AppKit
import SwiftUI
import SysmonCore

/// 设置窗口分四页：通用、番茄钟、健康提醒、用量。记住上次停在哪一页。
struct SettingsView: View {
    @ObservedObject var monitor: MonitorController
    @ObservedObject var preferences: Preferences
    @ObservedObject var usage: UsageController
    @AppStorage("settingsTab") private var tab = Tab.general

    private var s: Strings { preferences.strings }

    enum Tab: String {
        case general, pomodoro, health, usage
    }

    var body: some View {
        TabView(selection: $tab) {
            page(general).tabItem { Label(s[.tabGeneral], systemImage: "gearshape") }.tag(Tab.general)
            page(pomodoro).tabItem { Label(s[.tabPomodoro], systemImage: "timer") }.tag(Tab.pomodoro)
            page(health).tabItem { Label(s[.tabHealth], systemImage: "figure.walk") }.tag(Tab.health)
            page(usageTab).tabItem { Label(s[.tabUsage], systemImage: "chart.bar") }.tag(Tab.usage)
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
        Section(s[.generalSwitchScreen]) {
            LabeledContent(s[.generalShortcut]) {
                HotKeyRecorder(combo: Binding(
                    get: { preferences.hotKey },
                    set: { monitor.setHotKey($0) }
                ), strings: s)
            }
            hotKeyWarnings(failed: monitor.hotKeyFailed, conflict: monitor.pageHotKeyConflict)
            Text(s[.generalSwitchHelp])
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle(s[.generalLed], isOn: $preferences.ledEnabled)
            Text(s[.generalLedHelp])
                .foregroundStyle(.secondary)
        }

        Section {
            // 各语言用自己的写法列出，选完立刻生效
            Picker(s[.generalLanguage], selection: $preferences.language) {
                Text(s[.generalSystemLanguage]).tag(AppLanguage?.none)
                Divider()
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(lang.nativeName).tag(AppLanguage?.some(lang))
                }
            }
            Toggle(s[.generalLaunchAtLogin], isOn: Binding(
                get: { monitor.launchAtLogin },
                set: { monitor.setLaunchAtLogin($0) }
            ))
        }
    }

    @ViewBuilder private var pomodoro: some View {
        Section {
            Toggle(s[.pomoScreen], isOn: Binding(
                get: { preferences.pomodoroEnabled },
                set: { monitor.setPomodoroEnabled($0) }
            ))
            LabeledContent(s[.pomoShortcut]) {
                HotKeyRecorder(combo: Binding(
                    get: { preferences.pomodoroHotKey },
                    set: { monitor.setPomodoroHotKey($0) }
                ), strings: s)
            }
            hotKeyWarnings(failed: monitor.pomodoroHotKeyFailed, conflict: monitor.pomodoroHotKeyConflict)
            Text(s[.pomoShortcutHelp])
                .foregroundStyle(.secondary)
        }

        Section(s[.pomoDurations]) {
            stepper(.pomoFocus, \.pomodoroConfig.focusMinutes, 5...90)
            stepper(.pomoShort, \.pomodoroConfig.shortBreakMinutes, 1...30)
            stepper(.pomoLong, \.pomodoroConfig.longBreakMinutes, 1...60)
            stepper(.pomoRounds, \.pomodoroConfig.rounds, 2...8)
            Text(s[.pomoDurationsHelp])
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var health: some View {
        Section {
            Toggle(s[.healthSit], isOn: configBinding(\.healthConfig.sitEnabled))
            if preferences.healthConfig.sitEnabled {
                stepper(.healthEvery, \.healthConfig.sitMinutes, 10...180)
            }
        }

        Section {
            Toggle(s[.healthWater], isOn: configBinding(\.healthConfig.waterEnabled))
            if preferences.healthConfig.waterEnabled {
                stepper(.healthEvery, \.healthConfig.waterMinutes, 10...180)
            }
        }

        Section {
            Text(s[.healthHelp])
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var usageTab: some View {
        Section(s[.usageSection]) {
            usageToggle(s[.usageClaude], .claude, isOn: preferences.claudeEnabled)
            usageToggle(s[.usageChatGPT], .chatgpt, isOn: preferences.chatgptEnabled)
        }

        Section {
            // 当成 Markdown 渲染，`claude` 显示成代码样式
            Text(LocalizedStringKey(s[.usageSource]))
            Text(LocalizedStringKey(s[.usageCost]))
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private func hotKeyWarnings(failed: Bool, conflict: Bool) -> some View {
        if failed {
            Text(s[.hotkeyTaken])
                .foregroundStyle(.red)
        }
        if conflict {
            Text(s[.hotkeyDuplicate])
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

    /// 数字设置项：标签是带 %d 的整句，例如“专注 25 分钟”
    private func stepper(_ label: L10nKey, _ path: ReferenceWritableKeyPath<Preferences, Int>,
                         _ range: ClosedRange<Int>) -> some View {
        let value = configBinding(path)
        return Stepper(s(label, value.wrappedValue), value: value, in: range)
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
                    Text(settingsStatus(usage.states[service] ?? UsageState(), now: context.date, strings: s))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
