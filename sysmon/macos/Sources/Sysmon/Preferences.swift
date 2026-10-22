import Foundation
import SysmonCore

/// 用户偏好，存在 UserDefaults 里。改动立刻写回，下次启动恢复。
@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var claudeEnabled: Bool {
        didSet { defaults.set(claudeEnabled, forKey: "claudeEnabled") }
    }
    @Published var chatgptEnabled: Bool {
        didSet { defaults.set(chatgptEnabled, forKey: "chatgptEnabled") }
    }
    @Published var pomodoroEnabled: Bool {
        didSet { defaults.set(pomodoroEnabled, forKey: "pomodoroEnabled") }
    }
    /// 番茄钟“开始 / 暂停”的全局快捷键；nil 表示没设置
    @Published var pomodoroHotKey: HotKeyCombo? {
        didSet { store(pomodoroHotKey, "pomodoroHotKey") }
    }
    @Published var pomodoroConfig: PomodoroConfig {
        didSet { store(pomodoroConfig, "pomodoroConfig") }
    }
    @Published var healthConfig: HealthConfig {
        didSet { store(healthConfig, "healthConfig") }
    }
    @Published var ledEnabled: Bool {
        didSet { defaults.set(ledEnabled, forKey: "ledEnabled") }
    }
    /// 当前页只由 Mac 端记录，rawValue 存字符串
    @Published var page: Page {
        didSet { defaults.set(page.rawValue, forKey: "page") }
    }
    /// 全局快捷键，JSON 存储；nil 表示没设置
    @Published var hotKey: HotKeyCombo? {
        didSet { store(hotKey, "hotKey") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 没写过的开关默认开启
        claudeEnabled = defaults.object(forKey: "claudeEnabled") as? Bool ?? true
        chatgptEnabled = defaults.object(forKey: "chatgptEnabled") as? Bool ?? true
        page = defaults.string(forKey: "page").flatMap(Page.init(rawValue:)) ?? .sys
        hotKey = Self.load(defaults, "hotKey")
        pomodoroEnabled = defaults.object(forKey: "pomodoroEnabled") as? Bool ?? true
        pomodoroHotKey = Self.load(defaults, "pomodoroHotKey")
        pomodoroConfig = Self.load(defaults, "pomodoroConfig") ?? PomodoroConfig()
        healthConfig = Self.load(defaults, "healthConfig") ?? HealthConfig()
        ledEnabled = defaults.object(forKey: "ledEnabled") as? Bool ?? true
    }

    /// JSON 存储；nil 时删掉这一项
    private func store<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// 读不到或数据损坏时返回 nil，由调用方用默认值
    private static func load<T: Decodable>(_ defaults: UserDefaults, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// 参与轮换的页面，顺序固定 sys → pomo → cl → gpt
    var enabledPages: [Page] {
        SysmonCore.enabledPages(pomodoro: pomodoroEnabled, claude: claudeEnabled, chatgpt: chatgptEnabled)
    }
}
