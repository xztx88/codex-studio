import Foundation
import AppKit
import Network
import CommonCrypto

final class AccountService {
    static let shared = AccountService()

    private let homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    private var storeURL: URL {
        homeURL.appendingPathComponent(".local/share/codex-account/accounts.json")
    }
    private var authURL: URL {
        homeURL.appendingPathComponent(".codex/auth.json")
    }

    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let resetCreditURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")!

    let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    let redirectURI = "http://localhost:1455/auth/callback"
    let userAgent = "codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal"

    // OAuth Local Server instance
    private var oauthListener: NWListener?

    // MARK: - JWT Helpers

    func jwtPayload(token: String) -> [String: Any]? {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return json
        }

        // Fallback for tokens with trailing duplicate characters/braces
        if let str = String(data: data, encoding: .utf8) {
            var recovered: [String: Any] = [:]
            if let emailMatch = str.range(of: "\"email\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                let sub = String(str[emailMatch])
                if let val = sub.components(separatedBy: ":").last?.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) {
                    recovered["email"] = val
                }
            }
            if let authRange = str.range(of: "\"https://api.openai.com/auth\"\\s*:\\s*\\{", options: .regularExpression) {
                let startIndex = authRange.upperBound
                var depth = 1
                var currentIndex = startIndex
                while currentIndex < str.endIndex && depth > 0 {
                    if str[currentIndex] == "{" { depth += 1 }
                    else if str[currentIndex] == "}" { depth -= 1 }
                    currentIndex = str.index(after: currentIndex)
                }
                if depth == 0 {
                    let authJsonStr = "{" + String(str[startIndex..<currentIndex])
                    if let authData = authJsonStr.data(using: .utf8),
                       let authObj = (try? JSONSerialization.jsonObject(with: authData)) as? [String: Any] {
                        recovered["https://api.openai.com/auth"] = authObj
                    }
                }
            }
            if !recovered.isEmpty {
                return recovered
            }
        }
        return nil
    }

    struct ClaimsInfo {
        var email: String?
        var accountId: String?
        var plan: String?
        var subscriptionStart: String?
        var subscriptionUntil: String?
        var organizationTitle: String?
        var exp: Double?
    }

    func extractClaims(idToken: String) -> ClaimsInfo {
        guard let payload = jwtPayload(token: idToken) else {
            return ClaimsInfo()
        }
        var email: String? = payload["email"] as? String
        if let profile = payload["https://api.openai.com/profile"] as? [String: Any] {
            if let pEmail = profile["email"] as? String, !pEmail.isEmpty {
                email = pEmail
            }
        }
        var accountId: String?
        var plan: String?
        var subStart: String?
        var subUntil: String?
        var orgTitle: String?

        if let auth = payload["https://api.openai.com/auth"] as? [String: Any] {
            accountId = auth["chatgpt_account_id"] as? String
            plan = auth["chatgpt_plan_type"] as? String
            subStart = auth["chatgpt_subscription_active_start"] as? String
            subUntil = auth["chatgpt_subscription_active_until"] as? String

            if let orgs = auth["organizations"] as? [[String: Any]] {
                for org in orgs {
                    let title = org["title"] as? String
                    if let t = title, !t.isEmpty, t.lowercased() != "personal" {
                        orgTitle = t
                        break
                    }
                }
            }
        }
        let exp = payload["exp"] as? Double

        return ClaimsInfo(
            email: email,
            accountId: accountId,
            plan: plan,
            subscriptionStart: subStart,
            subscriptionUntil: subUntil,
            organizationTitle: orgTitle,
            exp: exp
        )
    }

    func isTokenExpired(token: String?) -> Bool {
        guard let token = token, !token.isEmpty else { return true }
        guard let payload = jwtPayload(token: token),
              let exp = payload["exp"] as? Double else {
            return false
        }
        // Buffer of 60 seconds
        return exp < (Date().timeIntervalSince1970 + 60.0)
    }

    // MARK: - PKCE

    func generatePKCE() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let verifierData = verifier.data(using: .utf8)!
        verifierData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(verifierData.count), &hash)
        }
        let challenge = Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))

        return (verifier, challenge)
    }

    // MARK: - OAuth 2.0 PKCE Flow with Local Server

    func startOAuthServer(port: UInt16 = 1455, onResult: @escaping (Result<(code: String, state: String), Error>) -> Void) throws {
        stopOAuthServer()

        let queue = DispatchQueue(label: "codex.studio.oauth.queue")
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let listener = try NWListener(using: .tcp, on: nwPort)

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                guard let data = data, let reqStr = String(data: data, encoding: .utf8) else {
                    return
                }

                if reqStr.contains("GET /auth/callback") {
                    // Extract code and state from query
                    var code: String?
                    var state: String?

                    if let urlLine = reqStr.components(separatedBy: "\r\n").first,
                       let pathWithQuery = urlLine.components(separatedBy: " ").dropFirst().first,
                       let url = URL(string: "http://localhost\(pathWithQuery)"),
                       let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                        code = components.queryItems?.first(where: { $0.name == "code" })?.value
                        state = components.queryItems?.first(where: { $0.name == "state" })?.value
                    }

                    let successHTML = """
                    <!DOCTYPE html>
                    <html>
                    <head>
                        <meta charset="utf-8">
                        <title>Codex Studio 授权成功</title>
                        <style>
                            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f141c; color: #fff; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
                            .card { background: #1a2230; padding: 36px 48px; border-radius: 16px; border: 1px solid #2d3748; text-align: center; box-shadow: 0 12px 32px rgba(0,0,0,0.6); max-width: 440px; }
                            .icon { font-size: 48px; margin-bottom: 12px; }
                            h2 { color: #10b981; margin: 0 0 10px 0; font-size: 22px; }
                            p { color: #94a3b8; font-size: 14px; line-height: 1.6; margin: 0; }
                        </style>
                    </head>
                    <body>
                        <div class="card">
                            <div class="icon">✨</div>
                            <h2>OpenAI 账号授权成功</h2>
                            <p>凭证已安全传输至 Codex Studio 客户端。您可以关闭此网页并返回应用。</p>
                        </div>
                    </body>
                    </html>
                    """

                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(successHTML.utf8.count)\r\nConnection: close\r\n\r\n\(successHTML)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                        connection.cancel()
                    }))

                    self?.stopOAuthServer()

                    if let code = code, !code.isEmpty {
                        onResult(.success((code: code, state: state ?? "")))
                    } else {
                        onResult(.failure(NSError(domain: "CodexStudio", code: -4, userInfo: [NSLocalizedDescriptionKey: "未从回调中读取到 authorization code"])))
                    }
                } else {
                    let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
                    connection.send(content: notFound.data(using: .utf8), completion: .contentProcessed({ _ in
                        connection.cancel()
                    }))
                }
            }
        }

        listener.start(queue: queue)
        self.oauthListener = listener
    }

    func stopOAuthServer() {
        oauthListener?.cancel()
        oauthListener = nil
    }

    func exchangeCodeForTokens(code: String, verifier: String) async throws -> [String: Any] {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let params: [String: String] = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ]

        let bodyStr = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyStr.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "CodexStudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "未获取到有效响应"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CodexStudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "返回非合法 JSON"])
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "CodexStudio", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "兑换令牌失败: \(errorMsg)"])
        }

        return json
    }

    // MARK: - Process Helpers (Accurate & Reliable)

    private let chatgptBundleIdentifiers = ["com.openai.codex", "com.openai.chat"]

    func isChatGPTInstalled() -> Bool {
        if FileManager.default.fileExists(atPath: "/Applications/ChatGPT.app") {
            return true
        }
        for bid in chatgptBundleIdentifiers {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil {
                return true
            }
        }
        return false
    }

    func isChatGPTRunning() -> Bool {
        for bid in chatgptBundleIdentifiers {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            if apps.contains(where: { !$0.isTerminated }) {
                return true
            }
        }
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "/Applications/ChatGPT.app"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    @discardableResult
    func quitChatGPT() -> Bool {
        // 1. Terminate gracefully via macOS API
        for bid in chatgptBundleIdentifiers {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            for app in apps {
                app.terminate()
            }
        }

        // 2. Kill remaining child processes & helpers
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-9", "-f", "/Applications/ChatGPT.app"]
        try? task.run()
        task.waitUntilExit()

        // 3. Quick check for termination
        for _ in 0..<5 {
            if !isChatGPTRunning() { break }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return true
    }

    @discardableResult
    func launchChatGPT() -> Bool {
        for bid in chatgptBundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
                return true
            }
        }
        let appURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            return true
        }
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "/Applications/ChatGPT.app"]
        try? task.run()
        return true
    }

    // MARK: - Store Loading & Saving

    func loadStore() throws -> (active: String?, items: [AccountItem]) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return (nil, [])
        }
        let data = try Data(contentsOf: storeURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, [])
        }
        let active = json["active"] as? String
        let rawAccounts = json["accounts"] as? [[String: Any]] ?? []

        var items: [AccountItem] = []
        for raw in rawAccounts {
            guard let email = raw["email"] as? String,
                  let idToken = raw["id_token"] as? String,
                  let refreshToken = raw["refresh_token"] as? String else {
                continue
            }
            let accountId = (raw["chatgpt_account_id"] as? String) ?? (raw["account_id"] as? String) ?? ""
            let claims = extractClaims(idToken: idToken)
            let planStr = claims.plan ?? (raw["plan_type"] as? String) ?? "-"
            let plan = PlanType.from(string: planStr)
            let isActive = (email.lowercased() == (active ?? "").lowercased())
            let isEnabled = (raw["enabled"] as? Bool) ?? true
            let tag = raw["tag"] as? String

            items.append(AccountItem(
                email: email,
                chatgptAccountId: accountId.isEmpty ? (claims.accountId ?? "") : accountId,
                plan: plan,
                rawPlanString: planStr,
                idToken: idToken,
                accessToken: raw["access_token"] as? String,
                refreshToken: refreshToken,
                isActive: isActive,
                isEnabled: isEnabled,
                filenameTag: tag,
                organizationTitle: claims.organizationTitle,
                subscriptionUntil: claims.subscriptionUntil,
                subscriptionStart: claims.subscriptionStart,
                expiredDateStr: raw["expired"] as? String
            ))
        }

        items.sort { $0.email.lowercased() < $1.email.lowercased() }
        return (active, items)
    }

    func writeStore(active: String?, accounts: [AccountItem]) throws {
        let dir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])

        var rawList: [[String: Any]] = []
        for acc in accounts {
            var dict: [String: Any] = [
                "email": acc.email,
                "chatgpt_account_id": acc.chatgptAccountId,
                "plan_type": acc.rawPlanString,
                "id_token": acc.idToken,
                "refresh_token": acc.refreshToken,
                "enabled": acc.isEnabled
            ]
            if let access = acc.accessToken {
                dict["access_token"] = access
            }
            if let tag = acc.filenameTag {
                dict["tag"] = tag
            }
            rawList.append(dict)
        }

        let store: [String: Any] = [
            "active": active as Any,
            "accounts": rawList
        ]

        let data = try JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted, .sortedKeys])
        let tmpURL = storeURL.appendingPathExtension("tmp")
        try data.write(to: tmpURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
        _ = try? FileManager.default.removeItem(at: storeURL)
        try FileManager.default.moveItem(at: tmpURL, to: storeURL)
    }

    // MARK: - Switching & Refreshing

    func refreshTokens(refreshToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "CodexStudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "未知网络响应"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CodexStudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "服务器返回非合法 JSON"])
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "CodexStudio", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "刷新凭证失败 (\(errorMsg))"
            ])
        }

        guard json["access_token"] != nil, json["refresh_token"] != nil, json["id_token"] != nil else {
            throw NSError(domain: "CodexStudio", code: -2, userInfo: [NSLocalizedDescriptionKey: "返回凭证不完整"])
        }

        return json
    }

    func switchAccount(to target: AccountItem, autoRestartChatGPT: Bool) async throws {
        // 1. Prepare valid tokens (Skip remote HTTP network call if access token is still fresh!)
        var tokens: [String: Any]
        if let access = target.accessToken, !isTokenExpired(token: access) {
            tokens = [
                "access_token": access,
                "id_token": target.idToken,
                "refresh_token": target.refreshToken
            ]
        } else {
            // Only query OpenAI OAuth servers if expired or missing, done before quitting app
            do {
                tokens = try await refreshTokens(refreshToken: target.refreshToken)
            } catch {
                if let access = target.accessToken, !access.isEmpty {
                    tokens = [
                        "access_token": access,
                        "id_token": target.idToken,
                        "refresh_token": target.refreshToken
                    ]
                } else {
                    throw error
                }
            }
        }

        guard let idToken = tokens["id_token"] as? String,
              let accessToken = tokens["access_token"] as? String,
              let refreshToken = tokens["refresh_token"] as? String else {
            throw NSError(domain: "CodexStudio", code: -3, userInfo: [NSLocalizedDescriptionKey: "Token 解析失败"])
        }

        let claims = extractClaims(idToken: idToken)
        let accountId = claims.accountId ?? target.chatgptAccountId
        let email = claims.email ?? target.email

        // 2. Write to ~/.codex/auth.json
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nowString = isoFormatter.string(from: Date())

        let authData: [String: Any] = [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": NSNull(),
            "tokens": [
                "id_token": idToken,
                "access_token": accessToken,
                "refresh_token": refreshToken,
                "account_id": accountId
            ],
            "last_refresh": nowString
        ]

        let authJson = try JSONSerialization.data(withJSONObject: authData, options: [.prettyPrinted, .sortedKeys])
        let authDir = authURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: authDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try authJson.write(to: authURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)

        // 3. Update local store
        var (_, accounts) = try loadStore()
        for idx in 0..<accounts.count {
            if accounts[idx].email.lowercased() == email.lowercased() ||
               accounts[idx].chatgptAccountId == accountId {
                accounts[idx].idToken = idToken
                accounts[idx].accessToken = accessToken
                accounts[idx].refreshToken = refreshToken
                accounts[idx].chatgptAccountId = accountId
                accounts[idx].isActive = true
            } else {
                accounts[idx].isActive = false
            }
        }

        try writeStore(active: email, accounts: accounts)

        // 4. Instantly relaunch ChatGPT if requested
        if autoRestartChatGPT && isChatGPTInstalled() {
            let wasRunning = isChatGPTRunning()
            if wasRunning {
                quitChatGPT()
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
            launchChatGPT()
        }
    }

    // MARK: - Quota API Integration

    func fetchLiveQuota(account: AccountItem) async throws -> (quota: LiveQuota, newAccessToken: String?) {
        var token = account.accessToken
        var newAccessToken: String? = nil

        // If no access token or expired, refresh it first
        if isTokenExpired(token: token) {
            let refreshed = try await refreshTokens(refreshToken: account.refreshToken)
            if let freshAccess = refreshed["access_token"] as? String {
                token = freshAccess
                newAccessToken = freshAccess
            }
        }

        guard let validToken = token else {
            throw NSError(domain: "CodexStudio", code: -5, userInfo: [NSLocalizedDescriptionKey: "缺少有效 Access Token"])
        }

        do {
            let quota = try await queryUsageEndpoint(accessToken: validToken, accountId: account.chatgptAccountId)
            return (quota, newAccessToken)
        } catch let err as NSError where err.code == 401 {
            // Retry once with refresh
            let refreshed = try await refreshTokens(refreshToken: account.refreshToken)
            guard let freshAccess = refreshed["access_token"] as? String else {
                throw err
            }
            newAccessToken = freshAccess
            let quota = try await queryUsageEndpoint(accessToken: freshAccess, accountId: account.chatgptAccountId)
            return (quota, newAccessToken)
        }
    }

    private func queryUsageEndpoint(accessToken: String, accountId: String) async throws -> LiveQuota {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "CodexStudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "无响应"])
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw NSError(domain: "CodexStudio", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "凭据已失效 (401/403)"])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "CodexStudio", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "额度查询失败 (HTTP \(httpResponse.statusCode))"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CodexStudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "额度数据格式异常"])
        }

        var quota = LiveQuota()
        quota.planType = json["plan_type"] as? String ?? ""

        if let rateLimit = json["rate_limit"] as? [String: Any] {
            quota.allowed = rateLimit["allowed"] as? Bool ?? true
            quota.limitReached = rateLimit["limit_reached"] as? Bool ?? false

            if let primary = rateLimit["primary_window"] as? [String: Any] {
                quota.sessionUsedPercent = primary["used_percent"] as? Int ?? 0
                quota.sessionResetAfterSeconds = primary["reset_after_seconds"] as? Int
                quota.sessionResetAt = primary["reset_at"] as? Int64
            }

            if let secondary = rateLimit["secondary_window"] as? [String: Any] {
                quota.weeklyUsedPercent = secondary["used_percent"] as? Int ?? 0
                quota.weeklyResetAfterSeconds = secondary["reset_after_seconds"] as? Int
                quota.weeklyResetAt = secondary["reset_at"] as? Int64
            }
        }

        if let credits = json["credits"] as? [String: Any] {
            if let bal = credits["balance"] as? Double {
                quota.creditBalance = bal
            } else if let balInt = credits["balance"] as? Int {
                quota.creditBalance = Double(balInt)
            }
        }

        if let resetCredits = json["rate_limit_reset_credits"] as? [String: Any] {
            quota.resetCreditsCount = resetCredits["available_count"] as? Int ?? 0
        }

        quota.lastUpdated = Date()
        return quota
    }

    func consumeResetCredit(account: AccountItem) async throws -> LiveQuota {
        var token = account.accessToken
        if isTokenExpired(token: token) {
            let refreshed = try await refreshTokens(refreshToken: account.refreshToken)
            token = refreshed["access_token"] as? String
        }

        guard let validToken = token else {
            throw NSError(domain: "CodexStudio", code: -5, userInfo: [NSLocalizedDescriptionKey: "缺少有效 Access Token"])
        }

        var request = URLRequest(url: resetCreditURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(validToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if !account.chatgptAccountId.isEmpty {
            request.setValue(account.chatgptAccountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let body: [String: Any] = ["redeem_request_id": UUID().uuidString]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "CodexStudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "无网络响应"])
        }

        if httpResponse.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "CodexStudio", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "重置失败: \(msg)"])
        }

        // Immediately fetch updated quota
        let (updatedQuota, _) = try await fetchLiveQuota(account: account)
        return updatedQuota
    }

    // MARK: - Add / Import Account

    func addAccountManual(refreshToken: String, accessToken: String?, accountId: String?) async throws -> AccountItem {
        let trimmedRefresh = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRefresh.isEmpty else {
            throw NSError(domain: "CodexStudio", code: -12, userInfo: [NSLocalizedDescriptionKey: "Refresh Token 不能为空"])
        }

        // Validate by refreshing
        let tokenResp = try await refreshTokens(refreshToken: trimmedRefresh)
        guard let idToken = tokenResp["id_token"] as? String,
              let freshAccess = tokenResp["access_token"] as? String else {
            throw NSError(domain: "CodexStudio", code: -13, userInfo: [NSLocalizedDescriptionKey: "获取到的 Token 凭证不完整"])
        }

        let claims = extractClaims(idToken: idToken)
        let resolvedEmail = claims.email ?? "user@openai.com"
        let resolvedAccountId = claims.accountId ?? (accountId ?? "")
        let resolvedPlanStr = claims.plan ?? "plus"
        let plan = PlanType.from(string: resolvedPlanStr)

        var account = AccountItem(
            email: resolvedEmail,
            chatgptAccountId: resolvedAccountId,
            plan: plan,
            rawPlanString: resolvedPlanStr,
            idToken: idToken,
            accessToken: freshAccess,
            refreshToken: trimmedRefresh,
            isActive: false,
            isEnabled: true,
            filenameTag: "manual-token",
            organizationTitle: claims.organizationTitle,
            subscriptionUntil: claims.subscriptionUntil,
            subscriptionStart: claims.subscriptionStart
        )

        // Try fetch live quota
        if let (quota, _) = try? await fetchLiveQuota(account: account) {
            account.liveQuota = quota
        }

        // Save to store
        var (active, accounts) = try loadStore()
        accounts.removeAll { $0.email.lowercased() == account.email.lowercased() }
        accounts.append(account)
        try writeStore(active: active, accounts: accounts)

        return account
    }

    func importAccount(from fileURL: URL) async throws -> AccountItem {
        let data = try Data(contentsOf: fileURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CodexStudio", code: -10, userInfo: [NSLocalizedDescriptionKey: "无法解析该文件为 JSON"])
        }

        let tokens = (json["tokens"] as? [String: Any]) ?? json
        guard let idToken = tokens["id_token"] as? String ?? json["id_token"] as? String,
              let refreshToken = tokens["refresh_token"] as? String ?? json["refresh_token"] as? String else {
            throw NSError(domain: "CodexStudio", code: -11, userInfo: [NSLocalizedDescriptionKey: "文件中缺少有效的 id_token 或 refresh_token"])
        }

        var accessToken = tokens["access_token"] as? String ?? json["access_token"] as? String
        var accountId = tokens["account_id"] as? String
            ?? tokens["chatgpt_account_id"] as? String
            ?? json["account_id"] as? String
            ?? json["chatgpt_account_id"] as? String

        let claims = extractClaims(idToken: idToken)
        var email = json["email"] as? String ?? claims.email
        if email == nil || email?.isEmpty == true {
            email = claims.email ?? accountId ?? "unknown"
        }
        if accountId == nil || accountId?.isEmpty == true {
            accountId = claims.accountId ?? ""
        }

        let planStr = json["plan_type"] as? String ?? claims.plan ?? "-"
        let plan = PlanType.from(string: planStr)

        // Refresh token if needed
        if isTokenExpired(token: accessToken) {
            if let refreshed = try? await refreshTokens(refreshToken: refreshToken) {
                accessToken = refreshed["access_token"] as? String
            }
        }

        var account = AccountItem(
            email: email!,
            chatgptAccountId: accountId ?? "",
            plan: plan,
            rawPlanString: planStr,
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: refreshToken,
            isActive: false,
            isEnabled: true,
            filenameTag: fileURL.lastPathComponent,
            organizationTitle: claims.organizationTitle,
            subscriptionUntil: claims.subscriptionUntil,
            subscriptionStart: claims.subscriptionStart
        )

        // Try fetch live quota
        if let (quota, _) = try? await fetchLiveQuota(account: account) {
            account.liveQuota = quota
        }

        var (active, accounts) = try loadStore()
        accounts.removeAll { $0.email.lowercased() == account.email.lowercased() }
        accounts.append(account)
        try writeStore(active: active, accounts: accounts)

        return account
    }

    func exportAccount(account: AccountItem, to destinationURL: URL) throws {
        var exportDict: [String: Any] = [
            "email": account.email,
            "chatgpt_account_id": account.chatgptAccountId,
            "plan_type": account.rawPlanString,
            "id_token": account.idToken,
            "refresh_token": account.refreshToken
        ]
        if let access = account.accessToken {
            exportDict["access_token"] = access
        }

        let data = try JSONSerialization.data(withJSONObject: exportDict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destinationURL, options: .atomic)
    }

    func deleteAccount(email: String) throws {
        var (active, accounts) = try loadStore()
        accounts.removeAll { $0.email.lowercased() == email.lowercased() }
        if active?.lowercased() == email.lowercased() {
            active = accounts.first?.email
        }
        try writeStore(active: active, accounts: accounts)
    }
}
