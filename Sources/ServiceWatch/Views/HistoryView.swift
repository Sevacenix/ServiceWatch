import SwiftUI
import Charts

struct HistoryView: View {
    @Bindable var store: DemoStore
    @State private var loaded: Loaded?
    @State private var year = PriceCalendar.year(Date())

    private struct Request: Equatable {
        let key: String
        let revision: Int64
        let day: String
    }
    private struct Loaded {
        let request: Request
        let result: Result<PriceComparison, Error>
    }

    private var catalog: CatalogStore { store.catalog }
    private var groups: [CatalogOffer] {
        var seen: Set<String> = []
        let path = catalog.comparisonProductPath
        let choices = catalog.offers(path) + catalog.snapshot.historyGroups.filter { $0.productPath == path }
        return choices.filter { seen.insert($0.comparisonKey).inserted }
    }
    private var selection: String {
        let key = catalog.comparisonOfferKey
        return groups.contains { $0.comparisonKey == key } ? key : groups.first?.comparisonKey ?? ""
    }
    private var selected: CatalogOffer? { groups.first { $0.comparisonKey == selection } }
    private var request: Request {
        .init(key: selection, revision: catalog.snapshot.historyRevision, day: ServiceDate.string(Date()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    PageHeading(title: "价格历史", subtitle: "按同一方案和渠道比较：全历史、年度低点和大促观测。")
                    Link("打开有好价首页", destination: CatalogSource.base)
                }
                Picker("服务", selection: Binding(get: { catalog.comparisonProductPath }, set: {
                    catalog.comparisonProductPath = $0
                    catalog.comparisonOfferKey = ""
                })) {
                    Text("请选择服务").tag("")
                    ForEach(catalog.snapshot.products) { Text($0.name).tag($0.path) }
                }
                Picker("具体方案与渠道", selection: Binding(get: { selection }, set: { catalog.comparisonOfferKey = $0 })) {
                    if groups.isEmpty { Text("暂无方案记录").tag("") }
                    ForEach(groups, id: \.comparisonKey) { Text($0.selectorLabel).tag($0.comparisonKey) }
                }
                if let selected {
                    let product = catalog.snapshot.products.first { $0.path == selected.productPath }
                    let current = product?.listed == true ? catalog.offers(selected.productPath).first {
                        $0.comparisonKey == selected.comparisonKey
                    } : nil
                    comparisonHeader(selected, current: current, product: product)
                    if let loaded, loaded.request == request {
                        switch loaded.result {
                        case .success(let comparison):
                            PriceComparisonPanel(comparison: comparison, current: current, product: product,
                                                 currency: selected.currency, year: $year)
                            historyChart(comparison.chart)
                        case .failure(let error):
                            Text("无法读取价格历史：\(error.localizedDescription)").foregroundStyle(.orange)
                        }
                    } else { ProgressView("正在读取完整价格记录…").controlSize(.small) }
                } else {
                    ContentUnavailableView("选择已入库的具体方案", systemImage: "chart.xyaxis.line",
                                           description: Text("每天自动更新与手动校验都会留下观察记录。"))
                }
            }.padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onChange(of: catalog.snapshot.historyGroups.first?.productPath, initial: true) { _, path in
            if catalog.comparisonProductPath.isEmpty { catalog.comparisonProductPath = path ?? "" }
        }
        .task(id: request) {
            guard let selected else { loaded = nil; return }
            let query = request
            do {
                let comparison = try await catalog.comparison(for: selected)
                guard !Task.isCancelled else { return }
                if comparison.years[year] == nil && year != PriceCalendar.year(Date()) { year = PriceCalendar.year(Date()) }
                loaded = .init(request: query, result: .success(comparison))
            } catch {
                if !Task.isCancelled { loaded = .init(request: query, result: .failure(error)) }
            }
        }
    }

    private func comparisonHeader(_ selected: CatalogOffer, current: CatalogOffer?, product: CatalogProduct?) -> some View {
        Surface(title: selected.name, iconSources: product?.iconURLs ?? [], iconStore: catalog.icons) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.map { $0.price == nil ? "当前价格待更新" : "最新报价：\($0.priceLabel)" } ?? "该方案当前未列出")
                        .font(.title2.bold())
                    Text("\(selected.shop) · \(selected.duration.label) · \(selected.currency)").font(.caption).foregroundStyle(.secondary)
                    if let current {
                        Text("报价校验：\(current.observedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let issue = product?.lastError {
                        Text("上次刷新失败，保留旧报价：\(issue)").font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                if product?.listed == true {
                    Button("刷新该服务价格") { Task { await catalog.verify(selected.productPath) } }
                        .disabled(catalog.refreshingPaths.contains(selected.productPath))
                }
                if let current, current.price != nil {
                    Link("查看商家报价", destination: current.purchaseURL)
                }
            }
        }
    }

    private func historyChart(_ observations: [OfferObservation]) -> some View {
        Surface(title: "最近观察 · 最多 200 条") {
            if observations.contains(where: { $0.quote.price != nil }) {
                Chart(observations.reversed()) { observation in
                    if let price = observation.quote.decimalPrice {
                        LineMark(x: .value("时间", observation.quote.observedAt), y: .value("价格", price))
                        PointMark(x: .value("时间", observation.quote.observedAt), y: .value("价格", price))
                    }
                }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 190)
            }
            DisclosureGroup("查看观察明细（\(observations.count) 条）") {
                ForEach(observations) { observation in
                    HStack {
                        Text(observation.quote.observedAt, format: .dateTime.year().month().day().hour().minute().second()).monospacedDigit()
                        Spacer()
                        Text(observation.quote.priceLabel).fontWeight(.medium)
                        Text(observation.notModified ? "304 · 内容未变" : "200 · 页面核实").foregroundStyle(.secondary)
                    }.font(.caption)
                    Divider()
                }
            }
            Text("图表和明细有展示上限；最低价使用全部可比记录。没有采样的日期不补写。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PriceComparisonPanel: View {
    let comparison: PriceComparison
    let current: CatalogOffer?
    let product: CatalogProduct?
    let currency: String
    @Binding var year: Int

    private var now: Date { Date() }
    private var currentPoint: PricePoint? {
        current.flatMap { PricePoint(price: $0.price, at: $0.observedAt) }
    }
    private var stale: Bool {
        guard let current else { return false }
        return product?.lastError != nil || ServiceDate.string(current.observedAt) != ServiceDate.string(now)
    }

    var body: some View {
        let annual = comparison.years[year] ?? PriceYear()
        Surface(title: "比价参考 · 同方案、同渠道、同币种") {
            Label(decision, systemImage: "chart.bar.xaxis").font(.callout.weight(.medium))
            if let start = comparison.firstSample {
                Text("本方案可比记录始于 \(ServiceDate.string(start))。历史最低指本机采到的最低报价。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            reference("历史最低", low: comparison.historical)
            Divider()
            Picker("比较年度", selection: $year) {
                ForEach(Set(comparison.years.keys).union([PriceCalendar.year(now)]).sorted(by: >), id: \.self) {
                    Text("\($0) 年").tag($0)
                }
            }.frame(maxWidth: 250)
            reference(year == PriceCalendar.year(now) ? "今年最低" : "\(year) 年最低", low: annual.low)
            Divider()
            ForEach(PriceEvent.allCases) { event in
                reference(event.rawValue, low: annual.events[event] ?? PriceLow(), window: event.window(year: year))
            }
            Text("差额＝最新报价减参考价；百分比以参考价为基准。活动按北京时间的固定窗口统计，只代表已采到的报价。实际购买以结算页为准。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var decision: String {
        guard current != nil else { return "暂无当前可售报价，可查看历史参考。" }
        guard let currentPoint else { return "等待最新报价，暂不判断价格位置。" }
        if stale { return "当前为缓存报价，购买前建议刷新核实。" }
        guard let low = comparison.historical.point else { return "可比观测不足，暂无法判断价格位置。" }
        if currentPoint.amount == low.amount {
            return comparison.historical.sampledDays < 2 ?
                "最新价为首日观测低点，尚无跨日对照。" : "最新价达到本机记录的历史最低。"
        }
        if currentPoint.amount < low.amount { return "最新报价低于已读到的历史最低，请刷新确认。" }
        let gap = PriceDelta(current: currentPoint, reference: low).description
        return "最新价比历史最低高 \(gap.replacingOccurrences(of: "+", with: ""))。不急用时可等回落。"
    }

    private func reference(_ title: String, low: PriceLow, window: Range<Date>? = nil) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                if let window {
                    Text(PriceCalendar.label(window)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let point = low.point {
                    Text("\(currency) \(point.label)").font(.subheadline.monospacedDigit())
                    Text("\(ServiceDate.string(point.observedAt)) · \(low.sampledDays) 天有报价")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(window.map { now < $0.lowerBound } == true ? "活动未开始" : "暂无采样")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Group {
                if let currentPoint, let reference = low.point {
                    let delta = PriceDelta(current: currentPoint, reference: reference)
                    Text(delta.description).foregroundStyle(stale ? Color.secondary : delta.amount > 0 ? .orange : .primary)
                } else { Text("—").foregroundStyle(.secondary) }
            }.font(.caption.monospacedDigit()).frame(minWidth: 120, alignment: .trailing)
        }
    }
}
