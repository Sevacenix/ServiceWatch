import SwiftUI

struct OffersView: View {
    @Bindable var store: DemoStore
    private var catalog: CatalogStore { store.catalog }
    private var products: [CatalogProduct] {
        catalog.filteredProducts
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    PageHeading(title: tr("优惠发现"), subtitle: tr("真实目录 · 等级、方案与渠道分别报价。"))
                    Link(destination: CatalogSource.base) {
                        Label(tr("打开有好价首页"), systemImage: "arrow.up.right.square")
                    }.buttonStyle(.bordered)
                }
                HStack {
                    TextField(tr("搜索全部服务"), text: Binding(get: { catalog.search }, set: { catalog.search = $0 })).frame(maxWidth: 350)
                    Spacer()
                    Text(tr("显示\(products.count)/\(catalog.products.count)项 · \(catalog.visibleOfferCount)个方案/渠道")).font(.caption).foregroundStyle(.secondary)
                    Button(tr("刷新全部最新价格")) { Task { await catalog.refreshAll(.manual) } }.disabled(catalog.isUpdating)
                }
                HStack {
                    Picker(tr("分类"), selection: Binding(get: { catalog.categoryFilter }, set: { catalog.categoryFilter = $0 })) {
                        Text(tr("全部分类（\(catalog.products.count)）")).tag("")
                        ForEach(CatalogCategory.ordered, id: \.id) { category in
                            let count = catalog.products.filter { CatalogCategory.key($0.category) == category.id }.count
                            if count > 0 { Text("\(L10n.label(category.title)) (\(count))").tag(category.id) }
                        }
                    }.frame(width: 260)
                    if !catalog.categoryFilter.isEmpty || !catalog.search.isEmpty {
                        Button(tr("清除筛选")) { catalog.categoryFilter = ""; catalog.search = "" }.controlSize(.small)
                    }
                    Spacer()
                }
                CatalogStatusView(catalog: catalog)
                ForEach(products) { product in
                    Surface(title: product.name, iconSources: product.iconURLs ?? [], iconStore: catalog.icons) {
                        HStack {
                            Text(L10n.label(CatalogCategory.title(product.category)) + " · " + (product.kind == "bundle" ? tr("联名套餐，各项时长分别核实") : product.kind == "app" ? tr("软件授权") : tr("会员服务"))).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(tr("刷新最新价格")) { Task { await catalog.verify(product.path) } }
                                .disabled(catalog.refreshingPaths.contains(product.path))
                            Link(tr("来源"), destination: product.sourceURL)
                        }
                        if let error = product.lastError { Text(tr("更新失败，以下为上次成功数据：\(error)")).font(.caption).foregroundStyle(.orange) }
                        let offers = catalog.offers(product.path)
                        if offers.isEmpty { Text(tr("尚无核实后的具体方案，请刷新。")).font(.caption).foregroundStyle(.secondary) }
                        ForEach(offers) { offer in
                            CatalogOfferRow(offer: offer) { store.comparePrice(offer) }
                            if offer.id != offers.last?.id { Divider() }
                        }
                    }
                }
                if products.isEmpty && !catalog.isUpdating {
                    ContentUnavailableView(tr("暂无匹配服务"), systemImage: "magnifyingglass", description: Text(catalog.products.isEmpty ? tr("可更新完整目录，或在添加窗口手动录入。") : tr("当前分类与关键词没有匹配结果，可清除筛选。")))
                }
            }.padding(28).frame(maxWidth: 1150, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}

struct CatalogOfferRow: View {
    let offer: CatalogOffer
    let compare: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(offer.name).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Text("\(L10n.label(offer.shop)) · \(offer.duration.displayLabel)").font(.caption).foregroundStyle(.secondary)
                if !offer.specs.isEmpty || !offer.badge.isEmpty {
                    Text([offer.specs, offer.badge].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                Text(tr("校验于 \(L10n.dateTime(offer.observedAt))")).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 9) {
                Text(offer.displayPrice).font(.system(size: 19, weight: .semibold, design: .rounded))
                HStack(spacing: 8) {
                    Button(tr("比价记录"), action: compare)
                    Link(tr("前往购买"), destination: offer.purchaseURL)
                }.buttonStyle(.bordered).controlSize(.small)
            }
        }.padding(.vertical, 5)
    }
}

struct CatalogStatusView: View {
    @Bindable var catalog: CatalogStore
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if catalog.isUpdating { ProgressView(L10n.label(catalog.progress)).controlSize(.small) }
            if let error = catalog.error { Text(error).foregroundStyle(.orange) }
            Text(L10n.label(catalog.outcome)).foregroundStyle(.secondary)
            Text(tr("手动刷新与添加时校验不占每日额度；每次成功校验均入库并保留历史。价格以商家结算为准。"))
                .foregroundStyle(.secondary)
        }.font(.caption)
    }
}
