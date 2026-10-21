import Foundation
import SysmonCore

/// 负责按调度拉取 Claude / ChatGPT 的用量，把状态存进 UserDefaults。
/// 同一个服务同时只跑一个请求；被取消的请求不记录结果。
@MainActor
final class UsageController: ObservableObject {
    @Published private(set) var states: [UsageService: UsageState]

    private let preferences: Preferences
    private let defaults: UserDefaults
    private let session: URLSession
    private var schedules: [UsageService: UsageSchedule] = [:]
    private var inFlight: [UsageService: Task<Void, Never>] = [:]

    init(preferences: Preferences, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        self.defaults = defaults
        // 用量请求只带 Bearer 令牌：不要 cookie，也不要缓存
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)

        var restored: [UsageService: UsageState] = [:]
        for service in UsageService.allCases {
            // 数据损坏就从空状态开始
            restored[service] = defaults.data(forKey: Self.key(service))
                .flatMap { try? JSONDecoder().decode(UsageState.self, from: $0) } ?? UsageState()
            schedules[service] = UsageSchedule()
        }
        states = restored
    }

    private static func key(_ service: UsageService) -> String { "usage.\(service.rawValue)" }

    private func isEnabled(_ service: UsageService) -> Bool {
        switch service {
        case .claude: preferences.claudeEnabled
        case .chatgpt: preferences.chatgptEnabled
        }
    }

    /// 每 2 秒由 MonitorController 调用。熄屏时什么都不做。
    func tick(gateActive: Bool) {
        guard gateActive else { return }
        let now = Date()
        for service in UsageService.allCases where isEnabled(service) {
            guard inFlight[service] == nil, schedules[service]?.isDue(now: now) ?? true else { continue }
            start(service)
        }
    }

    /// 马上重新拉取：nil 表示所有开启的服务。
    func refreshNow(_ service: UsageService? = nil) {
        for s in service.map({ [$0] }) ?? UsageService.allCases where isEnabled(s) {
            schedules[s, default: UsageSchedule()].forceNext()
        }
        tick(gateActive: true)
    }

    private func start(_ service: UsageService) {
        inFlight[service] = Task { [weak self, session] in
            let outcome = await fetchUsage(service, session: session, now: Date())
            // fetchUsage 把取消映射成 .failed，这里不能当成一次真正的失败记下来
            guard let self else { return }
            if Task.isCancelled {
                self.inFlight[service] = nil
                return
            }
            self.finish(service, outcome)
        }
    }

    private func finish(_ service: UsageService, _ outcome: FetchOutcome) {
        inFlight[service] = nil
        schedules[service, default: UsageSchedule()].record(outcome, now: Date())
        let next = reduce(states[service] ?? UsageState(), outcome)
        states[service] = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key(service))
        }
    }
}
