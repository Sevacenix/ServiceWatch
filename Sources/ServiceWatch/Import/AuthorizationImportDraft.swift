import Foundation

enum ImportTarget: Hashable {
    case choose, add, update(UUID)
}

struct AuthorizationImportDraft: Equatable {
    var origin: ImportOrigin
    var serviceID: Int?
    var serviceName: String
    var target: ImportTarget
    var baseline: Entitlement?
    var tier: String
    var validity: String
    var expiry: String
    var markPaid: Bool

    init(origin: ImportOrigin, name: String, service: Service?, candidate: RecognizedAuthorization) {
        self.origin = origin
        serviceID = service?.id
        serviceName = name
        target = (service?.entitlements.isEmpty ?? true) ? .add : .choose
        tier = candidate.tier
        expiry = candidate.expiry ?? ""
        validity = candidate.perpetual ? "永久授权" : expiry.isEmpty ? "待确认" : "有到期日"
        markPaid = service == nil
    }

    var cleanName: String { serviceName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var cleanTier: String { tier.trimmingCharacters(in: .whitespacesAndNewlines) }
    var cleanExpiry: String { expiry.trimmingCharacters(in: .whitespacesAndNewlines) }
    var validFields: Bool {
        !cleanName.isEmpty && cleanName.count <= 100 && !cleanTier.isEmpty && cleanTier.count <= 100 &&
        ["有到期日", "永久授权", "待确认"].contains(validity) &&
        (validity != "有到期日" || ServiceDate.parse(cleanExpiry) != nil)
    }
    var validitySummary: String { validity == "有到期日" ? cleanExpiry : validity }
    func selection(_ value: ImportTarget, in service: Service?) -> AuthorizationImportDraft {
        var draft = self
        draft.target = value
        if case .update(let id) = value { draft.baseline = service?.entitlements.first { $0.id == id } }
        else { draft.baseline = nil }
        return draft
    }
}

extension DemoStore {
    // The review UI and the commit use the same validation against the latest stored record.
    func prepareImport(_ draft: AuthorizationImportDraft) throws -> Service {
        guard draft.validFields else { throw ImportInputError.invalidFields }
        let existing = services.first { $0.id == draft.serviceID && !$0.example }
        if draft.serviceID != nil && existing == nil { throw ImportInputError.staleTarget }
        let key = AuthorizationRecognition.key
        if existing == nil && services.contains(where: { !$0.example && key($0.name) == key(draft.cleanName) }) {
            throw ImportInputError.duplicateService
        }
        let product = catalog.snapshot.products.first { $0.listed && key($0.name) == key(draft.cleanName) }
        var service = existing ?? Service(id: (services.map(\.id).max() ?? 0) + 1,
                                          name: draft.cleanName,
                                          category: product.map { CatalogCategory.title($0.category) } ?? "自定义服务",
                                          symbol: "key.horizontal.fill", tint: .teal, paid: draft.markPaid,
                                          entitlements: [], offerPath: product?.path,
                                          evidence: draft.origin.rawValue + " · 用户确认")
        var entitlement: Entitlement
        var index: Int?
        switch draft.target {
        case .choose: throw ImportInputError.chooseTarget
        case .add: entitlement = .init(tier: draft.cleanTier, expires: nil)
        case .update(let id):
            guard let position = service.entitlements.firstIndex(where: { $0.id == id }),
                  service.entitlements[position] == draft.baseline else { throw ImportInputError.staleTarget }
            index = position
            entitlement = service.entitlements[position]
            if draft.validity == "待确认" && (entitlement.expires != nil || entitlement.perpetual) {
                throw ImportInputError.preserveExpiry
            }
        }
        if service.entitlements.contains(where: { $0.id != entitlement.id && key($0.tier) == key(draft.cleanTier) }) {
            throw ImportInputError.duplicate
        }
        let expiry = draft.validity == "有到期日" ? draft.cleanExpiry : nil
        let perpetual = draft.validity == "永久授权"
        if index == nil || entitlement.tier != draft.cleanTier || entitlement.expires != expiry || entitlement.perpetual != perpetual {
            if entitlement.tier != draft.cleanTier { entitlement.quote = nil }
            entitlement.tier = draft.cleanTier
            entitlement.expires = expiry
            entitlement.perpetual = perpetual
            entitlement.importOrigin = draft.origin
        }
        if let index { service.entitlements[index] = entitlement }
        else { service.entitlements.append(entitlement) }
        if draft.markPaid { service.paid = true }
        return service
    }

    @discardableResult func saveImport(_ draft: AuthorizationImportDraft) throws -> Int {
        let service = try prepareImport(draft)
        try save(service)
        return service.id
    }
}
