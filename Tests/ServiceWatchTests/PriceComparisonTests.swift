import XCTest
@testable import ServiceWatch

final class PriceComparisonTests: XCTestCase {
    private let product = CatalogProduct(path: "/vip/bilibili", name: "哔哩哔哩", category: "media", kind: "vip")

    private func quote(_ price: String?, at date: Date, badge: String = "", currency: String = "CNY") -> CatalogOffer {
        .init(id: "/vip/bilibili#offer-1-test", productPath: product.path, productName: product.name,
              name: "大会员年卡", price: price, currency: currency, unit: "/年", shop: "京东旗舰店", specs: "",
              badge: badge, purchasePath: "/go/test", duration: .init(months: 12, label: "12个月"), observedAt: date)
    }

    func testAllTimeMinimumSurvivesChartLimitAndMissingPrices() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("catalog.sqlite")
        let db = try CatalogDatabase(url: url)
        let page = FetchedCatalogPage(cache: .init(body: "test", etag: nil, modified: nil), notModified: false)
        let low = quote("54.00", at: PriceCalendar.date(2025, 11, 11), badge: "90 天最低")
        let june = quote("100", at: PriceCalendar.date(2026, 6, 18))
        let november = quote("70", at: PriceCalendar.date(2026, 11, 11))
        try db.saveProduct(product, offers: [low], runID: "fixture", page: page)
        try db.saveProduct(product, offers: [june], runID: "fixture", page: page)
        try db.saveProduct(product, offers: [november], runID: "fixture", page: page)
        try db.saveProduct(product, offers: [quote("1", at: PriceCalendar.date(2026, 11, 12), currency: "USD")], runID: "fixture", page: page)
        var variant = quote("2", at: PriceCalendar.date(2026, 11, 13))
        variant.badge = "仅新用户"
        try db.saveProduct(product, offers: [variant], runID: "fixture", page: page)
        let day = PriceCalendar.date(2026, 11, 16)
        for offset in 0...205 {
            let current = quote(offset == 205 ? nil : "125", at: day.addingTimeInterval(Double(offset)))
            try db.saveProduct(product, offers: [current], runID: "fixture", page: page)
        }
        // Reopen the previous schema and derive history from retained observation rows.
        let reopened = try CatalogDatabase(url: url)
        let snapshot = try reopened.snapshot()
        let keys = Set(snapshot.historyGroups.filter { $0.comparisonKey == november.comparisonKey }.map(\.groupKey))
        XCTAssertEqual(keys, Set([low.groupKey, november.groupKey]))
        let result = try reopened.comparison(groupKeys: keys.sorted(), currency: "CNY", now: day.addingTimeInterval(600))
        XCTAssertEqual(result.chart.count, 200)
        XCTAssertFalse(result.chart.contains { $0.quote.price == "54.00" })
        XCTAssertEqual(result.firstSample, low.observedAt)
        XCTAssertEqual(result.historical.point?.amount, 54)
        XCTAssertEqual(result.historical.sampledDays, 4)
        XCTAssertEqual(result.years[2026]?.low.point?.amount, 70)
        XCTAssertEqual(result.years[2026]?.events[.june]?.point?.amount, 100)
        XCTAssertEqual(result.years[2026]?.events[.november]?.point?.amount, 70)
        XCTAssertNil(result.years[2026]?.events[.blackFriday])
        XCTAssertNil(snapshot.offers.first?.price)
        XCTAssertEqual(snapshot.historyRevision, 211)
    }

    func testFestivalWindowsUseShanghaiBoundariesAndFourthThursday() {
        let june = PriceEvent.june.window(year: 2026)
        XCTAssertTrue(june.contains(PriceCalendar.date(2026, 6, 18)))
        XCTAssertFalse(june.contains(june.upperBound))
        XCTAssertFalse(june.contains(june.lowerBound.addingTimeInterval(-1)))
        XCTAssertEqual(PriceEvent.blackFriday.window(year: 2026).lowerBound, PriceCalendar.date(2026, 11, 27))
        XCTAssertEqual(PriceEvent.blackFriday.window(year: 2026).upperBound, PriceCalendar.date(2026, 11, 30))
        XCTAssertEqual(PriceEvent.blackFriday.window(year: 2024).upperBound, PriceCalendar.date(2024, 12, 2))
        let event = PriceEvent.november.window(year: 2026)
        var comparison = PriceComparison()
        comparison.observe(PricePoint(price: "80", at: event.upperBound)!)
        comparison.observe(PricePoint(price: "120", at: event.upperBound.addingTimeInterval(-1))!)
        XCTAssertEqual(comparison.years[2026]?.events[.november]?.point?.amount, 120)
        XCTAssertEqual(comparison.years[2026]?.low.point?.amount, 80)
    }

    func testComparisonKeyKeepsMaterialOfferTerms() {
        let date = PriceCalendar.date(2026, 11, 11)
        let original = quote("108", at: date)
        XCTAssertEqual(original.comparisonKey, quote("98", at: date, badge: "90 天最低").comparisonKey)
        for change: (inout CatalogOffer) -> Void in [
            { $0.currency = "USD" }, { $0.shop = "淘宝旗舰店" }, { $0.unit = "/2年" },
            { $0.duration = .init(months: 13, label: "13个月") },
            { $0.name = "超级大会员年卡" }, { $0.badge = "仅新用户" }, { $0.specs = "限新用户" }
        ] {
            var other = original
            change(&other)
            XCTAssertNotEqual(other.comparisonKey, original.comparisonKey)
        }
    }

    func testDeltaUsesReferenceAsDenominatorAndNeverDividesByZero() throws {
        let date = PriceCalendar.date(2026, 11, 11)
        let current = try XCTUnwrap(PricePoint(price: "120", at: date))
        let reference = try XCTUnwrap(PricePoint(price: "100", at: date))
        let zero = try XCTUnwrap(PricePoint(price: "0", at: date))
        XCTAssertEqual(PriceDelta(current: current, reference: reference).amount, 20)
        XCTAssertEqual(PriceDelta(current: current, reference: reference).fraction, Decimal(string: "0.2"))
        XCTAssertEqual(PriceDelta(current: reference, reference: current).amount, -20)
        XCTAssertEqual(PriceDelta(current: current, reference: current).description, "持平")
        XCTAssertNil(PriceDelta(current: current, reference: zero).fraction)
        XCTAssertNil(PricePoint(price: "价格待更新", at: date))
    }
}
