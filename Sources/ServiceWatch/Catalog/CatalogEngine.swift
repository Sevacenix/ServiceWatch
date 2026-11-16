import Foundation

actor CatalogEngine {
    private let database: CatalogDatabase
    private let transport: any CatalogTransport
    private var robotsDay: String?
    private var denied: [String] = []
    private var updatingAll = false
    private var inFlight: [String: Task<[CatalogOffer], Error>] = [:]
    init(url: URL, transport: any CatalogTransport = CatalogHTTP()) throws {
        database = try CatalogDatabase(url: url)
        self.transport = transport
    }
    func snapshot() throws -> CatalogSnapshot { try database.snapshot() }
    func history(_ groupKey: String) throws -> [OfferObservation] { try database.history(groupKey: groupKey) }
    func comparison(groupKeys: [String], currency: String, now: Date) throws -> PriceComparison {
        try database.comparison(groupKeys: groupKeys, currency: currency, now: now)
    }
    func setDailyEnabled(_ enabled: Bool) throws { try database.setSetting("daily_enabled", enabled ? "true" : "false") }
    private func fetch(_ url: URL) async throws -> FetchedCatalogPage {
        guard CatalogSource.allowed(url), !denied.contains(where: { url.path.hasPrefix($0) }) else { throw CatalogError.invalid("robots规则不允许读取该页面。") }
        if let text = try database.setting("retry_after"), let value = Double(text), value > Date().timeIntervalSince1970 {
            throw CatalogError.retryAfter(Date(timeIntervalSince1970: value))
        }
        do { return try await transport.get(url, cache: database.cache(url)) }
        catch CatalogError.retryAfter(let until) {
            try database.setSetting("retry_after", String(until.timeIntervalSince1970)); throw CatalogError.retryAfter(until)
        }
    }
    private func ensureRobots(now: Date) async throws {
        guard robotsDay != CatalogSource.day(now) else { return }
        let url = CatalogSource.url("/robots.txt")
        // robots itself is always readable; no private JSON indexes or tracking APIs are requested.
        let page = try await fetch(url)
        var applies = false, rules: [String] = []
        for raw in page.cache.body.components(separatedBy: .newlines) {
            let line = raw.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0].lowercased() == "user-agent" { applies = parts[1] == "*" }
            if applies && parts[0].lowercased() == "disallow" && !parts[1].isEmpty { rules.append(parts[1]) }
        }
        guard page.cache.body.lowercased().contains("user-agent:") else { throw CatalogError.invalid("无法确认站点robots规则，暂停同步。") }
        denied = rules
        robotsDay = CatalogSource.day(now)
        try database.saveCache(url, page.cache)
    }
    private func directory(now: Date) async throws -> [CatalogProduct] {
        try await ensureRobots(now: now)
        let firstURL = CatalogSource.url("/page/1")
        let firstPage = try await fetch(firstURL)
        let first = try CatalogParser.directory(firstPage.cache.body)
        var products = first.products
        var pages = [(firstURL, firstPage)]
        for path in first.pages where path != "/page/1" {
            let url = CatalogSource.url(path)
            let page = try await fetch(url)
            products += try CatalogParser.directory(page.cache.body).products
            pages.append((url, page))
        }
        guard Set(products.map(\.path)).count == products.count else { throw CatalogError.invalid("分页产品重复，保留上次完整目录。") }
        try database.replaceDirectory(products)
        for (url, page) in pages { try database.saveCache(url, page.cache) }
        return try database.products().filter(\.listed)
    }
    func refreshDirectory(now: Date = Date()) async throws {
        guard !updatingAll else { throw CatalogError.busy }
        guard let run = try database.begin(.directory, now: now) else { return }
        do {
            let products = try await directory(now: now)
            try database.finish(run, status: "成功", note: "已更新\(products.count)项目录，未占用每日额度。", now: Date())
        } catch {
            try database.finish(run, status: "失败", note: error.localizedDescription, now: Date()); throw error
        }
    }
    private func product(_ product: CatalogProduct, run: CatalogRun, now: Date) async throws -> [CatalogOffer] {
        if let task = inFlight[product.path] { return try await task.value }
        let task = Task { () throws -> [CatalogOffer] in
            let page = try await self.fetch(product.sourceURL)
            let offers = try CatalogParser.detail(page.cache.body, product: product, now: now)
            try self.database.saveProduct(product, offers: offers, runID: run.id, page: page)
            return offers
        }
        inFlight[product.path] = task
        do {
            let result = try await task.value
            inFlight[product.path] = nil
            return result
        } catch {
            inFlight[product.path] = nil
            try database.failProduct(product.path, message: error.localizedDescription)
            throw error
        }
    }
    func refreshProduct(path: String, trigger: CatalogTrigger, now: Date = Date()) async throws -> [CatalogOffer] {
        guard let current = try database.products().first(where: { $0.path == path && $0.listed }),
              let run = try database.begin(trigger, now: now) else { throw CatalogError.invalid("请先更新并选择目录中的服务。") }
        do {
            try await ensureRobots(now: now)
            let result = try await product(current, run: run, now: now)
            try database.finish(run, status: "成功", note: "\(current.name)：核实\(result.count)个方案/渠道，未占用每日额度。", now: Date())
            return result
        } catch {
            try database.finish(run, status: "失败", note: error.localizedDescription, now: Date()); throw error
        }
    }
    @discardableResult func refreshAll(trigger: CatalogTrigger, now: Date = Date(), progress: @Sendable (String) -> Void = { _ in }) async throws -> String {
        guard !updatingAll else { throw CatalogError.busy }
        if trigger == .daily {
            if try database.setting("daily_enabled") != "true" { return "每日自动更新已关闭。" }
        }
        guard let run = try database.begin(trigger, now: now) else { return "今天的自动批次已尝试，未重复联网。" }
        updatingAll = true
        defer { updatingAll = false }
        do {
            progress("正在更新完整服务目录…")
            let products = try await directory(now: now)
            var success = 0, failed = 0, count = 0
            for (index, current) in products.enumerated() {
                progress("核实方案 \(index + 1)/\(products.count) · \(current.name)")
                do { count += try await product(current, run: run, now: Date()).count; success += 1 }
                catch {
                    failed += 1
                    if case CatalogError.retryAfter = error { throw error }
                    if case CatalogError.http(let code) = error, [401, 403, 429, 503].contains(code) { throw error }
                }
            }
            let note = "目录\(products.count)项；成功\(success)项、\(count)个方案/渠道；失败\(failed)项（保留旧价）。"
            try database.finish(run, status: failed == 0 ? "成功" : "部分成功", note: note, now: Date())
            return note
        } catch {
            try database.finish(run, status: "失败", note: error.localizedDescription + " 已入库的成功记录和历史均保留。", now: Date()); throw error
        }
    }
}
