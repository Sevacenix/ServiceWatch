import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case services = "服务与授权", offers = "优惠发现", history = "价格历史"
    case inbox = "授权导入", sources = "数据源与更新"
    case guide = "使用向导"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .services: "square.stack.3d.up"
        case .offers: "tag"
        case .history: "chart.xyaxis.line"
        case .inbox: "tray.and.arrow.down"
        case .sources: "arrow.triangle.2.circlepath"
        case .guide: "questionmark.circle"
        }
    }
}

struct Entitlement: Identifiable, Codable, Equatable {
    var id = UUID()
    var tier: String
    var expires: String?
    var note: String = ""
    var perpetual = false
    var quote: CatalogOffer? = nil
    var importOrigin: ImportOrigin? = nil
}

enum ServiceTint: String, Codable {
    case blue, pink, orange, green, red, purple, teal
    var color: Color {
        switch self {
        case .blue: .blue
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        case .red: .red
        case .purple: .purple
        case .teal: .teal
        }
    }
}

struct Service: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
    var category: String
    var symbol: String
    var tint: ServiceTint
    var color: Color { tint.color }
    var paid: Bool
    var entitlements: [Entitlement]
    var channel = "待核实"
    var method = "待核实"
    var autoRenew = "未知"
    var nextCharge: String? = nil
    var nextAmount: String? = nil
    var offerPath: String?
    var evidence = "本地记录"
    var example = false
    var billingCycle = "待核实"
    var paidAmount: String? = nil
    var currency = "CNY"
    var customURL: String? = nil
    var renewalPlan: RenewalPlan? = nil
    var customIcon: String? = nil
    var nextExpiry: String? { entitlements.first?.perpetual == true ? nil : entitlements.first?.expires }
}

struct ServiceChange: Identifiable, Codable {
    var id = UUID()
    var recordedAt = Date()
    var before: Service?
    var after: Service
    var summary: String { summary(language: .simplifiedChinese) }

    func summary(language: AppLanguage) -> String {
        func validity(_ entitlement: Entitlement) -> String {
            if entitlement.perpetual { return L10n.label("永久授权", language: language) }
            return entitlement.expires ?? L10n.label("待确认", language: language)
        }

        guard let before else {
            let title = after.entitlements.contains { $0.importOrigin != nil } ? "导入添加服务与授权" : "手动添加服务与授权"
            return L10n.label(title, language: language)
        }
        let parts = after.entitlements.compactMap { current -> String? in
            guard let old = before.entitlements.first(where: { $0.id == current.id }) else {
                return L10n.text("新增 \(current.tier)：\(validity(current))", language: language)
            }
            guard old.tier != current.tier || old.expires != current.expires || old.perpetual != current.perpetual else { return nil }
            return L10n.text("\(current.tier)：\(validity(old)) → \(validity(current))", language: language)
        }
        var descriptions = parts
        if before.renewalPlan != after.renewalPlan, let plan = after.renewalPlan {
            descriptions.append(L10n.text("自动扣款：\(plan.summary(language: language))", language: language))
        }
        if before.customIcon != after.customIcon { descriptions.append(L10n.label("更新服务图标", language: language)) }
        return descriptions.isEmpty
            ? L10n.label("更新服务资料或主要授权", language: language)
            : descriptions.joined(separator: L10n.label("；", language: language))
    }
}

enum ServiceDate {
    static var today: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.startOfDay(for: Date())
    }
    static func parse(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        guard text.count == 10, let date = f.date(from: text), f.string(from: date) == text else { return nil }
        return date
    }
    static func string(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func days(_ value: String?) -> Int? {
        guard let value, let date = parse(value) else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c.dateComponents([.day], from: today, to: date).day
    }
}
