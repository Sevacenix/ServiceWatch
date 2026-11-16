import Foundation

enum CatalogParser {
    private static func document(_ html: String) throws -> XMLDocument {
        guard html.utf8.count < 3_000_000 else { throw CatalogError.invalid("页面过大，已停止解析。") }
        // libxml's HTML mode does not honor HTML5 <meta charset> on older macOS.
        let source = html.replacingOccurrences(of: "<head>", with: "<head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">")
        return try XMLDocument(data: Data(source.utf8), options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
    }
    private static func cls(_ value: String) -> String { "contains(concat(' ', normalize-space(@class), ' '), ' \(value) ')" }
    private static func text(_ node: XMLNode, _ xpath: String) -> String {
        let value = (try? node.nodes(forXPath: xpath).first?.stringValue) ?? ""
        return value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func attr(_ node: XMLNode, _ key: String) -> String { (node as? XMLElement)?.attribute(forName: key)?.stringValue ?? "" }
    static func directory(_ html: String) throws -> (products: [CatalogProduct], pages: [String]) {
        // libxml's HTML4 tidy mode moves block children outside HTML5 card anchors.
        // Neutralize only complete product-card wrappers before tidying, preserving
        // the exact source association between a service and its one/two brand icons.
        let wrappers = try NSRegularExpression(pattern: "<a\\b([^>]*\\bdata-item-id\\s*=[^>]*)>(.*?)</a\\s*>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let normalized = wrappers.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "<div $1>$2</div>")
        let doc = try document(normalized)
        let cards = try doc.nodes(forXPath: "//*[\(cls("card")) and @data-item-id]")
        let products = try cards.map { card -> CatalogProduct in
            let path = attr(card, "href")
            guard CatalogSource.allowed(CatalogSource.url(path)), !path.hasPrefix("/page/") else { throw CatalogError.invalid("目录包含不支持的来源链接。") }
            let name = text(card, ".//*[\(cls("meta"))]/h3")
            let fallback = attr(card, "aria-label").replacingOccurrences(of: "查看", with: "").replacingOccurrences(of: "优惠", with: "")
            let category = attr(card, "data-cat")
            let kind = path.split(separator: "/").first.map(String.init) ?? ""
            guard !name.isEmpty || !fallback.isEmpty else { throw CatalogError.invalid("目录产品名缺失。") }
            var icons: [String] = []
            for image in try card.nodes(forXPath: ".//img[@src]") {
                let source = attr(image, "src")
                if let url = URL(string: source, relativeTo: CatalogSource.base)?.absoluteURL,
                   BrandIconSource.allowed(url), !icons.contains(url.absoluteString) { icons.append(url.absoluteString) }
            }
            return CatalogProduct(path: path, name: name.isEmpty ? fallback : name, category: category, kind: kind, iconURLs: icons.isEmpty ? nil : icons)
        }
        guard !products.isEmpty, Set(products.map(\.path)).count == products.count else { throw CatalogError.invalid("未识别出完整产品目录，保留旧数据。") }
        let links = try doc.nodes(forXPath: "//a[starts-with(@href, '/page/')]").map { attr($0, "href") }
        let pages = Set(links.filter { $0.range(of: "^/page/[0-9]+$", options: .regularExpression) != nil }).sorted()
        guard pages.count < 100 else { throw CatalogError.invalid("目录分页数超出上限。") }
        return (products, pages)
    }
    static func detail(_ html: String, product: CatalogProduct, now: Date) throws -> [CatalogOffer] {
        let doc = try document(html)
        // JSON-LD establishes product identity; AggregateOffer is deliberately not
        // used as a tier price. Each concrete channel must have its own price.
        let scripts = try doc.nodes(forXPath: "//script[@type='application/ld+json']")
        let graphs = scripts.compactMap { ($0.stringValue ?? "").data(using: .utf8) }.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let identities = graphs.flatMap { $0["@graph"] as? [[String: Any]] ?? [$0] }.filter { $0["@type"] as? String == "Product" }
        guard identities.contains(where: {
            guard let url = ($0["url"] as? String).flatMap(URL.init(string:)) else { return false }
            return CatalogSource.allowed(url) && url.path == product.path
        }) else {
            throw CatalogError.invalid("产品身份与所选服务不符，未应用报价。")
        }
        let options = try doc.nodes(forXPath: "//*[@data-offer-option]")
        guard !options.isEmpty else { throw CatalogError.invalid("未找到具体等级方案，保留旧报价。") }
        let offers = try options.map { option -> CatalogOffer in
            let id = attr(option, "id")
            let name = text(option, ".//*[\(cls("offer-name"))]")
            let price = text(option, ".//*[\(cls("offer-price"))]/strong")
            let unit = text(option, ".//*[\(cls("offer-price"))]/small")
            let symbol = text(option, ".//*[\(cls("offer-currency"))]")
            let pending = !text(option, ".//*[\(cls("offer-pending"))]").isEmpty
            let currency: String
            switch symbol {
            case "¥", "￥": currency = "CNY"
            case "$", "US$": currency = "USD"
            case "€": currency = "EUR"
            case "" where pending:
                let sourceCurrency = (identities.first?["offers"] as? [String: Any])?["priceCurrency"] as? String
                guard let sourceCurrency, sourceCurrency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { throw CatalogError.invalid("待报价方案未提供币种。") }
                currency = sourceCurrency
            default: throw CatalogError.invalid("未知报价币种：\(symbol)")
            }
            let link = try option.nodes(forXPath: ".//a[\(cls("offer-purchase"))]").first
            let path = link.map { attr($0, "href") } ?? ""
            guard !id.isEmpty, !name.isEmpty, pending || (RenewalPlan.validAmount(price) && NSDecimalNumber(string: price).doubleValue.isFinite),
                  path.range(of: "^/go/[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
                throw CatalogError.invalid("方案价格或购买链接不完整，整页保留上次成功报价。")
            }
            let shop = text(option, ".//*[\(cls("offer-store"))]/span")
            let specs = [text(option, ".//*[\(cls("offer-specs"))]"), text(option, ".//*[\(cls("offer-note"))]")].filter { !$0.isEmpty }.joined(separator: " · ")
            let badge = text(option, ".//*[\(cls("offer-badge"))]")
            return CatalogOffer(id: product.path + "#" + id, productPath: product.path, productName: product.name,
                                name: name, price: pending ? nil : price, currency: currency, unit: unit, shop: shop.isEmpty ? "渠道待确认" : shop,
                                specs: specs, badge: badge, purchasePath: path,
                                duration: .infer(name: name, unit: unit, bundle: product.kind == "bundle", badge: badge), observedAt: now)
        }
        guard Set(offers.map(\.id)).count == offers.count else { throw CatalogError.invalid("页面方案标识重复，已停止更新。") }
        return offers
    }
}
