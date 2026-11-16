import Foundation
import CryptoKit

enum CatalogSource {
    static let base = URL(string: "https://deals.iplaysoft.com")!
    static func url(_ path: String) -> URL { URL(string: path, relativeTo: base)!.absoluteURL }
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == base.host, url.query == nil, url.user == nil,
              url.password == nil, url.port == nil else { return false }
        return url.path == "/robots.txt" || url.path.range(of: "^/(page/[0-9]+|(?:vip|app|bundle)/[a-zA-Z0-9_-]+)$", options: .regularExpression) != nil
    }
    static func day(_ date: Date) -> String { ServiceDate.string(date) }
}

struct CatalogProduct: Identifiable, Codable, Equatable, Sendable {
    var id: String { path }
    var path: String
    var name: String
    var category: String
    var kind: String
    var lastVerified: Date? = nil
    var lastError: String? = nil
    var listed = true
    var iconURLs: [String]? = nil
    var sourceURL: URL { CatalogSource.url(path) }
}

enum CatalogCategory {
    static let ordered: [(id: String, title: String)] = [
        ("file", "文件网盘"), ("media", "视频音乐"), ("design", "设计创意"),
        ("productivity", "效率办公"), ("knowledge", "知识学习"), ("life", "生活购物"),
        ("game", "游戏娱乐"), ("system", "系统开发"), ("optimize", "优化辅助"), ("other", "其它")
    ]
    static func key(_ value: String) -> String { ordered.contains { $0.id == value } ? value : "other" }
    static func title(_ value: String) -> String { ordered.first { $0.id == key(value) }!.title }
    static func filter(_ products: [CatalogProduct], category: String, search: String) -> [CatalogProduct] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return products.filter { (category.isEmpty || key($0.category) == category) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }
}

struct OfferDuration: Codable, Equatable, Sendable {
    var months = 0
    var days = 0
    var perpetual = false
    var label: String
    var calculable: Bool { perpetual || months > 0 || days > 0 }
    func expiry(start: String) -> String? {
        guard !perpetual, calculable, let date = ServiceDate.parse(start) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        guard let end = calendar.date(byAdding: .month, value: months, to: date),
              let result = calendar.date(byAdding: .day, value: days, to: end) else { return nil }
        return ServiceDate.string(result)
    }
    static func infer(name: String, unit: String, bundle: Bool, badge: String = "") -> OfferDuration {
        if bundle { return .init(label: "联名套餐 · 各项有效期需分别确认（\(unit)）") }
        if unit.contains("买断") || unit.contains("永久") { return .init(perpetual: true, label: "永久使用权 · 所购版本") }
        let normalized = name.replacingOccurrences(of: "一年", with: "12个月")
            .replacingOccurrences(of: "两年", with: "24个月").replacingOccurrences(of: "三年", with: "36个月")
            .replacingOccurrences(of: "半年", with: "6个月")
        let regex = try! NSRegularExpression(pattern: "([0-9]+)\\s*(?:个)?(年|月|天)")
        let matches = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
        var months = 0, days = 0
        for (index, match) in matches.enumerated() {
            guard let numberRange = Range(match.range(at: 1), in: normalized), let number = Int(normalized[numberRange]),
                  let unitRange = Range(match.range(at: 2), in: normalized) else { continue }
            if index > 0 {
                // Only a bare gift duration can extend the same right. Other services, upgrades,
                // mixed tiers and promotional deadlines must not extend the primary license.
                let previousEnd = matches[index - 1].range.upperBound
                let between = (normalized as NSString).substring(with: NSRange(location: previousEnd, length: match.range.location - previousEnd))
                let suffix = (normalized as NSString).substring(from: match.range.upperBound)
                guard between.range(of: "赠|送", options: .regularExpression) != nil,
                      suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      between.range(of: "[A-Za-z]|会员|网盘|音乐|升级|维护", options: .regularExpression) == nil else {
                    return .init(label: "多项时长 · 请核实后手动填写")
                }
            }
            switch normalized[unitRange] { case "年": months += number * 12; case "月": months += number; default: days += number }
        }
        if matches.isEmpty {
            let trimmed = unit.replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespaces)
            if trimmed == "年" { months = 12 }
            else if trimmed == "月" { months = 1 }
            else if trimmed == "季" { months = 3 }
            else if let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                    let nr = Range(match.range(at: 1), in: trimmed), let number = Int(trimmed[nr]),
                    let ur = Range(match.range(at: 2), in: trimmed) {
                switch trimmed[ur] { case "年": months = number * 12; case "月": months = number; default: days = number }
            }
        }
        let cleanBadge = badge.trimmingCharacters(in: .whitespacesAndNewlines)
        if let total = cleanBadge.range(of: "(?:到手|合计|共|享)\\s*[0-9]+\\s*(?:个)?月(?:\\s|$)", options: .regularExpression) {
            let digits = cleanBadge[total].filter(\.isNumber)
            if let count = Int(digits), count >= months, days == 0 { months = count }
        } else if name.range(of: "赠|送", options: .regularExpression) == nil,
                  cleanBadge.range(of: "^(?:加赠|赠送|赠|送)\\s*[0-9]+\\s*(?:个)?(?:月|天)$", options: .regularExpression) != nil,
                  let count = Int(cleanBadge.filter(\.isNumber)) {
            if cleanBadge.hasSuffix("天") { days += count } else { months += count }
        }
        guard months > 0 || days > 0 else { return .init(label: "时长待确认 · \(unit)") }
        let label = [months > 0 ? "\(months)个月" : nil, days > 0 ? "\(days)天" : nil].compactMap { $0 }.joined(separator: " + ")
        return .init(months: months, days: days, label: label)
    }
}

struct CatalogOffer: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var productPath: String
    var productName: String
    var name: String
    var price: String?
    var currency: String
    var unit: String
    var shop: String
    var specs: String
    var badge: String
    var purchasePath: String
    var duration: OfferDuration
    var observedAt: Date
    var sourceURL: URL { CatalogSource.url(productPath) }
    var purchaseURL: URL { CatalogSource.url(purchasePath) }
    var priceLabel: String { price.map { "\(currency) \($0)\(unit)" } ?? "价格待更新\(unit)" }
    var selectorLabel: String { "\(name) · \(shop) · \(priceLabel)" }
    var groupKey: String {
        let identity = [id, productPath, name, unit, shop, specs, badge, duration.label].joined(separator: "\n")
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var comparisonKey: String {
        // Keep offer ID and all material terms. Only omit explicitly descriptive price badges.
        let marketing = badge.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMarketing = marketing.range(of: #"^(?:日常价|限时优惠|[0-9]+\s*天最低|[0-9]+(?:\.[0-9]+)?\s*折)$"#,
                                          options: .regularExpression) != nil
        let terms = [id, productPath, name, currency, unit, shop, specs, isMarketing ? "" : badge, duration.label]
        // Length prefixes avoid collisions if source terms themselves contain separators.
        return terms.map { "\($0.utf8.count):\($0)" }.joined()
    }
    var decimalPrice: Double? { price.map { NSDecimalNumber(string: $0, locale: Locale(identifier: "en_US_POSIX")).doubleValue } }
}

struct OfferObservation: Identifiable, Codable, Sendable {
    var id: String
    var quote: CatalogOffer
    var runID: String
    var notModified: Bool
}

enum CatalogTrigger: String, Codable, Sendable {
    case daily, manual, adding, directory
    var title: String { switch self { case .daily: "每日自动"; case .manual: "手动刷新"; case .adding: "添加时核实"; case .directory: "手动更新目录" } }
}
struct CatalogRun: Identifiable, Codable, Sendable {
    var id: String
    var trigger: CatalogTrigger
    var startedAt: Date
    var finishedAt: Date?
    var status: String
    var note: String
}
struct CatalogSnapshot: Sendable {
    var products: [CatalogProduct] = []
    var offers: [CatalogOffer] = []
    var observations: [OfferObservation] = []
    var historyGroups: [CatalogOffer] = []
    var historyRevision: Int64 = 0
    var runs: [CatalogRun] = []
    var dailyEnabled = false
}
struct CachedCatalogPage: Sendable {
    var body: String
    var etag: String?
    var modified: String?
}
struct FetchedCatalogPage: Sendable {
    var cache: CachedCatalogPage
    var notModified: Bool
}
enum CatalogError: LocalizedError {
    case invalid(String), http(Int), busy, retryAfter(Date)
    var errorDescription: String? {
        switch self {
        case .invalid(let text): text
        case .http(let code): "优惠站返回 HTTP \(code)，保留最后成功数据。"
        case .busy: "全目录更新正在进行，请稍后再试。"
        case .retryAfter(let date): "站点限流，请在 \(date.formatted()) 后再试。"
        }
    }
}
