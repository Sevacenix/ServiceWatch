import XCTest
import AppKit
@testable import ServiceWatch

private actor FixtureIconDownloads: BrandIconFetching {
    let bytes: Data
    private(set) var requests = 0
    init(bytes: Data) { self.bytes = bytes }
    func data(_ url: URL) async throws -> Data { requests += 1; return bytes }
    func count() -> Int { requests }
}

final class CatalogPresentationTests: XCTestCase {
    private func fixture(_ page: Int) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "catalog-\(page)", withExtension: "html", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func products() throws -> [CatalogProduct] { try (1...3).flatMap { try CatalogParser.directory(fixture($0)).products } }
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ServiceWatch-Brand-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }
    @MainActor private func imageData() throws -> Data {
        let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { image.setColor(.systemBlue, atX: x, y: y) } }
        return try XCTUnwrap(image.representation(using: .png, properties: [:]))
    }
    func testCategoryAndTextSearchComposeWithoutHidingOtherServices() throws {
        let all = try products()
        XCTAssertEqual(CatalogCategory.filter(all, category: "", search: "").count, 9)
        XCTAssertEqual(CatalogCategory.filter(all, category: "file", search: "").count, 2)
        XCTAssertEqual(CatalogCategory.filter(all, category: "media", search: "").count, 3)
        XCTAssertEqual(CatalogCategory.filter(all, category: "other", search: "").count, 1)
        let matched = CatalogCategory.filter(all, category: "media", search: " 京东 ")
        XCTAssertFalse(matched.isEmpty)
        XCTAssertTrue(matched.allSatisfy { $0.category == "media" && $0.name.contains("京东") })
        XCTAssertTrue(CatalogCategory.filter(all, category: "media", search: "Parallels").isEmpty)
        XCTAssertEqual(CatalogCategory.title("future-category"), "其它")
    }
    func testCatalogIconSourcesAndBundleIconPairs() throws {
        let all = try products()
        XCTAssertTrue(all.allSatisfy { !($0.iconURLs ?? []).isEmpty })
        XCTAssertTrue(all.flatMap { $0.iconURLs ?? [] }.allSatisfy { URL(string: $0).map(BrandIconSource.allowed) == true })
        XCTAssertEqual(all.first { $0.path == "/bundle/bilibili-jd" }?.iconURLs?.count, 2)
        XCTAssertEqual(all.first { $0.path == "/vip/bilibili" }?.iconURLs?.first,
            all.first { $0.path == "/bundle/bilibili-jd" }?.iconURLs?.first)
    }
    func testLegacyCatalogHydratesIconsFromCacheWithoutNewPriceRuns() throws {
        let url = try folder().appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase(url: url)
        var legacy = try products()
        for index in legacy.indices { legacy[index].iconURLs = nil }
        try database.replaceDirectory(legacy)
        for page in 1...3 {
            try database.saveCache(CatalogSource.url("/page/\(page)"), .init(body: fixture(page), etag: "cached", modified: nil))
        }
        let now = Date()
        XCTAssertNotNil(try database.begin(.daily, now: now))
        let before = try database.snapshot()
        let reopened = try CatalogDatabase(url: url)
        let after = try reopened.snapshot()
        XCTAssertEqual(after.products.count, before.products.count)
        XCTAssertTrue(after.products.allSatisfy { !($0.iconURLs ?? []).isEmpty })
        XCTAssertEqual(after.products.map(\.lastVerified), before.products.map(\.lastVerified))
        XCTAssertEqual(after.offers, before.offers)
        XCTAssertEqual(after.runs.map(\.id), before.runs.map(\.id))
        XCTAssertNil(try reopened.begin(.daily, now: now))
    }
    @MainActor func testDownloadedBrandIconIsReusedFromDiskAfterRestart() async throws {
        let directory = try folder().appendingPathComponent("Icons")
        let data = try imageData()
        let downloader = FixtureIconDownloads(bytes: data)
        let source = "https://deals-cdn.iplaysoft.com/assets/icons/offline-fixture.png"
        let store = BrandIconStore(folder: directory, downloads: downloader)
        let first = await store.load(source)
        XCTAssertNotNil(first)
        let requests = await downloader.count()
        XCTAssertEqual(requests, 1)
        let offline = FixtureIconDownloads(bytes: Data())
        let reopened = BrandIconStore(folder: directory, downloads: offline)
        let cached = await reopened.load(source)
        XCTAssertNotNil(cached)
        let offlineRequests = await offline.count()
        XCTAssertEqual(offlineRequests, 0)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(BrandIconSource.filename(source))), data)
    }
    @MainActor func testInvalidSourcesAndNonImagesCannotEnterIconCache() async throws {
        let downloader = FixtureIconDownloads(bytes: Data("not an image".utf8))
        let store = BrandIconStore(folder: try folder(), downloads: downloader)
        for source in ["file:///etc/passwd", "https://evil.test/assets/icons/logo.png", "https://deals.iplaysoft.com/data/icon.png", "http://deals-cdn.iplaysoft.com/assets/icons/logo.png"] {
            let image = await store.load(source)
            XCTAssertNil(image)
        }
        let requests = await downloader.count()
        XCTAssertEqual(requests, 0)
        XCTAssertThrowsError(try store.saveCustom(Data("not an image".utf8)))
        XCTAssertFalse(BrandIconSource.validCustomName("../outside.image"))
    }
    @MainActor func testManualServiceIconPersistsWithAuthorization() async throws {
        let directory = try folder()
        let icons = BrandIconStore(folder: directory.appendingPathComponent("Icons"))
        let name = try icons.saveCustom(imageData())
        let repository = AuthorizationRepository(fileURL: directory.appendingPathComponent("authorizations.json"))
        var service = ServiceFixtures.services[0]
        service.customIcon = name
        try repository.save(.init(services: [service]))
        let reopened = DemoStore(repository: repository)
        XCTAssertEqual(reopened.services[0].customIcon, name)
        XCTAssertNotNil(reopened.catalog.icons.customImage(name))
    }
}
