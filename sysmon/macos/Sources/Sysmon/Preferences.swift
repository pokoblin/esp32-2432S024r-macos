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
    /// 当前页只由 Mac 端记录，rawValue 存字符串
    @Published var page: Page {
        didSet { defaults.set(page.rawValue, forKey: "page") }
    }
    /// 全局快捷键，JSON 存储；nil 表示没设置
    @Published var hotKey: HotKeyCombo? {
        didSet {
            if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: "hotKey")
            } else {
                defaults.removeObject(forKey: "hotKey")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 没写过的开关默认开启
        claudeEnabled = defaults.object(forKey: "claudeEnabled") as? Bool ?? true
        chatgptEnabled = defaults.object(forKey: "chatgptEnabled") as? Bool ?? true
        page = defaults.string(forKey: "page").flatMap(Page.init(rawValue:)) ?? .sys
        hotKey = defaults.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) }
    }

    /// 参与轮换的页面，顺序固定 sys → cl → gpt
    var enabledPages: [Page] {
        SysmonCore.enabledPages(pomodoro: false, claude: claudeEnabled, chatgpt: chatgptEnabled)
    }
}
