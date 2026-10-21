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

@Test func lineBufferSplitsAcrossChunks() {
    var b = SerialLineBuffer()
    #expect(b.append(Array("TA".utf8)) == [])
    #expect(b.append(Array("P\r\nfoo\n".utf8)) == ["TAP", "foo"])
}

@Test func lineBufferDropsOverlong() {
    var b = SerialLineBuffer()
    #expect(b.append(Array(repeating: UInt8(ascii: "x"), count: 300) + Array("\nTAP\n".utf8)) == ["TAP"])
}

@Test func lineBufferToleratesInvalidUTF8() {
    var b = SerialLineBuffer()
    #expect(b.append([0xff, 0xfe, 0x0a] + Array("TAP\n".utf8)).last == "TAP")
}

/// 伪终端另一头写进来的行，要在主线程通过 onLine 交出来；另一头关掉后端口应判为失联。
@MainActor
@Test func readsLinesAndDetectsHangup() async throws {
    var master: Int32 = -1
    var slave: Int32 = -1
    var name = [CChar](repeating: 0, count: 128)
    try #require(openpty(&master, &slave, &name, nil, nil) == 0)
    let path = name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    let port = try #require(SerialPort(path: path))
    // 和 SerialPort 一样独占打开后，slave 这端可以关掉；只留 master 当"板子"
    close(slave)

    var received: [String] = []
    port.onLine = { received.append($0) }
    port.startReading()

    let msg = Array("TAP\r\n".utf8)
    #expect(Darwin.write(master, msg, msg.count) == msg.count)
    // 带超时轮询：读路径坏了要失败，不能一直挂着
    for _ in 0..<150 where received.isEmpty {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(received == ["TAP"])

    // 板子端断开：不能先调 write（write 自己遇到 EIO 也会返回 false），
    // 要等读路径自己读到 EOF/EIO 并关掉端口，之后 write 才返回 false
    close(master)
    for _ in 0..<150 where port.isOpen {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!port.isOpen)
    #expect(port.write("x\n") == false)
    port.close()
}
