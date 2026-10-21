import AppKit
import ServiceManagement
import SysmonCore

/// 每 2 秒采集一次 CPU / 内存压力 / 网速，通过串口发给副屏。
/// 显示器睡眠、锁屏、切换用户或系统睡眠时发 OFF 并暂停；串口断开后每次触发时自动重连。
@MainActor
final class MonitorController: ObservableObject {
    @Published private(set) var portPath: String?
    @Published private(set) var summary = "等待数据…"
    @Published private(set) var launchAtLogin = false

    private static let interval: TimeInterval = 2

    private var port: SerialPort?
    private var gate = DisplayGate()
    private var rateMeter = RateMeter()
    private var lastCPU: CPUTicks?
    private var lastTime: TimeInterval?
    private var timer: Timer?
    // 菜单栏程序常驻后台，不持有这个 activity 的话定时器会被 App Nap 拖慢
    private var activity: NSObjectProtocol?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Send system stats to the ESP32 screen")
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
        guard let port else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let ticks = readCPUTicks()
        let counters = readPhysicalCounters()
        let elapsed = lastTime.map { now - $0 } ?? 0
        let cpu = zip(lastCPU, ticks).map { cpuPercent(prev: $0, cur: $1) }
        lastTime = now
        lastCPU = ticks

        // 第一次只建立基线，下一次才有速率和 CPU 差值
        guard let rates = rateMeter.update(counters, elapsed: elapsed),
              let cpu, let mem = readMemoryPressure() else { return }

        let sample = Sample(cpu: cpu, mem: mem.percent, level: mem.level, rx: rates.rx, tx: rates.tx)
        summary = "CPU \(cpu)% · 内存压力 \(mem.percent)% · ↓\(rateText(rates.rx)) ↑\(rateText(rates.tx))"
        if !port.write(encodeSample(sample)) { disconnect() }
    }

    private func connect() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        guard let path = pickSerialDevice(from: names), let port = SerialPort(path: path) else { return }
        self.port = port
        portPath = path
        resetBaselines()
    }

    private func disconnect() {
        port?.close()
        port = nil
        portPath = nil
        summary = "等待数据…"
        resetBaselines()
    }

    private func resetBaselines() {
        rateMeter = RateMeter()
        lastCPU = nil
        lastTime = nil
    }

    private func rateText(_ bytesPerSecond: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .memory) + "/s"
    }

    // MARK: - 显示器睡眠 / 锁屏联动

    private func updateGate(_ change: (inout DisplayGate) -> Void) {
        let wasActive = gate.active
        change(&gate)
        if wasActive && !gate.active {
            if let port, !port.write(offLine) { disconnect() }
            resetBaselines()
        } else if !wasActive && gate.active {
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

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
