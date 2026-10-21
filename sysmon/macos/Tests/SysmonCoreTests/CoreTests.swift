import Testing
@testable import SysmonCore

@Test func encodesSample() {
    let s = Sample(cpu: 37, mem: 51, level: 1, rx: 13_002_342, tx: 880_640)
    #expect(encodeSample(s) == "S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640\n")
}

@Test func encodeClampsRates() {
    let s = Sample(cpu: 1, mem: 1, level: 1, rx: 5_000_000_000, tx: 0)
    #expect(encodeSample(s).contains("rx=4294967295"))
    #expect(offLine == "OFF\n")
}

@Test func cpuPercentMath() {
    let a = CPUTicks(user: 100, system: 100, idle: 800, nice: 0)
    let b = CPUTicks(user: 150, system: 150, idle: 900, nice: 0)
    #expect(cpuPercent(prev: a, cur: b) == 50)
    #expect(cpuPercent(prev: a, cur: a) == 0)
}

@Test func memoryMath() {
    #expect(memoryPercent(availableLevel: 49) == 51)
    #expect(memoryPercent(availableLevel: 120) == 0)
    #expect([1, 2, 4, 0, 3].map(normalizePressureLevel) == [1, 2, 4, 1, 1])
}

@Test func physicalFilter() {
    #expect(isPhysicalInterface(name: "en0", type: 6))
    #expect(isPhysicalInterface(name: "en5", type: 6))
    #expect(!isPhysicalInterface(name: "utun3", type: 1))
    #expect(!isPhysicalInterface(name: "awdl0", type: 6))
    #expect(!isPhysicalInterface(name: "llw0", type: 6))
    #expect(!isPhysicalInterface(name: "anpi0", type: 6))
    #expect(!isPhysicalInterface(name: "bridge0", type: 209))
    #expect(!isPhysicalInterface(name: "lo0", type: 24))
}

@Test func counterWrap() {
    #expect(counterDelta(prev: 10, cur: 30) == 20)
    #expect(counterDelta(prev: UInt32.max - 99, cur: 100) == 200)
}

@Test func rateMeterBasics() {
    var m = RateMeter()
    #expect(m.update(["en0": IfCounters(rx: 1000, tx: 0)], elapsed: 2) == nil)
    let r = m.update(["en0": IfCounters(rx: 3000, tx: 500)], elapsed: 2)
    #expect(r?.rx == 1000)
    #expect(r?.tx == 250)
}

@Test func rateMeterInterfaceChurn() {
    var m = RateMeter()
    _ = m.update(["en0": IfCounters(rx: 0, tx: 0)], elapsed: 1)
    // en7 新出现：这一轮只算 en0
    let r1 = m.update(["en0": IfCounters(rx: 100, tx: 10), "en7": IfCounters(rx: 5_000_000, tx: 0)], elapsed: 1)
    #expect(r1?.rx == 100)
    #expect(r1?.tx == 10)
    // en0 消失：只算 en7
    let r2 = m.update(["en7": IfCounters(rx: 5_000_400, tx: 0)], elapsed: 1)
    #expect(r2?.rx == 400)
    #expect(r2?.tx == 0)
}

@Test func boardCandidatesOnlyWCH() {
    let devices = [
        SerialDevice(path: "/dev/cu.usbserial-A10K", vendorID: 0x0403),  // FTDI
        SerialDevice(path: "/dev/cu.usbserial-114110", vendorID: 0x1a86),
        SerialDevice(path: "/dev/cu.Bluetooth-Incoming-Port", vendorID: nil),
        SerialDevice(path: "/dev/cu.usbserial-110", vendorID: 0x1a86),
    ]
    #expect(boardCandidates(devices) == ["/dev/cu.usbserial-110", "/dev/cu.usbserial-114110"])
    #expect(boardCandidates([SerialDevice(path: "/dev/cu.usbserial-A10K", vendorID: 0x0403)]).isEmpty)
    #expect(boardCandidates([]).isEmpty)
}

@Test func displayGate() {
    var g = DisplayGate()
    #expect(g.active)
    g.screensAsleep = true
    #expect(!g.active)
    g.screensAsleep = false
    g.locked = true
    #expect(!g.active)
}

@Test func readersReturnPlausibleValues() {
    #expect(readCPUTicks() != nil)
    let mem = readMemoryPressure()
    #expect(mem != nil)
    #expect([1, 2, 4].contains(mem?.level ?? -1))
    #expect(readPhysicalCounters()["en0"] != nil)
}

@Test func rateMeterIgnoresCounterReset() {
    // 扩展坞网卡在两次采样之间重新枚举，计数从 50 万掉回 10，不能当成 32 位回绕算出约 2 GB/s
    var m = RateMeter()
    _ = m.update(["en7": IfCounters(rx: 500_000, tx: 0)], elapsed: 2)
    let r = m.update(["en7": IfCounters(rx: 10, tx: 0)], elapsed: 2)
    #expect(r?.rx == 0)
    // 真正的回绕仍然照常计算
    _ = m.update(["en7": IfCounters(rx: UInt32.max - 99, tx: 0)], elapsed: 2)
    let w = m.update(["en7": IfCounters(rx: 100, tx: 0)], elapsed: 2)
    #expect(w?.rx == 100)
}
