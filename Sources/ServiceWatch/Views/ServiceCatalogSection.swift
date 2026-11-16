import SwiftUI

struct ServiceCatalogSection: View {
    let service: Service
    @Bindable var catalog: CatalogStore
    @State private var refreshIssue: String?
    var body: some View {
        if let path = service.offerPath {
            Surface(title: "当前优惠 · 按等级与方案") {
                Button(catalog.refreshingPaths.contains(path) ? "正在校验…" : "刷新最新价格") {
                    Task {
                        refreshIssue = nil
                        if await catalog.verify(path) == nil { refreshIssue = catalog.error ?? "本次核实尚未完成，请稍后再试。" }
                    }
                }
                    .disabled(catalog.refreshingPaths.contains(path))
                if let refreshIssue { Text(refreshIssue).font(.caption).foregroundStyle(.orange) }
                if let time = catalog.snapshot.products.first(where: { $0.path == path })?.lastVerified {
                    Text("页面核实于 \(time.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let issue = catalog.snapshot.products.first(where: { $0.path == path })?.lastError {
                    Text("更新失败，保留旧报价：\(issue)").font(.caption).foregroundStyle(.orange)
                }
                ForEach(service.entitlements.filter { $0.quote != nil }) { entitlement in
                    if let quote = entitlement.quote {
                        Text("已记录套餐：\(quote.name)").font(.caption.weight(.medium))
                        if let current = catalog.matching(quote) { Text("同方案最新价：\(current.priceLabel)").font(.caption) }
                        else { Text("原套餐快照：\(quote.priceLabel)，当前方案需重新核实。").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                let offers = catalog.offers(path)
                ForEach(Array(offers.prefix(4))) { offer in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(offer.name).font(.system(size: 11, weight: .medium))
                        Text("\(offer.priceLabel) · \(offer.shop) · \(offer.duration.label)").font(.system(size: 10)).foregroundStyle(.secondary)
                        Link("前往购买此方案", destination: offer.purchaseURL).font(.caption)
                    }
                    Divider()
                }
                if offers.isEmpty { Text("尚未获取具体方案，可点击刷新。").font(.caption).foregroundStyle(.secondary) }
                Text("各等级分别报价；刷新不会改动你的已有有效期或历史实付。").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
