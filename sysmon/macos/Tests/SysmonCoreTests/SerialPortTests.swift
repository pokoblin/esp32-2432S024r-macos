import Foundation
import Testing
@testable import SysmonCore

/// 设备还在但不再收数据（USB 卡住）时，write 不能把调用方（主线程）永久卡住，
/// 连续多次写不出去后应返回 false，让程序断开重连。用没人读的伪终端模拟。
@Test func writeDoesNotBlockWhenOutputIsStuck() throws {
    var master: Int32 = -1
    var slave: Int32 = -1
    var name = [CChar](repeating: 0, count: 128)
    try #require(openpty(&master, &slave, &name, nil, nil) == 0)
    defer {
        close(master)
        close(slave)
    }
    let path = name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    let port = try #require(SerialPort(path: path))

    nonisolated(unsafe) let p = port
    nonisolated(unsafe) var reportedDead = false
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        let line = String(repeating: "x", count: 63) + "\n"
        for _ in 0..<5000 where !reportedDead {
            reportedDead = !p.write(line)
        }
        done.signal()
    }
    #expect(done.wait(timeout: .now() + 3) == .success)
    #expect(reportedDead)
}
