import AppKit
import ServiceManagement
import SysmonCore

/// 菜单里的数值摘要单独放一个对象：它每 2 秒变一次，只该刷新菜单内容，
/// 不该牵动菜单栏图标所在的 scene。
@MainActor
final class SummaryModel: ObservableObject {
    @Published var text = "等待数据…"
}

/// 每 2 秒采集一次 CPU / 内存压力 / 网速，更新菜单摘要，连上板子时通过串口发给副屏。
/// 显示器睡眠、锁屏、切换用户或系统睡眠时发 OFF 并暂停；串口断开后每次触发时自动重连。
@MainActor
final class MonitorController: ObservableObject {
    @Published private(set) var portPath: String?
    @Published private(set) var launchAtLogin = false
    let summary = SummaryModel()

    private static let interval: TimeInterval = 2

    private var port: SerialPort?
    private var gate = DisplayGate()
    private var sampler = MetricsSampler()
    private var timer: Timer?
    // 工作时持有，防止 App Nap 拖慢定时器；暂停期间释放
    private var activity: NSObjectProtocol?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
        guard gate.active else { return }
        if port == nil { connect() }

        guard let sample = sampler.sample(cpu: readCPUTicks(), counters: readPhysicalCounters(),
                                          memory: readMemoryPressure(),
                                          now: ProcessInfo.processInfo.systemUptime) else { return }
        summary.text = "CPU \(sample.cpu)% · 内存压力 \(sample.mem)% · ↓\(rateText(sample.rx)) ↑\(rateText(sample.tx))"
        if let port, !port.write(encodeSample(sample)) { disconnect() }
    }

    /// 依次尝试每个 WCH 串口，第一个能打开的就是板子。
    private func connect() {
        for path in boardCandidates(listSerialDevices()) {
            if let port = SerialPort(path: path) {
                self.port = port
                portPath = path
                return
            }
        }
    }

    private func disconnect() {
        port?.close()
        port = nil
        portPath = nil
    }

    private func rateText(_ bytesPerSecond: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .memory) + "/s"
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
            if let port, !port.write(offLine) { disconnect() }
            sampler.reset()
            summary.text = "已暂停（显示器睡眠或锁屏）"
            setActivity(false)
        } else if !wasActive && gate.active {
            setActivity(true)
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
