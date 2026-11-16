import Foundation

struct EntitlementDraft: Identifiable {
    var id = UUID()
    var tier = ""
    var validity = "待确认"
    var expiryText = ""
    var note = ""
    var quote: CatalogOffer? = nil
    var importOrigin: ImportOrigin? = nil
    init() {}
    init(_ entitlement: Entitlement) {
        id = entitlement.id
        tier = entitlement.tier
        validity = entitlement.perpetual ? "永久授权" : entitlement.expires == nil ? "待确认" : "有到期日"
        expiryText = entitlement.expires ?? ""
        note = entitlement.note
        quote = entitlement.quote
        importOrigin = entitlement.importOrigin
    }
    var isValid: Bool {
        !tier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (validity != "有到期日" || ServiceDate.parse(expiryText) != nil)
    }
    var value: Entitlement {
        Entitlement(id: id, tier: tier.trimmingCharacters(in: .whitespacesAndNewlines),
                    expires: validity == "有到期日" ? expiryText : nil, note: note, perpetual: validity == "永久授权",
                    quote: quote?.name == tier.trimmingCharacters(in: .whitespacesAndNewlines) ? quote : nil,
                    importOrigin: importOrigin)
    }
    mutating func apply(_ offer: CatalogOffer, start: String) {
        tier = offer.name
        quote = offer
        if offer.duration.perpetual { validity = "永久授权"; expiryText = "" }
        else if let expiry = offer.duration.expiry(start: start) { validity = "有到期日"; expiryText = expiry }
        else { validity = "待确认"; expiryText = "" }
        note = "套餐默认：\(offer.duration.label)；按起算日\(start)预填，实际有效期需确认。\(offer.specs) \(offer.badge)"
    }
}
