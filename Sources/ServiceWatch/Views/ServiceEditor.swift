import SwiftUI
import UniformTypeIdentifiers

struct ServiceEditor: View {
    @Bindable var store: DemoStore
    var service: Service?
    @State private var name: String
    @State private var entitlements: [EntitlementDraft]
    @State private var channel: String
    @State private var method: String
    @State private var cycle: String
    @State private var amount: String
    @State private var currency: String
    @State private var site: String
    @State private var active: Bool
    @State private var saveError: String? = nil
    @State private var catalogPath: String
    @State private var selectedQuote: CatalogOffer? = nil
    @State private var startDate = ServiceDate.string(ServiceDate.today)
    @State private var customIconName: String?
    @State private var importedIconData: Data? = nil
    @State private var importedIconPreview: NSImage? = nil
    @State private var showingIconImporter = false
    private let originalIDs: Set<UUID>
    private let initialFocus: UUID?
    private var quoteMatchesDraft: Bool {
        guard let selectedQuote else { return false }
        return entitlements.contains { $0.quote?.id == selectedQuote.id && $0.tier == selectedQuote.name }
    }

    init(store: DemoStore, service: Service?) {
        self.store = store
        self.service = service
        var drafts = (service?.entitlements ?? []).map(EntitlementDraft.init)
        if service == nil || store.addingEntitlement { drafts.append(EntitlementDraft()) }
        _name = State(initialValue: service?.name ?? "")
        _entitlements = State(initialValue: drafts)
        originalIDs = Set(service?.entitlements.map(\.id) ?? [])
        initialFocus = store.addingEntitlement ? drafts.last?.id : store.editingEntitlementID
        _channel = State(initialValue: service?.channel ?? "")
        _method = State(initialValue: service?.method ?? "待核实")
        _cycle = State(initialValue: service?.billingCycle ?? "待核实")
        _amount = State(initialValue: service?.paidAmount ?? "")
        _currency = State(initialValue: service?.currency ?? "CNY")
        _site = State(initialValue: service?.customURL ?? "")
        _active = State(initialValue: service?.paid ?? false)
        _catalogPath = State(initialValue: service?.offerPath ?? "")
        _customIconName = State(initialValue: service?.customIcon)
    }
    private var valid: Bool {
        guard store.storageIssue == nil, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              entitlements.allSatisfy(\.isValid), !active || !entitlements.isEmpty else { return false }
        if service == nil && !catalogPath.isEmpty && selectedQuote?.productPath != catalogPath { return false }
        if !amount.isEmpty {
            guard let parsed = Double(amount), parsed.isFinite, parsed >= 0 else { return false }
        }
        if !site.isEmpty {
            guard let url = URL(string: site), ["https", "http"].contains(url.scheme), url.host != nil else { return false }
        }
        return true
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(service == nil ? "添加服务与授权" : "编辑服务与授权").font(.title2.bold())
                Spacer()
                Pill(text: service?.example == true ? "示例 · 不写入个人台账" : "保存到本机", color: .teal)
            }.padding(22)
            Divider()
            ScrollViewReader { reader in
                Form {
                    Section("优惠目录 · 添加时即时核实") {
                        CatalogSelectionView(catalog: store.catalog, productPath: $catalogPath, lockedProduct: service?.offerPath != nil) { offer in
                            selectedQuote = offer
                            if let offer, service == nil || store.addingEntitlement { apply(offer) }
                        }
                        if let selectedQuote {
                            TextField("授权起算日", text: $startDate, prompt: Text("YYYY-MM-DD"))
                            if ServiceDate.parse(startDate) == nil {
                                Text("起算日需为有效日期；不会按无效日期推算。").font(.caption).foregroundStyle(.orange)
                            }
                            Button(service == nil || store.addingEntitlement ? "按此方案与起算日重新填入默认值" : "将此方案填入当前授权草稿") {
                                apply(selectedQuote)
                            }.disabled(ServiceDate.parse(startDate) == nil)
                            Text("到期日按套餐时长预填，仍可逐条修改；续费顺延规则与起算日需由你确认。已有授权只在点击填入后改动草稿。")
                                .font(.caption).foregroundStyle(.secondary)
                            if !quoteMatchesDraft {
                                Text("所选套餐尚未应用，或等级已手动改为自定义；报价仅对应上方原方案，不会自动附到其它等级。")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    Section("服务") {
                        HStack(spacing: 12) {
                            if let importedIconPreview {
                                Image(nsImage: importedIconPreview).resizable().scaledToFit().frame(width: 36, height: 36)
                            } else {
                                BrandIconView(sources: store.catalog.snapshot.products.first { $0.path == catalogPath }?.iconURLs ?? service.map { store.catalog.iconSources(for: $0) } ?? [], customIcon: customIconName, store: store.catalog.icons, size: 36)
                            }
                            Button("导入服务图标…") { showingIconImporter = true }
                            if customIconName != nil || importedIconData != nil {
                                Button("使用默认图标") { customIconName = nil; importedIconData = nil; importedIconPreview = nil }
                            }
                            Spacer()
                        }
                        Text("优先使用服务真实图标；网站未收录的自定义服务可导入本地图片，保存后生效。")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("服务名称", text: $name, prompt: Text("例如 Parallels Desktop"))
                        Toggle("当前已开通", isOn: $active)
                    }
                    ForEach($entitlements) { $draft in
                        Section {
                            EntitlementEditorRow(draft: $draft)
                            HStack {
                                if entitlements.first?.id == draft.id { Pill(text: "主要授权 · 列表展示", color: .blue) }
                                else {
                                    Button("设为主要授权") {
                                        if let index = entitlements.firstIndex(where: { $0.id == draft.id }) {
                                            entitlements.insert(entitlements.remove(at: index), at: 0)
                                        }
                                    }.font(.caption)
                                }
                                Spacer()
                                if !originalIDs.contains(draft.id) {
                                    Button("撤销新增") { entitlements.removeAll { $0.id == draft.id } }.font(.caption)
                                }
                            }
                        } header: {
                            Text(draft.tier.isEmpty ? "新增授权 / 自定义等级" : draft.tier)
                        }.id(draft.id)
                    }
                    Section {
                        Button {
                            let draft = EntitlementDraft()
                            entitlements.append(draft)
                            withAnimation { reader.scrollTo(draft.id, anchor: .center) }
                        } label: { Label("添加授权 / 自定义等级", systemImage: "plus.circle") }
                        Text("每条等级分别保存日期；修改一项不会推算或覆盖其他等级的日期。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("付费信息 · 未知可以留空") {
                        if let selectedQuote, quoteMatchesDraft {
                            Text("所选套餐默认参考：\(selectedQuote.priceLabel)").font(.caption)
                            if let price = selectedQuote.price {
                                Button("我已确认实付相同，填入报价金额") { amount = price; currency = selectedQuote.currency }
                            }
                            Text("参考价不会自动记为历史实付；实际支付不同可在下方修改。").font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("购买渠道", text: $channel)
                        TextField("付费方式", text: $method, prompt: Text("苹果支付 / 微信 / 信用卡…"))
                        TextField("付费周期", text: $cycle, prompt: Text("月付 / 年付 / 一次性…"))
                        HStack {
                            TextField("实付金额", text: $amount, prompt: Text("留空表示未知"))
                            Picker("币种", selection: $currency) { Text("CNY").tag("CNY"); Text("USD").tag("USD"); Text("EUR").tag("EUR") }.frame(width: 120)
                        }
                        TextField("购买 / 官网链接", text: $site, prompt: Text("https://…"))
                    }
                }.formStyle(.grouped)
                    .onAppear { if let initialFocus { reader.scrollTo(initialFocus, anchor: .top) } }
            }
            Divider()
            HStack {
                Text("本机保存，重启保留；取消不会修改原数据。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { store.showingEditor = false }.keyboardShortcut(.cancelAction)
                Button("保存修改") { save() }.buttonStyle(.borderedProminent).disabled(!valid)
            }.padding(20)
        }.frame(width: 700, height: 740)
            .fileImporter(isPresented: $showingIconImporter, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else { throw CatalogError.invalid("请选择2MB以内的图标图片。") }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard let preview = BrandIconStore.decode(data) else { throw CatalogError.invalid("请选择2MB以内、可读取的图标图片。") }
                    importedIconData = data; importedIconPreview = preview; customIconName = nil
                } catch { saveError = error.localizedDescription }
            }
            .alert("未能完成操作", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("知道了") { saveError = nil }
            } message: { Text(saveError ?? "") }
    }
    private func apply(_ offer: CatalogOffer) {
        guard ServiceDate.parse(startDate) != nil else { return }
        let index = entitlements.firstIndex(where: { $0.id == initialFocus }) ?? 0
        if entitlements.isEmpty { entitlements.append(EntitlementDraft()) }
        entitlements[min(index, entitlements.count - 1)].apply(offer, start: startDate)
        if service == nil {
            name = offer.productName
            channel = offer.shop
            cycle = offer.duration.perpetual ? "一次性买断" : offer.unit
            currency = offer.currency
            site = offer.purchaseURL.absoluteString
        }
    }
    private func save() {
        var value = service ?? Service(id: (store.services.map(\.id).max() ?? 0) + 1, name: name, category: "自定义服务", symbol: "key.horizontal.fill", tint: .teal, paid: active, entitlements: [], evidence: "手动录入")
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.paid = active
        value.channel = channel.isEmpty ? "待核实" : channel
        value.method = method.isEmpty ? "待核实" : method
        value.billingCycle = cycle.isEmpty ? "待核实" : cycle
        value.paidAmount = amount.isEmpty ? nil : amount
        value.currency = currency
        value.customURL = site.isEmpty ? nil : site
        value.entitlements = entitlements.map { draft in
            var entitlement = draft.value
            if let before = service?.entitlements.first(where: { $0.id == entitlement.id }),
               before.tier != entitlement.tier || before.expires != entitlement.expires || before.perpetual != entitlement.perpetual {
                entitlement.importOrigin = nil
            }
            return entitlement
        }
        if value.entitlements.contains(where: { $0.quote?.productPath == catalogPath }) {
            value.offerPath = catalogPath
            if service == nil {
                value.category = catalogPath.hasPrefix("/app/") ? "软件授权" : catalogPath.hasPrefix("/bundle/") ? "联名会员" : "会员服务"
                value.symbol = catalogPath.hasPrefix("/app/") ? "desktopcomputer" : "key.horizontal.fill"
            }
        }
        value.evidence = "手动确认 · \(ServiceDate.string(Date()))"
        value.customIcon = customIconName
        do {
            if let importedIconData { value.customIcon = try store.catalog.icons.saveCustom(importedIconData) }
            try store.save(value)
            store.destination = .services
            store.showingEditor = false
        } catch { saveError = error.localizedDescription }
    }
}
