import Foundation
import SwiftUI

enum NavTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case accounts = "账号"
    case settings = "设置"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .accounts: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

enum PlanType: String, Codable {
    case plus = "plus"
    case k12 = "k12"
    case free = "free"
    case pro = "pro"
    case team = "team"
    case business = "business"
    case unknown = "unknown"

    static func from(string: String) -> PlanType {
        let lower = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("plus") { return .plus }
        if lower.contains("k12") { return .k12 }
        if lower.contains("free") { return .free }
        if lower.contains("pro") { return .pro }
        if lower.contains("team") { return .team }
        if lower.contains("business") { return .business }
        return .unknown
    }

    var displayName: String {
        switch self {
        case .plus: return "Plus"
        case .k12: return "K12 (教育)"
        case .free: return "Free"
        case .pro: return "Pro"
        case .team: return "Team (团队)"
        case .business: return "Business"
        case .unknown: return "Standard"
        }
    }

    var badgeColor: Color {
        switch self {
        case .plus: return Color(red: 0.65, green: 0.40, blue: 0.95) // Purple
        case .k12: return Color(red: 0.15, green: 0.60, blue: 0.95) // Vibrant Blue
        case .pro: return Color(red: 0.15, green: 0.75, blue: 0.55) // Emerald
        case .team: return Color(red: 0.95, green: 0.55, blue: 0.20) // Orange
        case .business: return Color(red: 0.90, green: 0.45, blue: 0.25)
        case .free: return Color(white: 0.55)
        case .unknown: return Color(white: 0.50)
        }
    }

    var badgeBackground: Color {
        badgeColor.opacity(0.14)
    }
}

struct LiveQuota: Hashable, Codable {
    var sessionUsedPercent: Int = 0          // 5小时已用百分比 (0-100)
    var sessionResetAfterSeconds: Int? = nil  // 5小时剩余重置秒数
    var sessionResetAt: Int64? = nil          // 5小时重置时间戳
    var weeklyUsedPercent: Int = 0           // 周限额已用百分比 (0-100)
    var weeklyResetAfterSeconds: Int? = nil   // 周限额剩余重置秒数
    var weeklyResetAt: Int64? = nil           // 周限额重置时间戳
    var allowed: Bool = true
    var limitReached: Bool = false
    var resetCreditsCount: Int = 0           // 主动重置可用次数
    var creditBalance: Double = 0.0          // Credit 余额
    var planType: String = ""
    var lastUpdated: Date = Date()
    var errorMessage: String? = nil
    var sessionRemainingPercent: Int {
        max(0, min(100, 100 - sessionUsedPercent))
    }

    var weeklyRemainingPercent: Int {
        max(0, min(100, 100 - weeklyUsedPercent))
    }

    var sessionResetText: String {
        formatResetCountdown(resetAt: sessionResetAt, afterSeconds: sessionResetAfterSeconds)
    }

    var weeklyResetText: String {
        formatResetCountdown(resetAt: weeklyResetAt, afterSeconds: weeklyResetAfterSeconds)
    }

    private func formatResetCountdown(resetAt: Int64?, afterSeconds: Int?) -> String {
        guard let resetAt = resetAt, resetAt > 0 else {
            if let sec = afterSeconds, sec > 0 {
                return formatSeconds(sec)
            }
            return "就绪"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        let dateStr = df.string(from: date)

        let diff = Int(date.timeIntervalSince(Date()))
        let countdownStr = formatSeconds(diff)
        return "\(dateStr) · \(countdownStr)"
    }

    private func formatSeconds(_ sec: Int) -> String {
        if sec <= 0 { return "即将重置" }
        if sec < 60 { return "1分钟后重置" }
        if sec < 3600 {
            let m = max(1, sec / 60)
            return "\(m)分钟后重置"
        }
        if sec < 86400 {
            let h = max(1, sec / 3600)
            return "\(h)小时后重置"
        }
        let d = max(1, sec / 86400)
        return "\(d)天后重置"
    }
}

struct SubscriptionBadgeInfo: Hashable {
    let icon: String
    let text: String
    let color: Color
    let bgOpacity: Double
}

struct AccountItem: Identifiable, Hashable {
    let id = UUID()
    var email: String
    var chatgptAccountId: String
    var plan: PlanType
    var rawPlanString: String
    var idToken: String
    var accessToken: String?
    var refreshToken: String
    var isActive: Bool
    var isEnabled: Bool = true
    var filenameTag: String? = nil
    var organizationTitle: String? = nil

    // Subscriptions & quota info
    var subscriptionUntil: String?
    var subscriptionStart: String?
    var expiredDateStr: String?

    // Live quota from official API
    var liveQuota: LiveQuota?
    var isRefreshingQuota: Bool = false
    var isResettingQuota: Bool = false

    var shortAccountId: String {
        if chatgptAccountId.count > 12 {
            let start = chatgptAccountId.prefix(6)
            let end = chatgptAccountId.suffix(6)
            return "\(start)...\(end)"
        }
        return chatgptAccountId
    }

    /// Official ChatGPT Subscription / Authorization Badge Info
    /// Context-aware across Plus, Pro, Team, K12, and Free plans
    var subscriptionBadge: SubscriptionBadgeInfo {
        let renewDate = parseRenewalDate(subscriptionUntil)

        switch plan {
        case .k12:
            // K12 is an educational organizational plan (no individual Stripe renewal)
            return SubscriptionBadgeInfo(
                icon: "graduationcap.fill",
                text: "教育授权 · 长期有效",
                color: Color(red: 0.15, green: 0.60, blue: 0.95),
                bgOpacity: 0.12
            )

        case .free:
            // If it had a Plus/Pro subscription date that expired in the past:
            if let d = renewDate, d < Date() {
                let df = DateFormatter()
                df.dateFormat = "MM/dd"
                let dateStr = df.string(from: d)
                return SubscriptionBadgeInfo(
                    icon: "exclamationmark.clock.fill",
                    text: "\(dateStr) 订阅已到期 (已转免费)",
                    color: Color.orange,
                    bgOpacity: 0.14
                )
            }
            return SubscriptionBadgeInfo(
                icon: "arrow.triangle.2.circlepath",
                text: "免费计划 · 滚动重置",
                color: Color.secondary,
                bgOpacity: 0.12
            )

        case .team, .business:
            if let d = renewDate {
                let diff = Int(d.timeIntervalSince(Date()))
                let df = DateFormatter()
                df.dateFormat = "MM/dd HH:mm"
                let dateStr = df.string(from: d)
                if diff <= 0 {
                    return SubscriptionBadgeInfo(
                        icon: "exclamationmark.triangle.fill",
                        text: "团队订阅已到期 (\(dateStr))",
                        color: Color.red,
                        bgOpacity: 0.14
                    )
                } else {
                    let days = max(1, Int(ceil(Double(diff) / 86400.0)))
                    return SubscriptionBadgeInfo(
                        icon: "calendar.badge.clock",
                        text: "团队续期 \(dateStr) · \(days)天后",
                        color: Color(red: 0.95, green: 0.55, blue: 0.20),
                        bgOpacity: 0.14
                    )
                }
            } else {
                return SubscriptionBadgeInfo(
                    icon: "person.3.fill",
                    text: "团队授权 · 有效",
                    color: Color(red: 0.95, green: 0.55, blue: 0.20),
                    bgOpacity: 0.14
                )
            }

        case .plus, .pro:
            if let d = renewDate {
                let diff = Int(d.timeIntervalSince(Date()))
                let df = DateFormatter()
                df.dateFormat = "MM/dd HH:mm"
                let dateStr = df.string(from: d)
                if diff <= 0 {
                    return SubscriptionBadgeInfo(
                        icon: "exclamationmark.triangle.fill",
                        text: "订阅已到期 (\(dateStr))",
                        color: Color.red,
                        bgOpacity: 0.14
                    )
                } else {
                    let days = max(1, Int(ceil(Double(diff) / 86400.0)))
                    return SubscriptionBadgeInfo(
                        icon: "calendar.badge.clock",
                        text: "订阅续期 \(dateStr) · \(days)天后",
                        color: plan == .pro ? Color(red: 0.15, green: 0.75, blue: 0.55) : Color(red: 0.65, green: 0.40, blue: 0.95),
                        bgOpacity: 0.12
                    )
                }
            } else {
                return SubscriptionBadgeInfo(
                    icon: "checkmark.seal.fill",
                    text: "\(plan.displayName) 官方订阅中",
                    color: plan.badgeColor,
                    bgOpacity: 0.12
                )
            }

        case .unknown:
            if let d = renewDate {
                let df = DateFormatter()
                df.dateFormat = "MM/dd HH:mm"
                return SubscriptionBadgeInfo(
                    icon: "calendar",
                    text: "有效期至 \(df.string(from: d))",
                    color: Color.secondary,
                    bgOpacity: 0.12
                )
            }
            return SubscriptionBadgeInfo(
                icon: "shield.fill",
                text: "官方授权有效",
                color: Color.secondary,
                bgOpacity: 0.12
            )
        }
    }

    private func parseRenewalDate(_ dateStr: String?) -> Date? {
        guard let str = dateStr, !str.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: str) { return d }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: str)
    }

    var subscriptionRenewText: String {
        guard let d = parseRenewalDate(subscriptionUntil) else {
            return ""
        }
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        let dateStr = df.string(from: d)

        let diff = Int(d.timeIntervalSince(Date()))
        if diff <= 0 { return "\(dateStr) · 已到期" }
        let days = max(1, Int(ceil(Double(diff) / 86400.0)))
        return "\(dateStr) · \(days)天后"
    }
}

enum ToastType {
    case success
    case error
    case info

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return Color.green
        case .error: return Color.red
        case .info: return Color.blue
        }
    }
}

struct ToastInfo: Equatable {
    let id = UUID()
    let message: String
    let type: ToastType

    static func == (lhs: ToastInfo, rhs: ToastInfo) -> Bool {
        lhs.id == rhs.id
    }
}

enum AddAccountTab: String, CaseIterable, Identifiable {
    case browser = "官方浏览器授权"
    case file = "JSON 凭证导入"
    case manual = "手动填入 Token"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .browser: return "safari.fill"
        case .file: return "doc.badge.plus"
        case .manual: return "key.fill"
        }
    }

    var badgeText: String? {
        switch self {
        case .browser: return "推荐"
        case .file: return "快捷"
        case .manual: return nil
        }
    }
}

