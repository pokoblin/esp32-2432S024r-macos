import Foundation
import SysmonCore

/// 持有番茄钟和健康提醒的唯一一份状态（Routine），把今日统计存进 UserDefaults。
/// 正在走的番茄不持久化：Sysmon 重启后回到空闲、第 1 个。
@MainActor
final class RoutineController: ObservableObject {
    @Published private(set) var routine: Routine {
        didSet {
            if routine.stats != oldValue.stats, let data = try? JSONEncoder().encode(routine.stats) {
                defaults.set(data, forKey: Self.statsKey)
            }
        }
    }
    /// 操作改了状态或横幅时调用，MonitorController 据此立刻发 T、B 行
    var onChange: (() -> Void)?

    private static let statsKey = "routine.stats"
    private let preferences: Preferences
    private let defaults: UserDefaults

    init(preferences: Preferences, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        self.defaults = defaults
        let stats = defaults.data(forKey: Self.statsKey)
            .flatMap { try? JSONDecoder().decode(TodayStats.self, from: $0) } ?? TodayStats()
        routine = Routine(pomodoro: Pomodoro(config: preferences.pomodoroConfig),
                          health: HealthTracker(config: preferences.healthConfig), stats: stats)
    }

    /// 每个 2 秒周期都调，熄屏时也调：番茄钟照常走，离开时间照常算。
    func tick(gateActive: Bool) {
        routine.tick(now: Date(), idleSeconds: readIdleSeconds() ?? 0, gateActive: gateActive, calendar: .current)
    }

    func toggle() { act { $0.toggle(now: Date()) } }
    func start() { act { $0.start(now: Date()) } }
    func pause() { act { $0.pause(now: Date()) } }
    func resume() { act { $0.resume(now: Date()) } }
    func skip() { act { $0.skip(now: Date()) } }
    func resetRound() { act { $0.resetRound() } }

    /// 关掉当前横幅；没有横幅时返回 false，调用方照常切屏。
    func dismissBanner() -> Bool {
        let dismissed = routine.dismissBanner()
        if dismissed { onChange?() }
        return dismissed
    }

    /// 设置里改了时长或提醒开关后调用。正在走的这一段不受影响。
    func applyConfig() {
        act {
            $0.pomodoro.config = preferences.pomodoroConfig
            $0.health.config = preferences.healthConfig
        }
    }

    func timerLine() -> String {
        encodeTimer(routine.pomodoro, stats: routine.stats, hasHotKey: preferences.pomodoroHotKey != nil,
                    now: Date(), calendar: .current)
    }

    func bannerLine() -> String {
        encodeBanner(routine.banner, led: preferences.ledEnabled)
    }

    func menuStatus(now: Date) -> String {
        pomodoroMenuStatus(routine.pomodoro, stats: routine.stats, now: now)
    }

    private func act(_ change: (inout Routine) -> Void) {
        change(&routine)
        onChange?()
    }
}
