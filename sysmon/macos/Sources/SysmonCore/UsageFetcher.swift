import Foundation

// 用量请求与拉取。只读：凭据过期就报过期，不续期。
// 日志里只写服务名和状态码 / 错误类别，绝不写请求头、响应体或令牌。

private let usageTimeout: TimeInterval = 15

/// 把 HTTP 状态码分类。2xx 返回 nil，交给解析处理。
public func classify(statusCode: Int) -> FetchOutcome? {
    switch statusCode {
    case 200..<300: return nil
    case 401, 403: return .unauthorized
    case 429: return .rateLimited
    default: return .failed
    }
}

private func usageRequest(_ url: String, token: String) -> URLRequest {
    var r = URLRequest(url: URL(string: url)!, timeoutInterval: usageTimeout)
    r.httpMethod = "GET"
    r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    r.setValue("Sysmon", forHTTPHeaderField: "User-Agent")
    r.setValue("application/json", forHTTPHeaderField: "Accept")
    return r
}

public func claudeUsageRequest(_ c: ClaudeCredential) -> URLRequest {
    var r = usageRequest("https://api.anthropic.com/api/oauth/usage", token: c.accessToken)
    r.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    return r
}

public func codexUsageRequest(_ c: CodexCredential) -> URLRequest {
    var r = usageRequest("https://chatgpt.com/backend-api/wham/usage", token: c.accessToken)
    r.setValue(c.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
    return r
}

/// 拉取一次用量。读凭据会起子进程、读文件，放到 detached 任务里，不占主线程和协作线程池。
public func fetchUsage(_ service: UsageService, session: URLSession, now: Date) async -> FetchOutcome {
    let request: URLRequest
    let claudePlan: String?
    switch service {
    case .claude:
        guard let cred = await Task.detached(operation: { readClaudeCredential() }).value else {
            return .noCredential
        }
        if cred.expiresAt <= now { return .credentialExpired }
        request = claudeUsageRequest(cred)
        claudePlan = cred.plan
    case .chatgpt:
        guard let cred = await Task.detached(operation: { readCodexCredential() }).value else {
            return .noCredential
        }
        if let exp = cred.expiresAt, exp <= now { return .credentialExpired }
        request = codexUsageRequest(cred)
        claudePlan = nil
    }

    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await session.data(for: request)
    } catch {
        // 只记错误类别，不记 URL 和请求内容
        NSLog("Sysmon: %@ 用量请求失败（网络错误 %ld）", service.rawValue, (error as? URLError)?.errorCode ?? -1)
        return .failed
    }
    guard let http = response as? HTTPURLResponse else {
        NSLog("Sysmon: %@ 用量请求失败（非 HTTP 响应）", service.rawValue)
        return .failed
    }
    if let outcome = classify(statusCode: http.statusCode) {
        NSLog("Sysmon: %@ 用量请求失败（状态码 %ld）", service.rawValue, http.statusCode)
        return outcome
    }
    do {
        switch service {
        case .claude: return .success(try parseClaudeUsage(data, plan: claudePlan, now: now))
        case .chatgpt: return .success(try parseCodexUsage(data, now: now))
        }
    } catch {
        NSLog("Sysmon: %@ 用量响应解析失败", service.rawValue)
        return .failed
    }
}
