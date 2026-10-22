import AppKit
import ServiceManagement
import SysmonCore

/// 每 2 秒采集一次 CPU / 内存压力 / 网速，连上板子时通过串口发给副屏。
/// 显示器睡眠、锁屏、切换用户或系统睡眠时发 OFF 并暂停；串口断开后每次触发时自动重连。
@MainActor
final class MonitorController: ObservableObject {
    @Published private(set) var portPath: String?
    @Published private(set) var launchAtLogin = false
    /// 全局快捷键注册失败（例如被别的程序占用），设置窗口据此提示
    @Published private(set) var hotKeyFailed = false
    @Published private(set) var pomodoroHotKeyFailed = false
    /// 两个快捷键录成了同一个组合；后录的那个不生效
    @Published private(set) var hotKeyConflict = false
    let preferences = Preferences()
    let usage: UsageController
    let routine: RoutineController

    private static let interval: TimeInterval = 2

    private var port: SerialPort?
    private var gate = DisplayGate()
    private var sampler = MetricsSampler()
    private var timer: Timer?
    private let hotKey = HotKeyCenter()
    private let pomodoroHotKey = HotKeyCenter()
    // 工作时持有，防止 App Nap 拖慢定时器；暂停期间释放
    private var activity: NSObjectProtocol?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        usage = UsageController(preferences: preferences)
        routine = RoutineController(preferences: preferences)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        // 快捷键和板子的 TAP 都走 advancePage，保证只有一份「当前页」
        hotKey.onPress = { [weak self] in self?.advancePage() }
        hotKeyFailed = !hotKey.register(preferences.hotKey)
        pomodoroHotKey.onPress = { [weak self] in self?.routine.toggle() }
        pomodoroHotKeyFailed = !pomodoroHotKey.register(preferences.pomodoroHotKey)
        routine.onChange = { [weak self] in self?.sendRoutineLines() }
        setActivity(true)
        observeSystemEvents()

        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Sysmon: launch at login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - 采集与发送

    private func tick() {
        // 番茄钟和离开时间在熄屏时也要推进，只是不发数据
        routine.tick(gateActive: gate.active)
        guard gate.active else { return }
        // 用量拉取按自己的节奏排期，放在 defer 里：不受采样基线阶段提前返回的影响
        defer { usage.tick(gateActive: gate.active) }
        if port == nil { connect() }

        guard let sample = sampler.sample(cpu: readCPUTicks(), counters: readPhysicalCounters(),
                                          memory: readMemoryPressure(),
                                          now: ProcessInfo.processInfo.systemUptime) else { return }
        // 发送顺序固定：S → P → T → B → U。系统状态数据停在别的页时也照常发，曲线才连续
        send([encodeSample(sample)] + pageLines())
    }

    /// 依次写出几行；任何一行写失败就断开，等下一次触发重连。
    private func send(_ lines: [String]) {
        guard let port else { return }
        for line in lines where !port.write(line) {
            disconnect()
            return
        }
    }

    /// 当前页的 P 行、番茄的 T 行、横幅的 B 行；当前页是用量页时再带一条 U 行。
    private func pageLines() -> [String] {
        let enabled = preferences.enabledPages
        let page = resolvePage(preferences.page, enabled: enabled)
        if page != preferences.page { preferences.page = page }
        var lines = [encodePage(page, enabled: enabled), routine.timerLine(), routine.bannerLine()]
        let service: UsageService? = switch page {
        case .sys, .pomodoro: nil
        case .claude: .claude
        case .chatgpt: .chatgpt
        }
        if let service {
            let state = usage.states[service] ?? UsageState()
            lines.append(encodeUsage(service, status: state.status, snapshot: state.snapshot,
                                     now: Date(), calendar: .current))
        }
        return lines
    }

    // MARK: - 切屏与设置

    /// 快捷键和板子的 TAP 的唯一入口：熄屏时不动；有横幅时只关横幅；只有系统状态屏时不动。
    func advancePage() {
        guard gate.active else { return }
        // 关横幅时 onChange 已经发了 T、B，这里补发 P，板子据此重画原来那屏
        if routine.dismissBanner() {
            send(pageLines())
            return
        }
        let enabled = preferences.enabledPages
        guard enabled.count > 1 else { return }
        preferences.page = nextPage(after: resolvePage(preferences.page, enabled: enabled), enabled: enabled)
        send(pageLines())  // 立刻发 P（和 U），不重发 S
    }

    /// 开关某块用量屏：当前页被关掉就回系统状态屏，开启时马上拉一次数据。
    func setUsageEnabled(_ service: UsageService, _ on: Bool) {
        switch service {
        case .claude: preferences.claudeEnabled = on
        case .chatgpt: preferences.chatgptEnabled = on
        }
        preferences.page = resolvePage(preferences.page, enabled: preferences.enabledPages)
        // 熄屏时不发也不拉；亮屏后的第一个 tick 会补上（调度已到期）
        guard gate.active else { return }
        send(pageLines())
        if on { usage.refreshNow(service) }
    }

    func setHotKey(_ combo: HotKeyCombo?) {
        guard !conflicts(combo, preferences.pomodoroHotKey) else { return }
        preferences.hotKey = combo
        hotKeyFailed = !hotKey.register(combo)
    }

    func setPomodoroHotKey(_ combo: HotKeyCombo?) {
        guard !conflicts(combo, preferences.hotKey) else { return }
        preferences.pomodoroHotKey = combo
        pomodoroHotKeyFailed = !pomodoroHotKey.register(combo)
        sendRoutineLines()  // 底栏提示跟着有没有快捷键变
    }

    /// 开关番茄屏：当前页被关掉就回系统状态屏。番茄钟本身照常可用。
    func setPomodoroEnabled(_ on: Bool) {
        preferences.pomodoroEnabled = on
        preferences.page = resolvePage(preferences.page, enabled: preferences.enabledPages)
        guard gate.active else { return }
        send(pageLines())
    }

    /// 和另一个快捷键撞了就记下来、不生效；不撞就清掉提示。
    private func conflicts(_ combo: HotKeyCombo?, _ other: HotKeyCombo?) -> Bool {
        hotKeyConflict = combo.map {
            hotKeyConflicts(keyCode: $0.keyCode, modifiers: $0.carbonModifiers,
                            otherKeyCode: other?.keyCode, otherModifiers: other?.carbonModifiers)
        } ?? false
        return hotKeyConflict
    }

    /// 番茄状态或横幅变了：立刻发 T、B，不等下一个 2 秒。
    private func sendRoutineLines() {
        guard gate.active else { return }
        send([routine.timerLine(), routine.bannerLine()])
    }

    /// 依次尝试每个 WCH 串口，第一个能打开的就是板子。
    private func connect() {
        for path in boardCandidates(listSerialDevices()) {
            if let port = SerialPort(path: path) {
                // 板子发回来的 TAP 行当作一次切屏；其他内容（开机日志等）忽略
                port.onLine = { [weak self] line in
                    if isTapLine(line) { self?.advancePage() }
                }
                port.startReading()
                self.port = port
                portPath = path
                return
            }
        }
    }

    private func disconnect() {
        port?.onLine = nil
        port?.close()
        port = nil
        portPath = nil
    }

    private func setActivity(_ on: Bool) {
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Send system stats to the ESP32 screen")
        } else if !on, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    // MARK: - 显示器睡眠 / 锁屏联动

    private func updateGate(_ change: (inout DisplayGate) -> Void) {
        let wasActive = gate.active
        change(&gate)
        if wasActive && !gate.active {
            send([offLine])
            sampler.reset()
            setActivity(false)
        } else if !wasActive && gate.active {
            setActivity(true)
            usage.refreshNow()  // 熄屏期间不拉取，亮屏后马上补一次
            tick()  // 立刻建立基线，下一次触发就能发数据点亮副屏
        }
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemSleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemSleeping = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ change: @escaping @MainActor (inout DisplayGate) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateGate(change) }
        }
        observers.append((center, token))
    }
}
