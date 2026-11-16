import SwiftUI

struct CatalogSelectionView: View {
    @Bindable var catalog: CatalogStore
    @Binding var productPath: String
    var lockedProduct: Bool
    var onSelection: (CatalogOffer?) -> Void
    @State private var search = ""
    @State private var offerID = ""
    @State private var quotes: [CatalogOffer] = []
    @State private var verified = false
    @State private var loading = false
    @State private var issue: String?
    private var choices: [CatalogProduct] {
        catalog.products.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path == productPath }
    }
    private var selected: CatalogOffer? { quotes.first { $0.id == offerID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if lockedProduct {
                productLabel
            } else {
                TextField(tr("搜索目录服务"), text: $search, prompt: Text(tr("在有好价的全部服务中搜索")))
                Picker(tr("服务目录"), selection: $productPath) {
                    Text(tr("请选择服务（也可直接手动录入）")).tag("")
                    ForEach(choices) { Text($0.name + ($0.kind == "bundle" ? tr(" · 联名") : "")).tag($0.path) }
                }
                if !productPath.isEmpty { productLabel }
            }
            HStack {
                Text(tr("\(catalog.products.count)项目录 · 有好价")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(tr("更新全部目录")) { Task { await catalog.refreshDirectory() } }.disabled(catalog.isUpdating)
            }
            if loading { ProgressView(tr("正在联网核实当前方案…")).controlSize(.small) }
            if let issue { Text(issue + tr(" 未将缓存价格应用为新默认值。")).font(.caption).foregroundStyle(.orange) }
            if !quotes.isEmpty {
                Picker(tr("等级 / 套餐 / 渠道"), selection: $offerID) {
                    ForEach(quotes) { Text($0.displaySelector).tag($0.id) }
                }.disabled(!verified)
                if let selected {
                    Text(selected.name).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    HStack { Text(tr("默认优惠价：\(selected.displayPrice)")).fontWeight(.semibold); Spacer(); Text(selected.duration.displayLabel) }
                    if !selected.specs.isEmpty || !selected.badge.isEmpty {
                        Text([selected.specs, selected.badge].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(verified ? tr("本次已联网校验") : tr("缓存，未完成本次校验")) · \(L10n.dateTime(selected.observedAt))")
                        .font(.caption).foregroundStyle(verified ? Color.secondary : .orange)
                    HStack {
                        Link(tr("优惠来源"), destination: selected.sourceURL)
                        Link(tr("前往购买"), destination: selected.purchaseURL)
                        Spacer()
                        Button(tr("刷新最新价格")) { Task { await verify(.manual) } }.disabled(loading)
                    }
                }
            } else if !productPath.isEmpty && !loading {
                Button(tr("刷新最新价格")) { Task { await verify(.manual) } }
            }
            Text(tr("默认值来自具体方案，非页面最低价；不代表已购买或账号结算价。网站未收录的服务仍可手动添加。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: productPath) {
            if !productPath.isEmpty && !Task.isCancelled { await verify(.adding) }
        }
        .onChange(of: offerID) { _, _ in if verified, let selected { onSelection(selected) } }
    }
    private var productLabel: some View {
        HStack {
            BrandIconView(sources: catalog.products.first { $0.path == productPath }?.iconURLs ?? [], store: catalog.icons)
            Text(catalog.products.first { $0.path == productPath }?.name ?? productPath).fontWeight(.medium)
        }
    }
    private func verify(_ trigger: CatalogTrigger) async {
        let path = productPath
        guard !path.isEmpty else { quotes = []; verified = false; return }
        loading = true; verified = false; issue = nil; onSelection(nil)
        quotes = catalog.offers(path)
        let result = await catalog.verify(path, trigger: trigger)
        guard !Task.isCancelled, productPath == path else { return }
        loading = false
        if let result {
            quotes = result; verified = true
            offerID = result.contains(where: { $0.id == offerID }) ? offerID : result.first?.id ?? ""
            if let selected { onSelection(selected) }
        } else { issue = catalog.error ?? tr("本次校验尚未完成，请刷新重试。") }
    }
}
