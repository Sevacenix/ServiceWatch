import Foundation

struct RecognizedAuthorization: Identifiable, Equatable, Sendable {
    let id = UUID()
    var tier: String
    var expiry: String? = nil
    var perpetual = false
    var evidence: String
}

struct ImportRecognition: Sendable {
    var origin: ImportOrigin
    var service: String?
    var candidates: [RecognizedAuthorization]
    var excerpt: String
    var ambiguousService = false
}

enum AuthorizationRecognition {
    private struct Tier {
        var name: String
        var aliases: [String]
        init(_ name: String, _ aliases: String...) { self.name = name; self.aliases = [name] + aliases }
    }

    private struct Profile {
        var name: String
        var aliases: [String]
        var tiers: [Tier]
    }

    private static let profiles: [Profile] = [
        .init(name: "Parallels Desktop", aliases: ["Parallels Desktop", "Parallels"], tiers: [
            .init("Standard", "Standard Edition", "标准版"), .init("Pro", "Pro Edition", "专业版"),
            .init("Business", "Business Edition", "商业版"), .init("Enterprise", "Enterprise Edition", "企业版")
        ]),
        .init(name: "腾讯视频", aliases: ["腾讯视频", "騰訊視頻", "WeTV"], tiers: [.init("SVIP", "超级影视 VIP"), .init("VIP")]),
        .init(name: "哔哩哔哩", aliases: ["哔哩哔哩", "嗶哩嗶哩", "bilibili", "云视听小电视", "超级大会员", "超級大會員"], tiers: [
            .init("超级大会员", "超級大會員", "超大会员"), .init("大会员", "大會員")
        ]),
        .init(name: "WPS", aliases: ["WPS", "WPS云服务", "WPS Office"], tiers: [
            .init("超级会员", "超級會員"), .init("大会员", "大會員"), .init("AI 会员", "AI会员")
        ]),
        .init(name: "京东 PLUS", aliases: ["京东PLUS", "京東PLUS", "PLUS会员", "PLUS會員"], tiers: [.init("PLUS 年卡", "年卡")]),
        .init(name: "QQ 音乐", aliases: ["QQ音乐", "QQ音樂", "豪华绿钻", "豪華綠鑽"], tiers: [
            .init("超级会员", "超級會員"), .init("豪华绿钻", "豪華綠鑽"), .init("听书会员", "聽書會員")
        ]),
        .init(name: "百度网盘", aliases: ["百度网盘", "百度網盤", "库库AI"], tiers: [
            .init("超级会员 SVIP", "超级会员", "超級會員", "SVIP")
        ]),
        .init(name: "Keep", aliases: ["Keep", "语音轻松跑"], tiers: [.init("Keep 会员", "会员", "會員")]),
        .init(name: "爱奇艺", aliases: ["爱奇艺", "愛奇藝", "iQIYI"], tiers: [
            .init("黄金 VIP", "黄金VIP", "黄金会员"), .init("白金 VIP", "白金VIP", "白金会员"), .init("星钻 VIP", "星钻VIP", "星钻会员")
        ]),
        .init(name: "知乎", aliases: ["知乎", "盐选会员"], tiers: [.init("盐选会员", "盐选")]),
        .init(name: "微博", aliases: ["微博"], tiers: [.init("SVIP"), .init("VIP")]),
        .init(name: "喜马拉雅", aliases: ["喜马拉雅"], tiers: [.init("VIP", "VIP会员")]),
        .init(name: "得到电子书", aliases: ["得到电子书", "得到电子書"], tiers: [.init("电子书会员", "电子书")])
    ]

    private static let expiryCue = #"(?i)(?:有效期(?:至|到|截止)?|有效至|会员至|會員至|會員有效期|授[权權]至|订阅至|訂閱至|到期转成[^；，。]{0,16}?至|到期轉成[^；，。]{0,16}?至|到期(?:日期|时间|日)?|截止日期|valid\s+(?:until|through|to)|expires?(?:\s+(?:on|at))?|expir(?:y|ation)(?:\s+date)?|(?:subscription|license|membership)\s+ends?(?:\s+on)?|subscription\s+end\s+date)"#
    private static let otherCue = #"(?i)(?:扣[款费費]|(?:下次|自动|自動)\s*续[费費]|续费(?:日|时间|金额)|续订日期|续約|(?:下单|支付|付款|购买|开通|激活|生效|起算|开始)(?:日期|时间|日)|下单于|购买于|订单日期|订单时间|促销|优惠|活动|兑换|優惠|兌換|優惠券|券有效期|维护|維護|技术支持|支持期|升级期|(?:next\s+)?(?:bill(?:ing)?|charg[e]|renew(?:al|s)?|order|purchase|activation|start)(?:\s+(?:on|at|date|time))?|(?:support|maintenance|upgrade)(?:\s+(?:ends?|until|through|expires?|expiry|period|validity))?|offer|promotion|coupon|redeem(?:\s+by)?)"#
    private static let permanentCue = #"(?i)(?:永久授[权權]|永久使用[权權]|(?:perpetual|lifetime)\s+(?:software\s+)?license)"#
    private static let months = "Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?"
    private static let numericDate = #"(?:19|20|21)[0-9]{2}\s*(?:年|[-./])\s*[0-9]{1,2}\s*(?:月|[-./])\s*[0-9]{1,2}\s*日?"#
    private static let dateRegex = try! NSRegularExpression(pattern:
        "(?i)(?<![0-9])(?:\(numericDate)|(?:\(months))\\.?\\s+[0-9]{1,2}(?:st|nd|rd|th)?[,]?\\s+(?:19|20|21)[0-9]{2}|[0-9]{1,2}\\s+(?:\(months))\\.?[,]?\\s+(?:19|20|21)[0-9]{2})(?![0-9])")
    private static let jdDateRegex = try! NSRegularExpression(pattern: #"(?<![0-9.])([2-9][0-9])\.([0-9]{1,2})\.([0-9]{1,2})(?=\s*到期)"#)
    private static let fieldRegex = try! NSRegularExpression(pattern:
        #"(?i)(?:^|[；;|])\s*(?:会员等级|会员类型|会员级别|授权等级|订阅等级|等级|套餐|版本|edition|plan|tier)\s*:\s*([^,，。；;|\n]{1,80})"#)

    static func key(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased().filter { !$0.isWhitespace }
    }

    private static func searchText(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: #"(?<=[\p{Han}])\s+|\s+(?=[\p{Han}])"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    static func recognize(_ document: ImportDocument, names: [String]) -> ImportRecognition {
        let lines = clean(document.lines, origin: document.origin)
        let productLines = lines.filter {
            $0.text.range(of: #"(?i)联合会员|聯合會員|联名|聯名|[+＋]|赠送|推荐|^From:|^To:"#, options: .regularExpression) == nil
        }
        let compact = productLines.map { searchText($0.text) }
        let profileMatches = profiles.filter { p in
            p.aliases.contains { alias in
                compact.contains { text in
                    if alias == "Keep" && document.origin == .email && text != "keep" {
                        return text.contains("keep会员") || text.contains("keep會員")
                    }
                    return matches(searchText(alias), in: text)
                }
            }
        }
        var matchesNames = Set(profileMatches.map(\.name))
        for name in names {
            let needle = searchText(name)
            guard needle.count >= 2, !profiles.contains(where: { p in p.aliases.contains { searchText($0) == needle } || searchText(p.name) == needle }),
                  compact.contains(where: { matches(needle, in: $0) }) else { continue }
            // A longer catalogue name that includes a recognized service is not a second account.
            if !profileMatches.contains(where: { p in p.aliases.contains { needle.contains(searchText($0)) } }) {
                matchesNames.insert(name)
            }
        }
        let service = matchesNames.count == 1 ? matchesNames.first : nil
        let profile = profiles.first { $0.name == service }
        let lineTiers = lines.map { tiers($0.text, profile: profile) }
        let allTiers = Set(lineTiers.flatMap { $0 })
        let defaultTier = allTiers.count == 1 ? allTiers.first ?? "" : ""
        var candidates: [RecognizedAuthorization] = []
        func append(_ tier: String, _ expiry: String?, _ perpetual: Bool, _ evidence: String) {
            guard !candidates.contains(where: { $0.tier == tier && $0.expiry == expiry && $0.perpetual == perpetual }) else { return }
            candidates.append(.init(tier: tier, expiry: expiry, perpetual: perpetual, evidence: String(evidence.prefix(420))))
        }
        for (index, line) in lines.enumerated() {
            guard candidates.count < 40 else { break }
            let adjacent = previousContext(index: index, lines: lines, lineTiers: lineTiers)
            let lineExpiry = line.text.range(of: expiryCue, options: .regularExpression) != nil
            let dateItems = dates(line.text, jd: service == "京东 PLUS")
            if let permanent = line.text.range(of: permanentCue, options: .regularExpression),
               !disallowed(String(line.text[..<permanent.lowerBound])) {
                let tier = lineTiers[index].count == 1 ? lineTiers[index][0] : adjacent?.tier ?? defaultTier
                append(tier, nil, true, line.text)
            }
            for (offset, item) in dateItems.enumerated() {
                let start = offset == 0 ? line.text.startIndex : dateItems[offset - 1].range.upperBound
                let end = offset + 1 == dateItems.count ? line.text.endIndex : dateItems[offset + 1].range.lowerBound
                let prefix = String(line.text[start..<item.range.lowerBound])
                let suffix = String(line.text[item.range.upperBound..<end])
                let nearbyTiers = tiers(prefix, profile: profile)
                let suffixTiers = tiers(suffix, profile: profile)
                let sameTier = nearbyTiers.count == 1 ? nearbyTiers.first :
                    nearbyTiers.isEmpty && dateItems.count == 1 && lineTiers[index].count == 1 ? lineTiers[index].first : nil
                let explicitPrefix = prefix.range(of: expiryCue, options: .regularExpression) != nil && !disallowed(prefix)
                let explicitSuffix = suffix.range(of: #"^\s*(?:到期|有效期截止|截止|expires?\b)"#, options: [.regularExpression, .caseInsensitive]) != nil && !disallowed(prefix)
                let rangeEnd = offset > 0 && lineExpiry && !disallowed(line.text) && isRangeJoin(prefix)
                let rangeStart = offset + 1 < dateItems.count && isRangeJoin(suffix)
                let adjacentExpiry = dateItems.count == 1 && prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    adjacent?.expiryLabel == true
                let tencent = service == "腾讯视频" && sameTier != nil &&
                    prefix.range(of: #"腾讯视频\s*S?VIP\s*:\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
                let baidu = service == "百度网盘" && prefix.range(of: #"(?i)\bSVIP\s*至\s*[:：]?\s*$"#, options: .regularExpression) != nil
                let qqCard = service == "QQ 音乐" && document.origin == .screenshot && dateItems.count == 1 &&
                    (sameTier != nil || adjacent?.tier != nil) &&
                    suffix.range(of: #"^\s*续费\s*[>〉›]?\s*$"#, options: .regularExpression) != nil
                guard !rangeStart, !disallowed(prefix),
                      explicitPrefix || explicitSuffix || rangeEnd || adjacentExpiry || tencent || baidu || qqCard else { continue }
                let tier = sameTier ?? (lineTiers[index].isEmpty && suffixTiers.isEmpty ? adjacent?.tier : nil) ?? (rangeEnd ? lineTiers[index].first : nil) ?? defaultTier
                let evidence = sameTier == nil ? [adjacent?.text, line.text].compactMap { $0 }.joined(separator: "\n") : line.text
                append(tier, item.day, false, evidence)
            }
        }
        if candidates.isEmpty {
            let evidence = lines.first(where: { !$0.text.isEmpty })?.text ?? ""
            if allTiers.isEmpty { append("", nil, false, evidence) }
            else { for tier in allTiers.sorted().prefix(12) { append(tier, nil, false, lines.first(where: { tiers($0.text, profile: profile).contains(tier) })?.text ?? evidence) } }
        }
        return .init(origin: document.origin, service: service, candidates: candidates,
                     excerpt: String(lines.map(\.text).joined(separator: "\n").prefix(12_000)), ambiguousService: matchesNames.count > 1)
    }

    private static func previousContext(index: Int, lines: [ImportLine], lineTiers: [[String]]) -> (tier: String?, expiryLabel: Bool, text: String)? {
        guard index > 0 else { return nil }
        var label: String?
        for prior in stride(from: index - 1, through: max(0, index - 5), by: -1) {
            if let a = lines[prior].box, let b = lines[index].box {
                // Adjacent rows of the same column, not the similarly placed date on another card.
                if a.midY - b.midY > 0.12 { break }
                if a.midY - b.midY < max(a.height, b.height) * 0.45 ||
                    (abs(a.minX - b.minX) > 0.16 && (a.maxX < b.minX || b.maxX < a.minX)) { continue }
            }
            let text = lines[prior].text
            let hasDates = dates(text, jd: false).isEmpty == false
            if text.range(of: #"^(?:开通时间|开通日期|购买日期|下单时间|开通来源|订单号)(?=\s|:|[0-9]|$)"#, options: .regularExpression) != nil { continue }
            if disallowed(text) { break }
            let expiryLabel = text.range(of: expiryCue, options: .regularExpression) != nil && !hasDates
            if expiryLabel && label == nil { label = text }
            if lineTiers[prior].count == 1 {
                return (lineTiers[prior][0], label != nil, [text, label].compactMap { $0 }.joined(separator: "\n"))
            }
            if hasDates || lineTiers[prior].count > 1 { break }
        }
        return label.map { (nil, true, $0) }
    }

    private static func tiers(_ line: String, profile: Profile?) -> [String] {
        let compact = searchText(line)
        var hits: [(String, Range<String.Index>)] = []
        for tier in profile?.tiers ?? [] {
            for alias in tier.aliases {
                let needle = searchText(alias)
                guard !needle.isEmpty else { continue }
                if let range = aliasRange(needle, in: compact, allowTrailingDigit: profile?.name == "百度网盘") {
                    hits.append((tier.name, range))
                }
            }
        }
        let longest = hits.filter { hit in
            !hits.contains { other in other.0 != hit.0 && other.1 != hit.1 && other.1.lowerBound <= hit.1.lowerBound && other.1.upperBound >= hit.1.upperBound }
        }
        if !longest.isEmpty { return Array(Set(longest.map(\.0))).sorted() }
        guard let match = fieldRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let valueRange = Range(match.range(at: 1), in: line) else { return [] }
        var value = String(line[valueRange])
        if let cutoff = value.range(of: expiryCue + "|" + otherCue, options: .regularExpression) { value = String(value[..<cutoff.lowerBound]) }
        if let firstDate = dates(value, jd: false).first { value = String(value[..<firstDate.range.lowerBound]) }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.contains("[已隐藏]") ? [] : [value]
    }

    private static func matches(_ needle: String, in value: String) -> Bool { aliasRange(needle, in: value) != nil }

    private static func aliasRange(_ needle: String, in value: String, allowTrailingDigit: Bool = false) -> Range<String.Index>? {
        guard !needle.isEmpty else { return nil }
        let asciiLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        let asciiAlnum = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let endSet = allowTrailingDigit ? asciiLetters : asciiAlnum
        var start = value.startIndex
        while let range = value.range(of: needle, range: start..<value.endIndex) {
            let before = range.lowerBound == value.startIndex ? nil : value[value.index(before: range.lowerBound)].unicodeScalars.first
            let after = range.upperBound == value.endIndex ? nil : value[range.upperBound].unicodeScalars.first
            let first = needle.unicodeScalars.first!, last = needle.unicodeScalars.last!
            if !(asciiAlnum.contains(first) && before.map(asciiAlnum.contains) == true),
               !(asciiAlnum.contains(last) && after.map(endSet.contains) == true) { return range }
            start = value.index(after: range.lowerBound)
        }
        return nil
    }

    private static func disallowed(_ text: String) -> Bool { text.range(of: otherCue, options: .regularExpression) != nil }
    private static func isRangeJoin(_ text: String) -> Bool {
        text.range(of: #"(?i)^\s*(?:至|到|through|to|[—~～])\s*$"#, options: .regularExpression) != nil
    }

    private static func dates(_ text: String, jd: Bool) -> [(day: String, range: Range<String.Index>)] {
        let span = NSRange(text.startIndex..., in: text)
        var values = dateRegex.matches(in: text, range: span).compactMap { result -> (String, Range<String.Index>)? in
            guard let range = Range(result.range, in: text), let day = day(String(text[range])) else { return nil }
            return (day, range)
        }
        if jd {
            for result in jdDateRegex.matches(in: text, range: span) {
                guard let range = Range(result.range, in: text), let day = day("20" + text[range]) else { continue }
                values.append((day, range))
            }
        }
        return values.sorted { $0.1.lowerBound < $1.1.lowerBound }
    }

    private static func day(_ token: String) -> String? {
        let parts = token.split(whereSeparator: { !$0.isASCII || !$0.isNumber })
        let numbers = parts.compactMap { Int($0) }
        var year = 0, month = 0, day = 0
        if numbers.count == 3 {
            (year, month, day) = (numbers[0], numbers[1], numbers[2])
        } else if numbers.count == 2 {
            (day, year) = (numbers[0], numbers[1])
            let shortNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            if let index = shortNames.firstIndex(where: { token.lowercased().contains($0) }) { month = index + 1 }
        }
        let value = String(format: "%04d-%02d-%02d", year, month, day)
        return (1900...2199).contains(year) && ServiceDate.parse(value) != nil ? value : nil
    }

    private static func clean(_ lines: [ImportLine], origin: ImportOrigin) -> [ImportLine] {
        var result: [ImportLine] = []
        var hideNext = false
        for original in lines.prefix(2_000) {
            let source = original.text.precomposedStringWithCompatibilityMapping
                .replacingOccurrences(of: "[‐‑‒–−]", with: "-", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if origin == .email && source.range(of: #"(?i)^(?:On .+ wrote:|[- ]*Original Message[- ]*|[- ]*Forwarded message[- ]*|发件人\s*:|原始邮件|转发邮件)"#, options: .regularExpression) != nil { break }
            if source.isEmpty || source.hasPrefix(">") { continue }
            let secretLabel = source.range(of: #"(?i)^(?:.*?(?:授权密钥|许可证密钥|序列号|激活码|验证码|license key|activation (?:key|code)|serial (?:no|number)|password))\s*[:：]?\s*"#, options: .regularExpression)
            if hideNext || secretLabel != nil {
                hideNext = !hideNext && secretLabel?.upperBound == source.endIndex
                continue
            }
            let sanitized = source
                .replacingOccurrences(of: #"(?i)https?://[^\s<>]+"#, with: "[链接已隐藏]", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, with: "[邮箱已隐藏]", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)(?<![A-Z0-9])(?:[A-Z0-9*]{4,8}-){2,}[A-Z0-9*]{4,8}(?![A-Z0-9])|(?<!\d)1[3-9]\d{9}(?!\d)"#, with: "[已隐藏]", options: .regularExpression)
            for clause in sanitized.split(whereSeparator: { "；;|".contains($0) }) {
                let text = String(clause.prefix(2_000)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.append(.init(text: text, box: original.box)) }
            }
        }
        return result
    }
}
