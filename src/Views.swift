import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Hover Tracker & Interactive Button Component

final class HoverTracker: ObservableObject {
    @Published var isHovered = false
}

struct HoverActionButton<Content: View>: View {
    let action: () -> Void
    var defaultBg: Color = Color(NSColor.controlBackgroundColor)
    var hoverBg: Color = Color.blue.opacity(0.15)
    var defaultBorder: Color = Color.gray.opacity(0.25)
    var hoverBorder: Color = Color.blue.opacity(0.5)
    var defaultFg: Color = .primary
    var hoverFg: Color = .blue
    var cornerRadius: CGFloat = 7
    var isEnabled: Bool = true
    @ViewBuilder let content: () -> Content

    @StateObject private var tracker = HoverTracker()

    var body: some View {
        Button(action: action) {
            content()
                .foregroundColor(isEnabled ? (tracker.isHovered ? hoverFg : defaultFg) : Color.secondary.opacity(0.45))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isEnabled ? (tracker.isHovered ? hoverBg : defaultBg) : Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isEnabled ? (tracker.isHovered ? hoverBorder : defaultBorder) : Color.clear, lineWidth: 1)
                )
                .scaleEffect(isEnabled && tracker.isHovered ? 1.02 : 1.0)
                .shadow(color: isEnabled && tracker.isHovered ? Color.black.opacity(0.10) : Color.clear, radius: 3, y: 1)
                .animation(.easeInOut(duration: 0.12), value: tracker.isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { h in
            if isEnabled {
                tracker.isHovered = h
                if h {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}

// MARK: - Custom Progress Bar (Displays Remaining Quota 剩余量)

struct ModernProgressBar: View {
    let value: Double // 0.0 to 1.0 (Remaining fraction)
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.separatorColor).opacity(0.35))
                    .frame(height: 7)

                RoundedRectangle(cornerRadius: 4)
                    .fill(tint)
                    .frame(width: max(0, min(geo.size.width * CGFloat(value), geo.size.width)), height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
            }
        }
        .frame(height: 7)
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Logo & Branding
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.10, green: 0.70, blue: 0.95), Color(red: 0.55, green: 0.30, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 38, height: 38)
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)

                    Image(systemName: "cpu.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Studio")
                        .font(.system(size: 16, weight: .bold))
                    Text("ChatGPT 账号管理")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 22)

            // Navigation Items
            VStack(spacing: 4) {
                ForEach(NavTab.allCases) { tab in
                    SidebarTabButton(
                        tab: tab,
                        isSelected: state.selectedTab == tab,
                        badgeCount: tab == .accounts ? state.accounts.count : nil
                    ) {
                        state.selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Bottom Host Status Card (Live ChatGPT Indicator)
            VStack(alignment: .leading, spacing: 10) {
                if state.isChatGPTInstalled {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(state.isChatGPTRunning ? Color.green : Color.gray.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .shadow(color: state.isChatGPTRunning ? Color.green.opacity(0.6) : Color.clear, radius: 4)

                        Text(state.isChatGPTRunning ? "ChatGPT 运行中" : "ChatGPT 已完全退出")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(state.isChatGPTRunning ? .primary : .secondary)

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        HoverActionButton(
                            action: { state.launchChatGPT() },
                            defaultBg: Color.blue.opacity(0.12),
                            hoverBg: Color.blue,
                            defaultBorder: Color.blue.opacity(0.3),
                            hoverBorder: Color.blue,
                            defaultFg: .blue,
                            hoverFg: .white,
                            cornerRadius: 6
                        ) {
                            Text("启动")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }

                        HoverActionButton(
                            action: { state.quitChatGPT() },
                            defaultBg: state.isChatGPTRunning ? Color.red.opacity(0.12) : Color.gray.opacity(0.10),
                            hoverBg: Color.red,
                            defaultBorder: state.isChatGPTRunning ? Color.red.opacity(0.3) : Color.clear,
                            hoverBorder: Color.red,
                            defaultFg: state.isChatGPTRunning ? .red : .secondary,
                            hoverFg: .white,
                            cornerRadius: 6,
                            isEnabled: state.isChatGPTRunning
                        ) {
                            Text("完全退出")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("ChatGPT 未安装")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Text("切号凭证依然生效，可用于 Codex CLI 终端与开发工具。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.8)))
            .padding(14)
        }
        .frame(width: 215)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SidebarTabButton: View {
    let tab: NavTab
    let isSelected: Bool
    let badgeCount: Int?
    let action: () -> Void

    @StateObject private var tracker = HoverTracker()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 15))
                    .frame(width: 22)

                Text(tab.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))

                Spacer()

                if let count = badgeCount {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.12) : (tracker.isHovered ? Color.gray.opacity(0.08) : Color.clear))
            )
            .foregroundColor(isSelected ? .blue : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            tracker.isHovered = h
            if h {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Accounts View

struct AccountsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            HStack(spacing: 12) {
                // Search Box
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    TextField("搜索邮箱、套餐、标签...", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !state.searchQuery.isEmpty {
                        Button(action: { state.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                .frame(maxWidth: 320)

                Spacer()

                // Auto Refresh Timer Pill
                if state.isAutoRefreshEnabled {
                    let mins = state.secondsUntilNextRefresh / 60
                    let secs = state.secondsUntilNextRefresh % 60
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(String(format: "%02d:%02d 自动刷新", mins, secs))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help("已开启定时自动刷新，每 \(state.autoRefreshInterval / 60) 分钟自动同步官方额度")
                }

                // Refresh All Quotas Button with hover
                HoverActionButton(
                    action: { state.refreshAllQuotas() },
                    defaultBg: Color(NSColor.controlBackgroundColor),
                    hoverBg: Color.blue.opacity(0.12),
                    defaultBorder: Color.gray.opacity(0.25),
                    hoverBorder: Color.blue.opacity(0.4),
                    defaultFg: .primary,
                    hoverFg: .blue,
                    cornerRadius: 8
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                        Text("全部刷新")
                            .font(.system(size: 13, weight: .medium))
                    }
                }

                // Add Account Button with hover
                HoverActionButton(
                    action: { state.isAddModalPresented = true },
                    defaultBg: Color.blue,
                    hoverBg: Color(red: 0.15, green: 0.50, blue: 0.95),
                    defaultBorder: Color.blue,
                    hoverBorder: Color.blue.opacity(0.8),
                    defaultFg: .white,
                    hoverFg: .white,
                    cornerRadius: 8
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("添加账号")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Scrollable Content
            ScrollView {
                VStack(spacing: 16) {
                    if state.filteredAccounts.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "tray")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(state.searchQuery.isEmpty ? "暂无已保存账号，点击右上角「+ 添加账号」或直接拖拽 JSON 到窗口即可导入" : "未找到匹配的账号")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(state.filteredAccounts) { account in
                                AccountCardView(account: account, state: state)
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .onDrop(of: ["public.file-url"], isTargeted: $state.isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $state.isAddModalPresented) {
            AddAccountSheetView(state: state)
        }
        .alert("确认重置 5 小时限额？", isPresented: Binding(
            get: { state.resetCreditTarget != nil },
            set: { if !$0 { state.resetCreditTarget = nil } }
        )) {
            Button("立即重置", role: .none) {
                state.confirmResetCredit()
            }
            Button("取消", role: .cancel) {
                state.resetCreditTarget = nil
            }
        } message: {
            if let target = state.resetCreditTarget {
                Text("将消耗 \(target.email) 的 1 次主动重置次数，立即清空 5 小时限额并将可用额度回满至 100%。确认继续吗？")
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    state.importFromFile(url: url)
                }
            }
        }
        return true
    }
}

// MARK: - Account Card View (Refined Layout with Hover Effects and Remaining Quota)

struct AccountCardView: View {
    let account: AccountItem
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row 1: Header (Checkbox/Status Icon, Brand Pill, Email, Tag, Short Account ID)
            HStack(spacing: 10) {
                // Checkbox / Active indicator
                if account.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 15, height: 15)
                }

                // [Codex] Brand Pill
                Text("Codex")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.10, green: 0.65, blue: 0.50).opacity(0.18))
                    .foregroundColor(Color(red: 0.10, green: 0.75, blue: 0.55))
                    .clipShape(Capsule())

                // Email
                Text(account.email)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)

                // Filename Tag
                if let tag = account.filenameTag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.14))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .lineLimit(1)
                }

                Spacer()

                // Top-Right Status Badge (Moved from Bottom-Left)
                if account.isActive {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                        Text("当前生效主账号")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1))
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                        Text("待命状态")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Row 2: Badges Bar (Plan, Context-aware Subscription/Authorization, Team Org, Credit, Reset Credits)
            let quota = account.liveQuota ?? LiveQuota()
            let subBadge = account.subscriptionBadge
            HStack(spacing: 8) {
                // Plan Badge
                Text("套餐 \(account.plan.displayName)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(account.plan.badgeBackground)
                    .foregroundColor(account.plan.badgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Organization Title Badge (for Team accounts or org workspaces)
                if let orgTitle = account.organizationTitle, !orgTitle.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 10))
                        Text(orgTitle)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .foregroundColor(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Official Subscription / Authorization Badge (Context-aware for Plus / K12 / Free / Team)
                HStack(spacing: 4) {
                    Image(systemName: subBadge.icon)
                        .font(.system(size: 10))
                    Text(subBadge.text)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(subBadge.color.opacity(subBadge.bgOpacity))
                .foregroundColor(subBadge.color)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Credit Balance Badge
                HStack(spacing: 4) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 10))
                    Text("Credit 余额 \(Int(quota.creditBalance))")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.12))
                .foregroundColor(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Reset Credits Badge (Shown if available)
                if quota.resetCreditsCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("主动重置次数 \(quota.resetCreditsCount)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Spacer()
            }

            // Row 3: Progress Bars Section (Displays REMAINING Quota 剩余量)
            VStack(spacing: 12) {
                if let quota = account.liveQuota {
                    // 5 Hour Limit Row (Remaining Quota)
                    VStack(spacing: 5) {
                        HStack {
                            Text("5 小时限额")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            Spacer()

                            let rem5h = quota.sessionRemainingPercent
                            Text("剩余 \(rem5h)%  \(quota.sessionResetText)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(remainingProgressColor(for: rem5h))
                        }

                        ModernProgressBar(
                            value: Double(quota.sessionRemainingPercent) / 100.0,
                            tint: remainingProgressColor(for: quota.sessionRemainingPercent)
                        )
                    }

                    // Weekly Limit Row + Reset Button (Remaining Quota)
                    VStack(spacing: 5) {
                        HStack(alignment: .center) {
                            Text("周限额")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            Spacer()

                            let remWeek = quota.weeklyRemainingPercent
                            Text("剩余 \(remWeek)%  \(quota.weeklyResetText)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(remainingProgressColor(for: remWeek))

                            // Reset Quota Button with hover effect
                            HoverActionButton(
                                action: { state.promptResetCredit(for: account) },
                                defaultBg: quota.resetCreditsCount > 0 ? Color.orange.opacity(0.16) : Color.gray.opacity(0.10),
                                hoverBg: Color.orange,
                                defaultBorder: quota.resetCreditsCount > 0 ? Color.orange.opacity(0.4) : Color.clear,
                                hoverBorder: Color.orange,
                                defaultFg: quota.resetCreditsCount > 0 ? .orange : Color.secondary.opacity(0.5),
                                hoverFg: .white,
                                cornerRadius: 6,
                                isEnabled: quota.resetCreditsCount > 0
                            ) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10))
                                    Text("重置额度")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.vertical, -1)
                            }
                            .help(quota.resetCreditsCount > 0 ? "消耗 1 次主动重置次数，立即清空 5 小时限额回满至 100%" : "没有可用的主动重置次数")
                        }

                        ModernProgressBar(
                            value: Double(quota.weeklyRemainingPercent) / 100.0,
                            tint: remainingProgressColor(for: quota.weeklyRemainingPercent)
                        )
                    }
                } else if account.isRefreshingQuota {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("正在查询 OpenAI 官方实时额度与重置信息...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        Text("尚未同步官方实时用量，点击右侧按钮即可获取")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        HoverActionButton(
                            action: { state.refreshQuota(for: account) },
                            defaultBg: Color.blue.opacity(0.12),
                            hoverBg: Color.blue,
                            defaultBorder: Color.blue.opacity(0.4),
                            hoverBorder: Color.blue,
                            defaultFg: .blue,
                            hoverFg: .white,
                            cornerRadius: 6
                        ) {
                            Text("立即同步额度")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor).opacity(0.6)))

            Divider()

            // Row 4: Bottom Action Bar (Quota Alerts on Left, Action Buttons Aligned to Right)
            HStack(spacing: 10) {
                // Left Side: 5h 额度已满 或 异常警告提示
                if quota.limitReached {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text("5h 额度已满")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let err = quota.errorMessage, !err.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                        Text(err)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Spacer pushes all action buttons to the RIGHT!
                Spacer()

                // Right Side: Action Buttons
                if !account.isActive {
                    HoverActionButton(
                        action: { state.promptSwitch(to: account) },
                        defaultBg: Color.blue.opacity(0.12),
                        hoverBg: Color.blue,
                        defaultBorder: Color.blue.opacity(0.4),
                        hoverBorder: Color.blue,
                        defaultFg: .blue,
                        hoverFg: .white,
                        cornerRadius: 7
                    ) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .bold))
                            Text("切换到此号")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }

                // Refresh Quota Button
                HoverActionButton(
                    action: { state.refreshQuota(for: account) },
                    defaultBg: Color.gray.opacity(0.10),
                    hoverBg: Color.blue.opacity(0.12),
                    defaultBorder: Color.gray.opacity(0.25),
                    hoverBorder: Color.blue.opacity(0.4),
                    defaultFg: .primary,
                    hoverFg: .blue,
                    cornerRadius: 7
                ) {
                    HStack(spacing: 5) {
                        if account.isRefreshingQuota {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        Text("刷新用量")
                            .font(.system(size: 12))
                    }
                }

                // Export JSON Button
                HoverActionButton(
                    action: { state.exportAccount(account: account) },
                    defaultBg: Color.gray.opacity(0.10),
                    hoverBg: Color.blue.opacity(0.12),
                    defaultBorder: Color.gray.opacity(0.25),
                    hoverBorder: Color.blue.opacity(0.4),
                    defaultFg: .primary,
                    hoverFg: .blue,
                    cornerRadius: 7
                ) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("导出 JSON")
                            .font(.system(size: 12))
                    }
                }

                // Delete Button
                HoverActionButton(
                    action: { state.promptDelete(account: account) },
                    defaultBg: Color.red.opacity(0.08),
                    hoverBg: Color.red,
                    defaultBorder: Color.red.opacity(0.25),
                    hoverBorder: Color.red,
                    defaultFg: .red,
                    hoverFg: .white,
                    cornerRadius: 7
                ) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("删除")
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(account.isActive ? Color.green.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: account.isActive ? 1.5 : 1)
        )
        .shadow(color: account.isActive ? Color.green.opacity(0.1) : Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    /// Colors for Remaining Quota: Green when ample (>=50%), Orange when moderate (>=20%), Red when low (<20%)
    private func remainingProgressColor(for remainingPercent: Int) -> Color {
        if remainingPercent >= 50 {
            return Color.green
        } else if remainingPercent >= 20 {
            return Color.orange
        } else {
            return Color.red
        }
    }
}

// MARK: - Add Account Sheet View (3 Methods with Hover Buttons)

struct AddAccountSheetView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.blue, Color(red: 0.35, green: 0.35, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 38, height: 38)
                        .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)

                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("添加 ChatGPT / Codex 账号")
                        .font(.system(size: 16, weight: .bold))

                    Text("支持官方免密授权、凭证文件拖拽导入与手动填入 Token")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Circular Close Button with hover
                HoverActionButton(
                    action: {
                        if state.isOAuthWaiting {
                            state.cancelBrowserOAuth()
                        }
                        state.isAddModalPresented = false
                    },
                    defaultBg: Color.gray.opacity(0.12),
                    hoverBg: Color.gray.opacity(0.25),
                    defaultBorder: Color.clear,
                    hoverBorder: Color.clear,
                    defaultFg: .secondary,
                    hoverFg: .primary,
                    cornerRadius: 14
                ) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Custom Segmented Pill Switcher
            HStack(spacing: 6) {
                ForEach(AddAccountTab.allCases) { tab in
                    let isSelected = state.addModalTab == tab
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.addModalTab = tab
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 12))

                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

                            if let badge = tab.badgeText {
                                Text(badge)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(isSelected ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                                    .foregroundColor(isSelected ? .blue : .green)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                .shadow(color: isSelected ? Color.black.opacity(0.08) : Color.clear, radius: 2, y: 1)
                        )
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Content Container
            VStack {
                switch state.addModalTab {
                case .browser:
                    browserOAuthTab
                case .file:
                    fileImportTab
                case .manual:
                    manualTokenTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 650, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // Tab 1: Browser OAuth
    private var browserOAuthTab: some View {
        VStack(spacing: 16) {
            // Steps Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 13))
                    Text("官方 OAuth PKCE 安全免密授权流程")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }

                HStack(alignment: .top, spacing: 12) {
                    stepBubble(index: "1", title: "点击打开官网", desc: "在默认浏览器打开 OpenAI 官方登录与授权认证页")
                    stepBubble(index: "2", title: "登录账号授权", desc: "输入账号或第三方登录，确认授权访问")
                    stepBubble(index: "3", title: "本地自动握手", desc: "安全接收凭证并自动查询套餐与额度")
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15), lineWidth: 1))

            // State & Interactive Card
            VStack(spacing: 14) {
                if state.isOAuthWaiting {
                    // Waiting Animation
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("正在等待浏览器登录完成...")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.blue)
                            Text("本地监听已启动 (http://localhost:1455/auth/callback)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.25), lineWidth: 1))

                    Text("请在已打开的网页中完成登录。完成后客户端将自动接收凭证，本弹窗会自动关闭并展示最新用量。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    HStack(spacing: 12) {
                        HoverActionButton(
                            action: { state.startBrowserOAuth() },
                            defaultBg: Color.gray.opacity(0.12),
                            hoverBg: Color.blue.opacity(0.12),
                            defaultBorder: Color.gray.opacity(0.2),
                            hoverBorder: Color.blue.opacity(0.4),
                            defaultFg: .primary,
                            hoverFg: .blue,
                            cornerRadius: 8
                        ) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                Text("重新在浏览器打开")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                        }

                        Spacer()

                        HoverActionButton(
                            action: { state.cancelBrowserOAuth() },
                            defaultBg: Color.red.opacity(0.10),
                            hoverBg: Color.red,
                            defaultBorder: Color.red.opacity(0.25),
                            hoverBorder: Color.red,
                            defaultFg: .red,
                            hoverFg: .white,
                            cornerRadius: 8
                        ) {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark")
                                Text("取消授权监听")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                } else {
                    // Ready to start
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("服务就绪 · 本地原生通信，凭证全程不离开您的电脑")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))

                        Spacer()

                        HoverActionButton(
                            action: { state.startBrowserOAuth() },
                            defaultBg: Color.blue,
                            hoverBg: Color(red: 0.15, green: 0.50, blue: 0.95),
                            defaultBorder: Color.blue,
                            hoverBorder: Color.blue,
                            defaultFg: .white,
                            hoverFg: .white,
                            cornerRadius: 9
                        ) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 13, weight: .bold))
                                Text("在系统浏览器中打开 OpenAI 官方登录")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func stepBubble(index: String, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(index)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.blue)
                    .clipShape(Circle())
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Tab 2: File Import
    private var fileImportTab: some View {
        VStack(spacing: 14) {
            // Drag and Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        state.isDropTargeted ? Color.blue : Color.gray.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(state.isDropTargeted ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.5))
                    )

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: state.isDropTargeted ? "arrow.down.circle.fill" : "doc.badge.plus")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)
                    }

                    Text("拖拽 .json 凭证文件至此处")
                        .font(.system(size: 14, weight: .bold))

                    Text("或点击下方按钮直接从本地选取凭证文件")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    HoverActionButton(
                        action: { selectAndImportFile() },
                        defaultBg: Color.blue.opacity(0.12),
                        hoverBg: Color.blue,
                        defaultBorder: Color.blue.opacity(0.3),
                        hoverBorder: Color.blue,
                        defaultFg: .blue,
                        hoverFg: .white,
                        cornerRadius: 7
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("选择本地 JSON 文件...")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 1)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .frame(maxHeight: 200)
            .onDrop(of: [UTType.fileURL], isTargeted: $state.isDropTargeted) { providers in
                guard let provider = providers.first else { return false }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        var targetURL: URL? = nil
                        if let url = item as? URL {
                            targetURL = url
                        } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            targetURL = url
                        } else if let str = item as? String, let url = URL(string: str) {
                            targetURL = url
                        }
                        if let targetURL = targetURL {
                            DispatchQueue.main.async {
                                state.importFromFile(url: targetURL)
                            }
                        }
                    }
                }
                return true
            }

            // Supported formats card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("支持的凭证文件格式")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("自动识别并验证")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    formatPill(name: "CLIProxyAPI / Quotio", sub: "codex-*.json")
                    formatPill(name: "官方标准凭证", sub: "auth.json")
                    formatPill(name: "完整账号存储库", sub: "accounts.json")
                }

                Text("提示：导入后将自动向 OpenAI 官方同步当前套餐、5小时用量及周限额信息。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15), lineWidth: 1))

            Spacer()
        }
    }

    private func formatPill(name: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
            Text(sub)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.12), lineWidth: 1))
    }

    private func selectAndImportFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "导入"
        panel.message = "选择 Codex 凭证 JSON 文件"

        if panel.runModal() == .OK, let url = panel.url {
            state.importFromFile(url: url)
        }
    }

    // Tab 3: Manual Token
    private var manualTokenTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Field 1: Refresh Token
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Refresh Token")
                        .font(.system(size: 12, weight: .bold))
                    Text("必填")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    Spacer()
                }

                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("粘贴以 rft_ 开头或官方生成的 Refresh Token...", text: $state.manualRefreshToken)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                    if !state.manualRefreshToken.isEmpty {
                        Button(action: { state.manualRefreshToken = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }

            // Field 2: Access Token
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Access Token")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("选填")
                        .font(.system(size: 10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.12))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                    Spacer()
                    Text("留空将自动从官方换取")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("可选粘贴已有 Access Token...", text: $state.manualAccessToken)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                    if !state.manualAccessToken.isEmpty {
                        Button(action: { state.manualAccessToken = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }

            // Field 3: Account ID
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Account ID")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("选填")
                        .font(.system(size: 10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.12))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                    Spacer()
                    Text("留空将自动从 Token Claims 解析")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("可选填入 ChatGPT Account ID...", text: $state.manualAccountId)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                    if !state.manualAccountId.isEmpty {
                        Button(action: { state.manualAccountId = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }

            Spacer()

            // Bottom Action Bar
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text("凭证仅加密存储于本地 ~/.local/share/codex-account")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)

                Spacer()

                let isReady = !state.manualRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HoverActionButton(
                    action: { state.submitManualToken() },
                    defaultBg: isReady ? Color.blue : Color.gray.opacity(0.15),
                    hoverBg: isReady ? Color(red: 0.15, green: 0.50, blue: 0.95) : Color.gray.opacity(0.15),
                    defaultBorder: isReady ? Color.blue : Color.clear,
                    hoverBorder: isReady ? Color.blue : Color.clear,
                    defaultFg: isReady ? .white : Color.secondary.opacity(0.6),
                    hoverFg: isReady ? .white : Color.secondary.opacity(0.6),
                    cornerRadius: 8,
                    isEnabled: isReady
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("验证并添加账号")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

// MARK: - Overview View

struct OverviewView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("总览看板")
                    .font(.system(size: 20, weight: .bold))

                // Stats Grid
                HStack(spacing: 16) {
                    StatCard(
                        title: "已保存账号数",
                        value: "\(state.accounts.count)",
                        icon: "person.2.fill",
                        color: .blue
                    )

                    StatCard(
                        title: "当前生效账号",
                        value: state.activeAccount?.email ?? "未设置",
                        icon: "checkmark.seal.fill",
                        color: .green
                    )

                    StatCard(
                        title: "ChatGPT 状态",
                        value: state.isChatGPTRunning ? "运行中" : "已退出",
                        icon: "power",
                        color: state.isChatGPTRunning ? .green : .gray
                    )
                }

                // Active Account Spotlight
                if let active = state.activeAccount {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("当前主账号详情")
                            .font(.system(size: 15, weight: .bold))

                        AccountCardView(account: active, state: state)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }

            Text(value)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("应用设置")
                    .font(.system(size: 20, weight: .bold))

                // Section 1: Quota Periodic Auto Refresh
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "timer")
                            .font(.system(size: 15))
                            .foregroundColor(.blue)
                        Text("额度定时自动刷新")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }

                    Toggle("开启后台定时自动更新额度", isOn: $state.isAutoRefreshEnabled)
                        .toggleStyle(.switch)
                        .font(.system(size: 13))

                    if state.isAutoRefreshEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("刷新时间间隔")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                ForEach([
                                    (120, "2 分钟"),
                                    (300, "5 分钟 (推荐)"),
                                    (600, "10 分钟"),
                                    (900, "15 分钟"),
                                    (1800, "30 分钟")
                                ], id: \.0) { sec, label in
                                    let isSelected = state.autoRefreshInterval == sec
                                    HoverActionButton(
                                        action: { state.autoRefreshInterval = sec },
                                        defaultBg: isSelected ? Color.blue.opacity(0.15) : Color.gray.opacity(0.10),
                                        hoverBg: isSelected ? Color.blue.opacity(0.25) : Color.blue.opacity(0.10),
                                        defaultBorder: isSelected ? Color.blue.opacity(0.6) : Color.gray.opacity(0.2),
                                        hoverBorder: Color.blue.opacity(0.5),
                                        defaultFg: isSelected ? .blue : .primary,
                                        hoverFg: .blue,
                                        cornerRadius: 7
                                    ) {
                                        Text(label)
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                let mins = state.secondsUntilNextRefresh / 60
                                let secs = state.secondsUntilNextRefresh % 60
                                Text("距离下次自动刷新: \(String(format: "%02d:%02d", mins, secs))")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)

                                if let last = state.lastRefreshedAt {
                                    let df: DateFormatter = {
                                        let f = DateFormatter()
                                        f.dateFormat = "HH:mm:ss"
                                        return f
                                    }()
                                    Text("·  上次刷新时间: \(df.string(from: last))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.leading, 4)
                    }

                    Text("提示：开启后，应用将在后台按设定周期自动向 OpenAI 查询所有账号的 5 小时限额、周限额及重置倒计时。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.18), lineWidth: 1))

                // Section 2: ChatGPT Desktop App Integration
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 15))
                            .foregroundColor(.blue)
                        Text("ChatGPT 客户端集成")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()

                        if state.isChatGPTInstalled {
                            HStack(spacing: 5) {
                                Circle().fill(state.isChatGPTRunning ? Color.green : Color.gray).frame(width: 7, height: 7)
                                Text(state.isChatGPTRunning ? "运行中" : "已就绪")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(state.isChatGPTRunning ? .green : .secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.gray.opacity(0.10))
                            .clipShape(Capsule())
                        } else {
                            Text("未安装客户端")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.gray.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }

                    Toggle("切换账号时自动重启 ChatGPT 桌面端", isOn: $state.autoRestartOnSwitch)
                        .toggleStyle(.switch)
                        .font(.system(size: 13))

                    if !state.isChatGPTInstalled {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text("当前系统未检测到官方 /Applications/ChatGPT.app。切号凭证仍会写入 ~/.codex/auth.json，方便配合终端 CLI 使用。")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.18), lineWidth: 1))

                // Section 3: Storage Paths
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "folder")
                            .font(.system(size: 15))
                            .foregroundColor(.blue)
                        Text("本地存储与凭证文件")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("多账号存储库 (accounts.json)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("~/.local/share/codex-account/accounts.json")
                            .font(.system(size: 12, design: .monospaced))

                        Text("当前生效凭证 (auth.json)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        Text("~/.codex/auth.json")
                            .font(.system(size: 12, design: .monospaced))

                        HoverActionButton(
                            action: {
                                let path = NSString(string: "~/.local/share/codex-account").expandingTildeInPath
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                            },
                            defaultBg: Color.gray.opacity(0.12),
                            hoverBg: Color.blue.opacity(0.12),
                            defaultBorder: Color.gray.opacity(0.2),
                            hoverBorder: Color.blue.opacity(0.4),
                            defaultFg: .primary,
                            hoverFg: .blue,
                            cornerRadius: 6
                        ) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11))
                                Text("在访达中显示账号目录")
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.18), lineWidth: 1))

                // Section 4: About & Universal Architecture
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "applelogo")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                        Text("关于 Codex Studio")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("版本 1.0.0")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Text("专为 macOS 打造的 ChatGPT / Codex 原生账号与额度管理工具。采用 Universal 2 架构（同时原生支持 Apple Silicon M系列 与 Intel 芯片），纯原生 Swift 编译，零外部依赖，极速省电。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.18), lineWidth: 1))
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Toast Overlay

struct ToastOverlay: View {
    let toast: ToastInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.type.iconName)
                .foregroundColor(toast.type.color)
                .font(.system(size: 15))

            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(white: 0.15).opacity(0.95))
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .padding(.top, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Switch Sheet View

struct SwitchSheetView: View {
    let target: AccountItem
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 46))
                .foregroundColor(.blue)

            VStack(spacing: 6) {
                Text("切换到账号")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(target.email)
                    .font(.system(size: 17, weight: .bold))
                Text("套餐: \(target.plan.displayName)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(target.plan.badgeColor)
            }

            if state.isChatGPTRunning {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text("ChatGPT 正在运行，切换时将自动彻底退出并重新拉起生效。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }

            HStack(spacing: 12) {
                HoverActionButton(
                    action: { state.switchTarget = nil },
                    defaultBg: Color.gray.opacity(0.15),
                    hoverBg: Color.gray.opacity(0.25),
                    defaultBorder: Color.gray.opacity(0.2),
                    hoverBorder: Color.gray.opacity(0.4),
                    defaultFg: .primary,
                    hoverFg: .primary,
                    cornerRadius: 6
                ) {
                    Text("取消")
                        .padding(.horizontal, 10)
                }

                HoverActionButton(
                    action: { state.confirmSwitch(to: target) },
                    defaultBg: Color.blue,
                    hoverBg: Color(red: 0.15, green: 0.50, blue: 0.95),
                    defaultBorder: Color.blue,
                    hoverBorder: Color.blue,
                    defaultFg: .white,
                    hoverFg: .white,
                    cornerRadius: 6
                ) {
                    Text("立即切换")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
