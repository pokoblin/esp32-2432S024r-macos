import Foundation

// 只读取别的程序已经存好的凭据：不续期、不写钥匙串、不写 auth.json。
// 令牌绝不能出现在日志或 description 里。

/// Claude Code 存在钥匙串里的 OAuth 凭据。
public struct ClaudeCredential: Sendable, CustomStringConvertible {
    public var accessToken: String
    public var expiresAt: Date
    /// 小写 ASCII，例如 "max"
    public var plan: String?

    public init(accessToken: String, expiresAt: Date, plan: String? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.plan = plan
    }

    /// 不含令牌
    public var description: String {
        "ClaudeCredential(expiresAt: \(expiresAt), plan: \(plan ?? "nil"))"
    }
}

/// Codex 存在 ~/.codex/auth.json 里的凭据。
public struct CodexCredential: Sendable, CustomStringConvertible {
    public var accessToken: String
    public var accountID: String
    /// 取自 access_token（JWT）的 exp；解不出来就是 nil
    public var expiresAt: Date?

    public init(accessToken: String, accountID: String, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.accountID = accountID
        self.expiresAt = expiresAt
    }

    /// 不含令牌
    public var description: String {
        "CodexCredential(accountID: \(accountID), expiresAt: \(expiresAt.map { "\($0)" } ?? "nil"))"
    }
}

/// 解析钥匙串里 "Claude Code-credentials" 的内容。
/// 顶层除了 claudeAiOauth 还可能有 mcpOAuth 等其它键，直接忽略。
/// expiresAt 是毫秒时间戳。
public func parseClaudeKeychainJSON(_ data: Data) -> ClaudeCredential? {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let oauth = root["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String, !token.isEmpty,
          let expiresMs = number(oauth["expiresAt"]) else { return nil }
    return ClaudeCredential(accessToken: token,
                            expiresAt: Date(timeIntervalSince1970: expiresMs / 1000),
                            plan: normalizePlan(oauth["subscriptionType"] as? String))
}

/// 解析 ~/.codex/auth.json。
public func parseCodexAuthJSON(_ data: Data) -> CodexCredential? {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let tokens = root["tokens"] as? [String: Any],
          let token = tokens["access_token"] as? String, !token.isEmpty,
          let account = tokens["account_id"] as? String, !account.isEmpty else { return nil }
    return CodexCredential(accessToken: token, accountID: account, expiresAt: jwtExpiry(token))
}

/// 取 JWT payload 里的 exp（秒）。格式不对、没有 exp 都返回 nil；不校验签名。
public func jwtExpiry(_ token: String) -> Date? {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    // base64url → base64，并补齐 padding
    var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
    guard let payload = Data(base64Encoded: b64),
          let obj = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
          let exp = number(obj["exp"]) else { return nil }
    return Date(timeIntervalSince1970: exp)
}

/// 给 DispatchWorkItem 用的 Process 包装：terminate() 本身线程安全，这里只是让 Swift 6 放行。
private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

/// 运行子进程并返回 stdout。启动失败、退出码非 0、超过 timeout 秒没退出（会被终止）都返回 nil。
/// stderr、stdin 都指向 /dev/null。会阻塞到子进程退出，别在主线程调用。
func runCapturingStdout(_ path: String, arguments: [String], timeout: TimeInterval) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let out = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do { try process.run() } catch { return nil }

    // 超时就终止子进程；进程一死管道就到 EOF，下面的读取也跟着返回
    let box = ProcessBox(process)
    let killer = DispatchWorkItem { if box.process.isRunning { box.process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

    // 先读到 EOF 再等退出，避免输出塞满管道造成死锁
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    killer.cancel()
    guard process.terminationStatus == 0, process.terminationReason == .exit else { return nil }
    return data
}

/// 用 /usr/bin/security 子进程读取钥匙串里的 Claude Code 凭据。
/// 会阻塞（最多约 5 秒，之后终止子进程），别在主线程调用。找不到、超时或格式不对时返回 nil。
public func readClaudeCredential() -> ClaudeCredential? {
    guard let data = runCapturingStdout(
        "/usr/bin/security",
        arguments: ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
        timeout: 5) else { return nil }
    return parseClaudeKeychainJSON(data)
}

/// 读取 ~/.codex/auth.json。文件不存在或格式不对时返回 nil。
public func readCodexCredential(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CodexCredential? {
    let url = home.appendingPathComponent(".codex/auth.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return parseCodexAuthJSON(data)
}
