import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: NavTab = .accounts
    @Published var accounts: [AccountItem] = []
    @Published var activeEmail: String?
    @Published var searchQuery: String = ""
    @Published var isChatGPTRunning: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = "正在处理中..."
    @Published var isDropTargeted: Bool = false
    @Published var toast: ToastInfo?

    // Dialogs & Sheets
    @Published var switchTarget: AccountItem?
    @Published var deleteTarget: AccountItem?
    @Published var resetCreditTarget: AccountItem?
    @Published var autoRestartOnSwitch: Bool = true

    // Add Account Sheet
    @Published var isAddModalPresented: Bool = false
    @Published var addModalTab: AddAccountTab = .browser
    @Published var isOAuthWaiting: Bool = false
    @Published var oauthStatusText: String = "点击下方按钮将在系统浏览器中打开 OpenAI 官方登录授权页面"
    private var currentOAuthVerifier: String = ""

    // Manual input fields
    @Published var manualRefreshToken: String = ""
    @Published var manualAccessToken: String = ""
    @Published var manualAccountId: String = ""

    @Published var isChatGPTInstalled: Bool = true

    // MARK: - Auto Periodic Quota Refresh
    @Published var isAutoRefreshEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoRefreshEnabled, forKey: "isAutoRefreshEnabled")
            resetAutoRefreshCountdown()
        }
    }
    @Published var autoRefreshInterval: Int {
        didSet {
            UserDefaults.standard.set(autoRefreshInterval, forKey: "autoRefreshInterval")
            resetAutoRefreshCountdown()
        }
    }
    @Published var secondsUntilNextRefresh: Int = 300
    @Published var lastRefreshedAt: Date? = nil
    @Published var uiTick: Int = 0

    private var processTimer: Timer?
    private var tickerTimer: Timer?

    init() {
        let savedAuto = UserDefaults.standard.object(forKey: "isAutoRefreshEnabled") as? Bool ?? true
        let savedInterval = UserDefaults.standard.integer(forKey: "autoRefreshInterval")
        let interval = savedInterval > 0 ? savedInterval : 300

        self.isAutoRefreshEnabled = savedAuto
        self.autoRefreshInterval = interval
        self.secondsUntilNextRefresh = interval

        refresh()
        startPolling()
        startTicker()

        // Auto refresh quotas on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshAllQuotas(silent: true)
        }
    }

    deinit {
        processTimer?.invalidate()
        tickerTimer?.invalidate()
    }

    func startPolling() {
        processTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkRunningStatus()
            }
        }
    }

    func startTicker() {
        tickerTimer?.invalidate()
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.uiTick += 1
                if self.isAutoRefreshEnabled {
                    self.secondsUntilNextRefresh -= 1
                    if self.secondsUntilNextRefresh <= 0 {
                        self.secondsUntilNextRefresh = self.autoRefreshInterval
                        self.refreshAllQuotas(silent: true)
                    }
                }
            }
        }
    }

    func resetAutoRefreshCountdown() {
        self.secondsUntilNextRefresh = self.autoRefreshInterval
    }

    func checkRunningStatus() {
        self.isChatGPTInstalled = AccountService.shared.isChatGPTInstalled()
        self.isChatGPTRunning = AccountService.shared.isChatGPTRunning()
    }

    func refresh() {
        checkRunningStatus()
        do {
            let (active, items) = try AccountService.shared.loadStore()
            self.activeEmail = active
            // Preserve existing liveQuota and refresh state
            var mergedItems: [AccountItem] = []
            for item in items {
                var copy = item
                if let existing = self.accounts.first(where: { $0.email.lowercased() == item.email.lowercased() }) {
                    copy.liveQuota = existing.liveQuota
                    copy.isRefreshingQuota = existing.isRefreshingQuota
                }
                mergedItems.append(copy)
            }
            self.accounts = mergedItems
        } catch {
            showToast("加载账号失败: \(error.localizedDescription)", type: .error)
        }
    }

    var activeAccount: AccountItem? {
        guard let activeEmail = activeEmail else { return nil }
        return accounts.first { $0.email.lowercased() == activeEmail.lowercased() }
    }

    var filteredAccounts: [AccountItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return accounts }
        return accounts.filter {
            $0.email.lowercased().contains(q) ||
            $0.chatgptAccountId.lowercased().contains(q) ||
            $0.plan.displayName.lowercased().contains(q) ||
            ($0.filenameTag ?? "").lowercased().contains(q)
        }
    }

    func showToast(_ message: String, type: ToastType = .info) {
        self.toast = ToastInfo(message: message, type: type)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if self?.toast?.message == message {
                self?.toast = nil
            }
        }
    }

    // MARK: - Switching Account

    func promptSwitch(to account: AccountItem) {
        if account.isActive {
            showToast("当前已经是 \(account.email)", type: .info)
            return
        }
        self.switchTarget = account
    }

    func confirmSwitch(to target: AccountItem) {
        self.switchTarget = nil
        self.isLoading = true
        self.loadingMessage = "正在切换至 \(target.email)..."

        let autoRestart = self.autoRestartOnSwitch
        Task {
            do {
                try await AccountService.shared.switchAccount(to: target, autoRestartChatGPT: autoRestart)
                self.refresh()
                self.isLoading = false
                if autoRestart {
                    self.showToast("已切换至 \(target.email)，ChatGPT 已重启生效", type: .success)
                } else {
                    self.showToast("已切换至 \(target.email)，重新打开 ChatGPT 后生效", type: .success)
                }
            } catch {
                self.isLoading = false
                self.showToast("切换失败: \(error.localizedDescription)", type: .error)
            }
        }
    }

    // MARK: - Deleting Account

    func promptDelete(account: AccountItem) {
        self.deleteTarget = account
    }

    func confirmDelete() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        do {
            try AccountService.shared.deleteAccount(email: target.email)
            refresh()
            showToast("已删除账号 \(target.email)", type: .success)
        } catch {
            showToast("删除失败: \(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - Quota Management

    func refreshQuota(for account: AccountItem) {
        guard let index = accounts.firstIndex(where: { $0.email.lowercased() == account.email.lowercased() }) else { return }
        accounts[index].isRefreshingQuota = true
        let targetEmail = account.email

        Task {
            do {
                let (quota, freshAccess) = try await AccountService.shared.fetchLiveQuota(account: account)
                if let idx = self.accounts.firstIndex(where: { $0.email.lowercased() == targetEmail.lowercased() }) {
                    self.accounts[idx].liveQuota = quota
                    if let freshAccess = freshAccess {
                        self.accounts[idx].accessToken = freshAccess
                    }
                    if !quota.planType.isEmpty {
                        let detected = PlanType.from(string: quota.planType)
                        if detected != .unknown {
                            self.accounts[idx].plan = detected
                            self.accounts[idx].rawPlanString = quota.planType
                        }
                    }
                    self.accounts[idx].isRefreshingQuota = false
                    try? AccountService.shared.writeStore(active: self.activeEmail, accounts: self.accounts)
                }
                self.showToast("\(targetEmail) 额度已更新", type: .success)
            } catch {
                if let idx = self.accounts.firstIndex(where: { $0.email.lowercased() == targetEmail.lowercased() }) {
                    self.accounts[idx].isRefreshingQuota = false
                    var q = self.accounts[idx].liveQuota ?? LiveQuota()
                    q.errorMessage = error.localizedDescription
                    self.accounts[idx].liveQuota = q
                }
                self.showToast("刷新 \(targetEmail) 额度失败: \(error.localizedDescription)", type: .error)
            }
        }
    }

    func refreshAllQuotas(silent: Bool = false) {
        if !silent {
            showToast("正在批量刷新所有账号额度...", type: .info)
        }
        for acc in accounts {
            let targetEmail = acc.email
            if let idx = self.accounts.firstIndex(where: { $0.email.lowercased() == targetEmail.lowercased() }) {
                self.accounts[idx].isRefreshingQuota = true
            }
            Task {
                do {
                    let (quota, freshAccess) = try await AccountService.shared.fetchLiveQuota(account: acc)
                    if let idx = self.accounts.firstIndex(where: { $0.email.lowercased() == targetEmail.lowercased() }) {
                        self.accounts[idx].liveQuota = quota
                        if let freshAccess = freshAccess {
                            self.accounts[idx].accessToken = freshAccess
                        }
                        if !quota.planType.isEmpty {
                            let detected = PlanType.from(string: quota.planType)
                            if detected != .unknown {
                                self.accounts[idx].plan = detected
                                self.accounts[idx].rawPlanString = quota.planType
                            }
                        }
                        self.accounts[idx].isRefreshingQuota = false
                        try? AccountService.shared.writeStore(active: self.activeEmail, accounts: self.accounts)
                    }
                } catch {
                    if let idx = self.accounts.firstIndex(where: { $0.email.lowercased() == targetEmail.lowercased() }) {
                        self.accounts[idx].isRefreshingQuota = false
                        var q = self.accounts[idx].liveQuota ?? LiveQuota()
                        q.errorMessage = error.localizedDescription
                        self.accounts[idx].liveQuota = q
                    }
                }
            }
        }
        self.lastRefreshedAt = Date()
        self.secondsUntilNextRefresh = self.autoRefreshInterval
    }

    func promptResetCredit(for account: AccountItem) {
        self.resetCreditTarget = account
    }

    func confirmResetCredit() {
        guard let target = resetCreditTarget else { return }
        resetCreditTarget = nil
        isLoading = true
        loadingMessage = "正在消耗重置次数并清空 5h 限额..."

        Task {
            do {
                let updated = try await AccountService.shared.consumeResetCredit(account: target)
                if let idx = self.accounts.firstIndex(where: { $0.id == target.id }) {
                    self.accounts[idx].liveQuota = updated
                    try? AccountService.shared.writeStore(active: self.activeEmail, accounts: self.accounts)
                }
                self.isLoading = false
                self.showToast("5小时额度已成功重置回 100%！", type: .success)
            } catch {
                self.isLoading = false
                self.showToast("重置额度失败: \(error.localizedDescription)", type: .error)
            }
        }
    }

    // MARK: - Toggle & Export

    func toggleAccountEnabled(account: AccountItem) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[idx].isEnabled.toggle()
        try? AccountService.shared.writeStore(active: activeEmail, accounts: accounts)
        let stateStr = accounts[idx].isEnabled ? "启用" : "禁用"
        showToast("已\(stateStr)账号 \(account.email)", type: .info)
    }

    func exportAccount(account: AccountItem) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "codex-\(account.email).json"
        savePanel.prompt = "导出"
        savePanel.message = "导出账号凭证 JSON 文件"

        if savePanel.runModal() == .OK, let destinationURL = savePanel.url {
            do {
                try AccountService.shared.exportAccount(account: account, to: destinationURL)
                showToast("已成功导出凭证至 \(destinationURL.lastPathComponent)", type: .success)
            } catch {
                showToast("导出失败: \(error.localizedDescription)", type: .error)
            }
        }
    }

    // MARK: - Method 1: File Import

    func importFromFile(url: URL) {
        isLoading = true
        loadingMessage = "正在解析并导入账号..."
        Task {
            do {
                let item = try await AccountService.shared.importAccount(from: url)
                self.refresh()
                self.isLoading = false
                self.isAddModalPresented = false
                self.showToast("已导入账号: \(item.email)，正在同步实时用量...", type: .success)
                // 主动触发实时额度刷新
                self.refreshQuota(for: item)
            } catch {
                self.isLoading = false
                self.showToast("导入失败: \(error.localizedDescription)", type: .error)
            }
        }
    }

    // MARK: - Method 2: Manual Token

    func submitManualToken() {
        let refToken = manualRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refToken.isEmpty else {
            showToast("请填写 Refresh Token", type: .error)
            return
        }

        isLoading = true
        loadingMessage = "正在验证 Token 并提取账号信息..."
        let accToken = manualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let accId = manualAccountId.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let item = try await AccountService.shared.addAccountManual(
                    refreshToken: refToken,
                    accessToken: accToken.isEmpty ? nil : accToken,
                    accountId: accId.isEmpty ? nil : accId
                )
                self.refresh()
                self.isLoading = false
                self.isAddModalPresented = false
                self.manualRefreshToken = ""
                self.manualAccessToken = ""
                self.manualAccountId = ""
                self.showToast("已添加账号: \(item.email)，正在同步实时用量...", type: .success)
                // 主动触发实时额度刷新
                self.refreshQuota(for: item)
            } catch {
                self.isLoading = false
                self.showToast("添加账号失败: \(error.localizedDescription)", type: .error)
            }
        }
    }

    // MARK: - Method 3: Browser OAuth Flow

    func startBrowserOAuth() {
        let (verifier, challenge) = AccountService.shared.generatePKCE()
        self.currentOAuthVerifier = verifier
        let state = UUID().uuidString

        do {
            try AccountService.shared.startOAuthServer(port: 1455) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let payload):
                        self?.handleOAuthCodeReceived(code: payload.code, verifier: verifier)
                    case .failure(let error):
                        self?.isOAuthWaiting = false
                        self?.oauthStatusText = "授权监听失败: \(error.localizedDescription)"
                        self?.showToast("OAuth 监听失败: \(error.localizedDescription)", type: .error)
                    }
                }
            }

            self.isOAuthWaiting = true
            self.oauthStatusText = "正在监听本地 1455 端口，已唤起系统默认浏览器..."

            var components = URLComponents(string: "https://auth.openai.com/oauth/authorize")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: AccountService.shared.clientId),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: AccountService.shared.redirectURI),
                URLQueryItem(name: "scope", value: "openid email profile offline_access"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "prompt", value: "login"),
                URLQueryItem(name: "id_token_add_organizations", value: "true"),
                URLQueryItem(name: "codex_cli_simplified_flow", value: "true")
            ]

            if let authURL = components.url {
                NSWorkspace.shared.open(authURL)
            }
        } catch {
            self.isOAuthWaiting = false
            self.oauthStatusText = "启动本地端口 1455 失败: \(error.localizedDescription)"
            self.showToast("无法启动本地回调服务: \(error.localizedDescription)", type: .error)
        }
    }

    private func handleOAuthCodeReceived(code: String, verifier: String) {
        self.oauthStatusText = "已截获授权 Code，正在向官方换取令牌..."
        self.isLoading = true
        self.loadingMessage = "正在兑换令牌并提取账号信息..."

        Task {
            do {
                let tokenJson = try await AccountService.shared.exchangeCodeForTokens(code: code, verifier: verifier)
                guard let idToken = tokenJson["id_token"] as? String,
                      let refreshToken = tokenJson["refresh_token"] as? String,
                      let accessToken = tokenJson["access_token"] as? String else {
                    throw NSError(domain: "CodexStudio", code: -8, userInfo: [NSLocalizedDescriptionKey: "返回凭证中缺失必要 Token"])
                }

                let claims = AccountService.shared.extractClaims(idToken: idToken)
                let resolvedEmail = claims.email ?? "user@openai.com"
                let resolvedAccountId = claims.accountId ?? ""
                let resolvedPlanStr = claims.plan ?? "plus"
                let plan = PlanType.from(string: resolvedPlanStr)

                var account = AccountItem(
                    email: resolvedEmail,
                    chatgptAccountId: resolvedAccountId,
                    plan: plan,
                    rawPlanString: resolvedPlanStr,
                    idToken: idToken,
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    isActive: false,
                    isEnabled: true,
                    filenameTag: "oauth-browser",
                    subscriptionUntil: claims.subscriptionUntil,
                    subscriptionStart: claims.subscriptionStart
                )

                if let (quota, _) = try? await AccountService.shared.fetchLiveQuota(account: account) {
                    account.liveQuota = quota
                }

                var (active, accounts) = try AccountService.shared.loadStore()
                accounts.removeAll { $0.email.lowercased() == account.email.lowercased() }
                accounts.append(account)
                try AccountService.shared.writeStore(active: active, accounts: accounts)

                self.refresh()
                self.isLoading = false
                self.isOAuthWaiting = false
                self.isAddModalPresented = false
                self.oauthStatusText = "就绪"
                self.showToast("浏览器授权成功！已添加账号: \(account.email)，正在同步实时用量...", type: .success)
                // 主动触发实时额度刷新
                self.refreshQuota(for: account)
            } catch {
                self.isLoading = false
                self.isOAuthWaiting = false
                self.oauthStatusText = "兑换令牌失败: \(error.localizedDescription)"
                self.showToast("授权兑换失败: \(error.localizedDescription)", type: .error)
            }
        }
    }

    func cancelBrowserOAuth() {
        AccountService.shared.stopOAuthServer()
        self.isOAuthWaiting = false
        self.oauthStatusText = "已取消授权监听"
    }

    // MARK: - Process Controls

    func quitChatGPT() {
        isLoading = true
        loadingMessage = "正在完全退出 ChatGPT 桌面端..."
        DispatchQueue.global().async {
            _ = AccountService.shared.quitChatGPT()
            DispatchQueue.main.async {
                self.isLoading = false
                self.checkRunningStatus()
                self.showToast("ChatGPT 桌面端及所有子进程已彻底关闭", type: .info)
            }
        }
    }

    func launchChatGPT() {
        isLoading = true
        loadingMessage = "正在启动 ChatGPT 桌面端..."
        DispatchQueue.global().async {
            _ = AccountService.shared.launchChatGPT()
            DispatchQueue.main.async {
                self.isLoading = false
                self.checkRunningStatus()
                self.showToast("ChatGPT 桌面端已启动", type: .info)
            }
        }
    }
}
