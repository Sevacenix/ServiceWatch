import XCTest
@testable import ServiceWatch

private actor FixtureCatalogTransport: CatalogTransport {
    var pages: [String: String]
    var requested: [String] = []
    var failure: CatalogError?
    init(detail: String) {
        pages = ["/robots.txt": "User-agent: *\nDisallow: /data/\nDisallow: /beacon.php\n",
                 "/page/1": "<html><head></head><body><a class='card' data-item-id='1' href='/vip/bilibili' aria-label='查看哔哩哔哩优惠' data-cat='media'>哔哩哔哩</a></body></html>",
                 "/vip/bilibili": detail]
    }
    func get(_ url: URL, cache: CachedCatalogPage?) async throws -> FetchedCatalogPage {
        requested.append(url.path)
        if let failure { throw failure }
        guard let body = pages[url.path] else { throw CatalogError.http(404) }
        return .init(cache: .init(body: body, etag: "fixture-v1", modified: nil), notModified: cache?.body == body)
    }
    func setFailure(_ value: CatalogError?) { failure = value }
    func replaceDetail(_ body: String) { pages["/vip/bilibili"] = body }
    func count() -> Int { requested.count }
}

final class CatalogTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func location() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ServiceWatch-Catalog-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("catalog.sqlite")
    }
    private func offers(_ name: String = "bilibili", path: String = "/vip/bilibili") throws -> [CatalogOffer] {
        try CatalogParser.detail(fixture(name), product: .init(path: path, name: name, category: "media", kind: path.split(separator: "/").first.map(String.init)!), now: Date())
    }

    func testThreeFixtureDirectoryPagesProduceNineDistinctProducts() throws {
        let all = try (1...3).flatMap { try CatalogParser.directory(fixture("catalog-\($0)")).products }
        XCTAssertEqual(all.count, 9)
        XCTAssertEqual(Set(all.map(\.path)).count, 9)
        XCTAssertEqual(all.filter { $0.kind == "app" }.count, 2)
        XCTAssertEqual(all.filter { $0.kind == "bundle" }.count, 1)
        XCTAssertTrue(all.contains { $0.path == "/app/parallelsdesktop" && $0.name == "Parallels Desktop 示例" })
        XCTAssertTrue(all.contains { $0.path == "/vip/icloud" })
    }

    func testBilibiliConcretePricesRemainAttachedToTheirTiersAndChannels() throws {
        let quotes = try offers()
        XCTAssertEqual(quotes.map(\.price), ["108", "168", "178", "188"])
        XCTAssertFalse(quotes[0].name.contains("超级"))
        XCTAssertTrue(quotes[1].name.contains("超级"))
        XCTAssertEqual(quotes[0].duration.months, 13)
        XCTAssertEqual(quotes[1].duration.months, 13)
        XCTAssertEqual(quotes[3].duration.months, 24)
        XCTAssertEqual(quotes[0].duration.expiry(start: "2026-11-09"), "2027-12-09")
        XCTAssertEqual(Set(quotes.map(\.groupKey)).count, 4)
        XCTAssertTrue(quotes.allSatisfy { $0.purchaseURL.host == "deals.iplaysoft.com" })
    }

    func testParallelsStandardAndProStaySeparateIncludingAlternateChannels() throws {
        let quotes = try offers("parallels", path: "/app/parallelsdesktop")
        XCTAssertEqual(quotes.count, 3)
        XCTAssertEqual(quotes[0].price, "249")
        XCTAssertTrue(quotes[0].name.contains("标准版"))
        XCTAssertTrue(quotes.last!.name.contains("专业版"))
        XCTAssertTrue(quotes.allSatisfy { $0.duration.months == 12 && !$0.duration.perpetual })
        XCTAssertEqual(Set(quotes.map(\.groupKey)).count, 3)
    }

    func testBundleDoesNotInventIndividualExpiryOrBorrowCheapestTierPrice() throws {
        let quotes = try offers("iqiyi-jd", path: "/bundle/iqiyi-jd")
        XCTAssertEqual(quotes.map(\.price), ["168", "248"])
        XCTAssertTrue(quotes[0].name.contains("黄金"))
        XCTAssertTrue(quotes[1].name.contains("白金"))
        XCTAssertTrue(quotes.allSatisfy { !$0.duration.calculable })
    }

    func testExplicitPendingQuoteDoesNotEraseTwoKnownBaiduPricesOrBecomeZero() throws {
        let quotes = try offers("baidu", path: "/vip/baiduwangpan")
        XCTAssertEqual(quotes.count, 3)
        XCTAssertEqual(quotes[0].price, "176")
        XCTAssertEqual(quotes[1].price, "196")
        XCTAssertNil(quotes[2].price)
        XCTAssertNil(quotes[2].decimalPrice)
        XCTAssertEqual(quotes[1].duration.months, 15)
        XCTAssertTrue(quotes[2].priceLabel.contains("价格待更新"))
    }

    func testDurationDistinguishesPermanentRightsAndOtherGiftedProducts() {
        let permanent = OfferDuration.infer(name: "软件永久版，含1年升级", unit: "/买断", bundle: false)
        XCTAssertTrue(permanent.perpetual)
        XCTAssertNil(permanent.expiry(start: "2026-11-09"))
        let gift = OfferDuration.infer(name: "会员12个月+赠3个月AI会员", unit: "/年", bundle: false)
        XCTAssertFalse(gift.calculable)
        XCTAssertEqual(OfferDuration.infer(name: "年度会员", unit: "/2年", bundle: false).months, 24)
        XCTAssertEqual(OfferDuration.infer(name: "年度会员", unit: "/年", bundle: false, badge: "加赠3个月").months, 15)
        XCTAssertEqual(OfferDuration.infer(name: "会员12个月+赠1个月", unit: "/年", bundle: false, badge: "享 13 个月").months, 13)
        XCTAssertNil(OfferDuration.infer(name: "会员", unit: "/年", bundle: false).expiry(start: "2027-02-29"))
    }

    func testPlanSwitchUpdatesTierDurationAndQuoteTogetherAndCustomTierDetachesQuote() throws {
        let quotes = try offers()
        var draft = EntitlementDraft()
        draft.apply(quotes[0], start: "2026-11-09")
        XCTAssertEqual(draft.value.quote?.price, "108")
        XCTAssertEqual(draft.value.expires, "2027-12-09")
        draft.apply(quotes[1], start: "2026-11-09")
        XCTAssertEqual(draft.tier, quotes[1].name)
        XCTAssertEqual(draft.value.quote?.price, "168")
        XCTAssertEqual(draft.value.quote?.id, quotes[1].id)
        draft.tier = "用户自定义等级"
        XCTAssertNil(draft.value.quote)
    }

    func testManualChecksAndDailyBudgetAreIndependentAndPersistAcrossReopen() async throws {
        let url = try location()
        let transport = FixtureCatalogTransport(detail: try fixture("bilibili"))
        let engine = try CatalogEngine(url: url, transport: transport)
        let day = ServiceDate.parse("2026-11-09")!
        try await engine.setDailyEnabled(true)
        try await engine.refreshDirectory(now: day)
        _ = try await engine.refreshProduct(path: "/vip/bilibili", trigger: .adding, now: day)
        _ = try await engine.refreshAll(trigger: .daily, now: day)
        let afterDaily = await transport.count()
        _ = try await engine.refreshAll(trigger: .daily, now: day)
        let afterRepeatedDaily = await transport.count()
        XCTAssertEqual(afterRepeatedDaily, afterDaily)
        _ = try await engine.refreshProduct(path: "/vip/bilibili", trigger: .manual, now: day)
        let afterManual = await transport.count()
        XCTAssertGreaterThan(afterManual, afterDaily)
        let reopenedTransport = FixtureCatalogTransport(detail: try fixture("bilibili"))
        let reopened = try CatalogEngine(url: url, transport: reopenedTransport)
        _ = try await reopened.refreshAll(trigger: .daily, now: day)
        let reopenedCount = await reopenedTransport.count()
        XCTAssertEqual(reopenedCount, 0)
        _ = try await reopened.refreshAll(trigger: .daily, now: ServiceDate.parse("2026-11-10")!)
        let snapshot = try await reopened.snapshot()
        XCTAssertEqual(snapshot.runs.filter { $0.trigger == .daily }.count, 2)
        XCTAssertEqual(snapshot.runs.filter { $0.trigger == .manual }.count, 1)
    }

    func test304AddsRealObservationAndBadPageDoesNotReplaceAnyPrice() async throws {
        let transport = FixtureCatalogTransport(detail: try fixture("bilibili"))
        let engine = try CatalogEngine(url: location(), transport: transport)
        try await engine.refreshDirectory()
        let first = try await engine.refreshProduct(path: "/vip/bilibili", trigger: .adding)
        _ = try await engine.refreshProduct(path: "/vip/bilibili", trigger: .manual)
        let history = try await engine.history(first[0].groupKey)
        XCTAssertEqual(history.count, 2)
        XCTAssertTrue(history.first!.notModified)
        XCTAssertEqual(history.map { $0.quote.price }, ["108", "108"])
        let before = try await engine.snapshot()
        await transport.replaceDetail(try fixture("bilibili").replacingOccurrences(of: "<strong>168</strong>", with: "<strong></strong>"))
        do { _ = try await engine.refreshProduct(path: "/vip/bilibili", trigger: .manual); XCTFail("Invalid page should fail") } catch {}
        let after = try await engine.snapshot()
        XCTAssertEqual(after.offers, before.offers)
        XCTAssertNotNil(after.products.first?.lastError)
        let retained = try await engine.history(first[0].groupKey)
        XCTAssertEqual(retained.count, 2)
    }

    func testFailedDailyAttemptIsNotRetriedUntilNextDayButManualStillWorks() async throws {
        let transport = FixtureCatalogTransport(detail: try fixture("bilibili"))
        let engine = try CatalogEngine(url: location(), transport: transport)
        let day = ServiceDate.parse("2026-11-09")!
        try await engine.setDailyEnabled(true)
        await transport.setFailure(.http(403))
        do { _ = try await engine.refreshAll(trigger: .daily, now: day); XCTFail("Expected blocked request") } catch {}
        let count = await transport.count()
        await transport.setFailure(nil)
        _ = try await engine.refreshAll(trigger: .daily, now: day)
        let after = await transport.count()
        XCTAssertEqual(after, count)
        try await engine.refreshDirectory(now: day)
        _ = try await engine.refreshProduct(path: "/vip/bilibili", trigger: .manual, now: day)
        let snapshot = try await engine.snapshot()
        XCTAssertEqual(snapshot.runs.filter { $0.trigger == .daily }.first?.status, "失败")
        XCTAssertEqual(snapshot.offers.count, 4)
    }

    func testConcurrentDatabaseConnectionsCannotClaimTwoDailyRuns() throws {
        let url = try location()
        let first = try CatalogDatabase(url: url)
        let second = try CatalogDatabase(url: url)
        let now = Date()
        XCTAssertNotNil(try first.begin(.daily, now: now))
        XCTAssertNil(try second.begin(.daily, now: now))
        XCTAssertNotNil(try second.begin(.manual, now: now))
        XCTAssertNotNil(try first.begin(.adding, now: now))
    }

    func testOlderResponseCannotOverwriteNewerQuoteButBothObservationsRemain() throws {
        let database = try CatalogDatabase(url: location())
        let product = CatalogProduct(path: "/vip/bilibili", name: "哔哩哔哩", category: "media", kind: "vip")
        try database.replaceDirectory([product])
        var older = try offers()[0]
        older.observedAt = ServiceDate.parse("2026-11-09")!
        var newer = older
        newer.price = "100"
        newer.observedAt = ServiceDate.parse("2026-11-10")!
        let page = FetchedCatalogPage(cache: .init(body: "fixture", etag: nil, modified: nil), notModified: false)
        try database.saveProduct(product, offers: [newer], runID: "new", page: page)
        try database.saveProduct(product, offers: [older], runID: "old", page: page)
        XCTAssertEqual(try database.offers().first?.price, "100")
        XCTAssertEqual(try database.history(groupKey: newer.groupKey).count, 2)
    }

    func testDailyPreferencePersistsWithoutDisablingManualChecks() async throws {
        let url = try location()
        let transport = FixtureCatalogTransport(detail: try fixture("bilibili"))
        let engine = try CatalogEngine(url: url, transport: transport)
        try await engine.setDailyEnabled(false)
        _ = try await engine.refreshAll(trigger: .daily)
        let count = await transport.count()
        XCTAssertEqual(count, 0)
        let reopened = try CatalogEngine(url: url, transport: transport)
        let snapshot = try await reopened.snapshot()
        XCTAssertFalse(snapshot.dailyEnabled)
        try await reopened.refreshDirectory()
        _ = try await reopened.refreshProduct(path: "/vip/bilibili", trigger: .manual)
        let updated = try await reopened.snapshot()
        XCTAssertEqual(updated.offers.count, 4)
    }

    func testNetworkAllowlistRejectsPrivateAndExternalSources() {
        for url in ["https://deals.iplaysoft.com/data/index.json", "https://deals.iplaysoft.com/?q=key", "https://evil.test/vip/bilibili", "http://deals.iplaysoft.com/vip/bilibili", "https://deals.iplaysoft.com/beacon.php"] {
            XCTAssertFalse(CatalogSource.allowed(URL(string: url)!))
        }
        XCTAssertTrue(CatalogSource.allowed(CatalogSource.url("/page/3")))
        XCTAssertTrue(CatalogSource.allowed(CatalogSource.url("/app/parallelsdesktop")))
    }

    func testLiveCatalogImportWhenExplicitlyRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["SERVICEWATCH_LIVE_DB"] else { throw XCTSkip("Live integration is opt-in") }
        let engine = try CatalogEngine(url: URL(fileURLWithPath: path))
        let trigger: CatalogTrigger = .manual
        let note: String
        if let product = ProcessInfo.processInfo.environment["SERVICEWATCH_LIVE_PRODUCT"] {
            let quotes = try await engine.refreshProduct(path: product, trigger: .manual)
            note = "单项核实：\(product) / \(quotes.count)方案"
        } else { note = try await engine.refreshAll(trigger: trigger) { print($0) } }
        let snapshot = try await engine.snapshot()
        print("LIVE RESULT: \(note)")
        print("LIVE PRODUCTS: \(snapshot.products.count); OFFERS: \(snapshot.offers.count)")
        for product in snapshot.products where product.lastError != nil { print("LIVE ERROR \(product.path): \(product.lastError!)") }
        XCTAssertGreaterThanOrEqual(snapshot.products.count, 68)
        XCTAssertTrue(snapshot.products.allSatisfy { $0.lastVerified != nil && $0.lastError == nil })
    }
}
