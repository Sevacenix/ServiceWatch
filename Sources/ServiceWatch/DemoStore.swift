import SwiftUI
import Observation

@MainActor @Observable final class DemoStore {
    var destination: Destination? = .services
    private(set) var services: [Service] = []
    private(set) var changes: [ServiceChange] = []
    private(set) var storageIssue: String? = nil
    @ObservationIgnored private let repository: AuthorizationRepository
    let catalog: CatalogStore
    var selectedID: Int?
    var search = ""
    var filter = "全部"
    var showingImport = false
    var showingEditor = false
    var editingID: Int? = nil
    var editingEntitlementID: UUID? = nil
    var addingEntitlement = false
    var showingRenewalManager = false
    var renewalServiceID: Int? = nil
    var message: String? = nil
    var storagePath: String { repository.fileURL.path }
    var isTestData: Bool { repository.fileURL != AuthorizationRepository.defaultProductionURL }
    init(repository: AuthorizationRepository = .init(fileURL: AuthorizationRepository.defaultURL)) {
        self.repository = repository
        catalog = CatalogStore(url: repository.fileURL.deletingLastPathComponent().appendingPathComponent("catalog.sqlite"))
        do {
            if let archive = try repository.load() {
                services = archive.services
                changes = archive.changes
            }
            selectedID = services.first?.id
        } catch {
            storageIssue = error.localizedDescription
            message = "读取授权数据失败：\(error.localizedDescription)\n原文件未被覆盖。\n\(repository.fileURL.path)"
        }
    }
    var selectedService: Service? { services.first { $0.id == selectedID } }
    func comparePrice(_ offer: CatalogOffer) {
        catalog.comparisonProductPath = offer.productPath
        catalog.comparisonOfferKey = offer.comparisonKey
        destination = .history
    }
    var pendingRenewalCount: Int {
        services.filter { !$0.example && $0.renewalPlan?.showsReviewPrompt == true }.count
    }
    func manageRenewal(_ service: Service) {
        renewalServiceID = service.id
        showingRenewalManager = true
    }
    func updateRenewal(serviceID: Int, plan: RenewalPlan) throws {
        guard var latest = services.first(where: { $0.id == serviceID }) else { throw AuthorizationStorageError.invalidRecords }
        var updated = plan
        let prior = latest.renewalPlan
        guard prior != updated else { return }
        let factsChanged = prior?.status != updated.status || prior?.nextCharge != updated.nextCharge ||
            prior?.amount != updated.amount || prior?.currency != updated.currency || prior?.channel != updated.channel ||
            prior?.method != updated.method || prior?.cycle != updated.cycle
        if factsChanged {
            updated.verifiedAt = updated.status == .unverified ? nil : Date()
        }
        updated.updatedAt = Date()
        latest.renewalPlan = updated
        latest.autoRenew = updated.status.title
        latest.nextCharge = updated.nextCharge
        latest.nextAmount = updated.amount
        try save(latest)
    }
    var expiringSoonCount: Int {
        services.filter { service in
            service.paid && !service.example && service.entitlements.contains {
                !$0.perpetual && (ServiceDate.days($0.expires).map { (0...30).contains($0) } ?? false)
            }
        }.count
    }
    var nextExpiryNote: String {
        let days = services.filter { $0.paid && !$0.example }.flatMap(\.entitlements)
            .filter { !$0.perpetual }.compactMap { ServiceDate.days($0.expires) }
        if let next = days.filter({ $0 >= 0 }).min() { return "最近授权到期还有 \(next) 天" }
        return days.contains(where: { $0 < 0 }) ? "有授权已到期，请查看详情" : "暂无明确到期日"
    }
    var filtered: [Service] {
        services.filter { service in
            (search.isEmpty || service.name.localizedCaseInsensitiveContains(search)) &&
            (filter == "全部" || (filter == "已开通" && service.paid) || (filter == "未开通" && !service.paid))
        }.sorted {
            if $0.paid != $1.paid { return $0.paid }
            return ($0.nextExpiry ?? "9999") < ($1.nextExpiry ?? "9999")
        }
    }
    func edit(_ service: Service?, entitlementID: UUID? = nil, adding: Bool = false) {
        editingID = service?.id
        editingEntitlementID = entitlementID
        addingEntitlement = adding
        showingEditor = true
    }
    func save(_ value: Service) throws {
        guard storageIssue == nil else { throw AuthorizationStorageError.unavailable }
        let old = services.first { $0.id == value.id }
        guard old != value else { return }
        var updated = services
        if let index = updated.firstIndex(where: { $0.id == value.id }) { updated[index] = value }
        else { updated.append(value) }
        if value.example {
            services = updated
            selectedID = value.id
            return
        }
        let change = ServiceChange(before: old, after: value)
        let updatedChanges = changes + [change]
        // Commit on disk first: failed writes must not appear saved in the UI.
        try repository.save(AuthorizationArchive(services: updated.filter { !$0.example }, changes: updatedChanges))
        services = updated
        changes = updatedChanges
        selectedID = value.id
    }
}
