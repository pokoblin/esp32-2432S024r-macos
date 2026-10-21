import Darwin

/// kern.memorystatus_level 是可用内存的百分比，压力百分比取 100 减去它。
public func memoryPercent(availableLevel: Int) -> Int {
    min(max(100 - availableLevel, 0), 100)
}

/// 系统压力等级：1 正常，2 警告，4 严重；其他值按正常处理。
public func normalizePressureLevel(_ raw: Int) -> Int {
    [1, 2, 4].contains(raw) ? raw : 1
}

/// percent 决定圆环弧长和数字，level 决定颜色（和活动监视器的内存压力图同一来源）。
public func readMemoryPressure() -> (percent: Int, level: Int)? {
    guard let available = sysctlInt32("kern.memorystatus_level"),
          let level = sysctlInt32("kern.memorystatus_vm_pressure_level") else { return nil }
    return (memoryPercent(availableLevel: available), normalizePressureLevel(level))
}

private func sysctlInt32(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
}
