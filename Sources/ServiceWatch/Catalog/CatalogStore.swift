import SwiftUI
import AppKit
import Observation

@MainActor @Observable final class CatalogStore {
    private(set) var snapshot = CatalogSnapshot()
    private(set) var isUpdating = false
    private(set) var refreshingPaths: Set<String> = []
    private(set) var error: String?
    private(set) var progress = ""
    private(set) var outcome = "尚未更新"
    var search = ""
    var categoryFilter = ""
    var comparisonProductPath = ""
    var comparisonOfferKey = ""
    let databaseURL: URL
    let icons: BrandIconStore
    @ObservationIgnored private var engine: CatalogEngine?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init(url: URL, transport: any CatalogTransport = CatalogHTTP()) {
        databaseURL = url
        icons = BrandIconStore(folder: url.deletingLastPathComponent().appendingPathComponent("Icons", isDirectory: true))
        do { engine = try CatalogEngine(url: url, transport: transport) }
        catch { self.error = error.localizedDescription }
    }
    var products: [CatalogProduct] { snapshot.products.filter(\.listed) }
    var filteredProducts: [CatalogProduct] { CatalogCategory.filter(products, category: categoryFilter, search: search) }
    var visibleOfferCount: Int {
        let paths = Set(filteredProducts.map(\.path))
        return snapshot.offers.filter { paths.contains($0.productPath) }.count
    }
    func iconSources(for service: Service) -> [String] {
        let product = service.offerPath.flatMap { path in snapshot.products.first { $0.path == path } } ??
            snapshot.products.first { $0.name.caseInsensitiveCompare(service.name) == .orderedSame }
        return product?.iconURLs ?? []
    }
    func offers(_ path: String) -> [CatalogOffer] { snapshot.offers.filter { $0.productPath == path } }
    func matching(_ quote: CatalogOffer) -> CatalogOffer? { snapshot.offers.first { $0.groupKey == quote.groupKey } }
    func reload() async {
        guard let engine else { return }
        do {
            snapshot = try await engine.snapshot()
            icons.prefetch(snapshot.products.flatMap { $0.iconURLs ?? [] })
            if outcome == "尚未更新", let last = snapshot.runs.first { outcome = "\(last.trigger.title) · \(last.status)：\(last.note)" }
        }
        catch { self.error = error.localizedDescription }
    }
    func start() async {
        guard !started else { return }
        started = true
        await reload()
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.sevacenix.ServiceWatch.Open.catalog.daily")
        scheduler.interval = 1800
        scheduler.tolerance = 300
        scheduler.repeats = true
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in await self?.refreshAll(.daily); completion(.finished) }
        }
        self.scheduler = scheduler
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll(.daily) }
        }
        await refreshAll(.daily)
    }
    func setDailyEnabled(_ value: Bool) async {
        guard let engine else { return }
        do {
            try await engine.setDailyEnabled(value)
            await reload()
            if value { await refreshAll(.daily) }
        } catch { self.error = error.localizedDescription }
    }
    func refreshDirectory() async {
        guard let engine, !isUpdating else { return }
        isUpdating = true; error = nil; progress = "正在获取全部服务目录…"
        do { try await engine.refreshDirectory(); outcome = "目录已更新；添加时将另行核实具体方案。" }
        catch { self.error = error.localizedDescription }
        await reload(); isUpdating = false
    }
    @discardableResult func verify(_ path: String, trigger: CatalogTrigger = .manual) async -> [CatalogOffer]? {
        guard let engine, !refreshingPaths.contains(path) else { return nil }
        refreshingPaths.insert(path)
        defer { refreshingPaths.remove(path) }
        do {
            let offers = try await engine.refreshProduct(path: path, trigger: trigger)
            await reload()
            outcome = "\(trigger.title)：已核实\(offers.count)个具体方案。"
            return offers
        } catch { self.error = error.localizedDescription; await reload(); return nil }
    }
    func refreshAll(_ trigger: CatalogTrigger = .manual) async {
        guard let engine, !isUpdating else { return }
        if trigger == .daily && !snapshot.dailyEnabled { return }
        if trigger == .daily && snapshot.runs.contains(where: { $0.trigger == .daily && CatalogSource.day($0.startedAt) == CatalogSource.day(Date()) }) { return }
        isUpdating = true; error = nil
        do {
            outcome = try await engine.refreshAll(trigger: trigger) { [weak self] text in
                Task { @MainActor in self?.progress = text; await self?.reload() }
            }
        } catch { self.error = error.localizedDescription }
        await reload(); isUpdating = false
    }
    func comparison(for offer: CatalogOffer, now: Date = Date()) async throws -> PriceComparison {
        guard let engine else { throw CatalogError.invalid("优惠数据库不可用。") }
        let keys = Set(snapshot.historyGroups.filter { $0.comparisonKey == offer.comparisonKey }.map(\.groupKey))
        return try await engine.comparison(groupKeys: keys.sorted(), currency: offer.currency, now: now)
    }
}
