import SwiftUI

struct ContentView: View {
    @Bindable var store: DemoStore
    @Binding var language: AppLanguage
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if let icon = AppBuildInfo.icon {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("续期")).font(.system(size: 18, weight: .bold))
                        Text(tr("服务与软件授权")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20).padding(.top, 7)
                List(selection: $store.destination) {
                    Section(tr("我的服务")) {
                        ForEach([Destination.services, .offers, .history]) { page in
                            Label(L10n.label(page.rawValue), systemImage: page.symbol).tag(page)
                        }
                    }
                    Section(tr("管理")) {
                        ForEach([Destination.inbox, .sources, .guide]) { page in
                            Label(L10n.label(page.rawValue), systemImage: page.symbol).tag(page)
                        }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("本地数据，自己掌握"), systemImage: "internaldrive")
                    Text(store.isTestData ? tr("隔离测试数据\n不影响个人授权记录") : tr("授权与优惠保存在本机\n邮件与截图由本机识别"))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                }.font(.system(size: 11)).padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            Group {
                switch store.destination ?? .services {
                case .services: ServicesView(store: store)
                case .offers: OffersView(store: store)
                case .history: HistoryView(store: store)
                case .inbox: ImportView(store: store, inSheet: false)
                case .sources: SourceView(store: store)
                case .guide: GuideView(store: store)
                }
            }
            .navigationTitle(tr("续期 · 服务与授权"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text(tr("本地授权管理")).font(.caption).foregroundStyle(.secondary)
                        if let channel = AppBuildInfo.releaseChannel { Pill(text: channel, color: .teal) }
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker(tr("语言"), selection: $language) {
                            ForEach(AppLanguage.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }.pickerStyle(.inline)
                    } label: {
                        Label(tr("语言"), systemImage: "globe")
                    }.help(tr("语言"))
                    Button { store.showingImport = true } label: { Label(tr("导入授权"), systemImage: "doc.viewfinder") }
                    Button { store.edit(nil) } label: { Label(tr("添加服务"), systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $store.showingImport) {
            ImportView(store: store, inSheet: true).frame(width: 880, height: 680)
        }
        .sheet(isPresented: $store.showingEditor) {
            ServiceEditor(store: store, service: store.services.first { $0.id == store.editingID })
        }
        .sheet(isPresented: $store.showingRenewalManager) {
            if let service = store.services.first(where: { $0.id == store.renewalServiceID }) {
                RenewalManager(store: store, service: service)
            }
        }
        .alert(tr("提示"), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button(tr("知道了")) { store.message = nil }
        } message: { Text(store.message ?? "") }
        .task { await store.catalog.start() }
    }
}

struct ServicesView: View {
    @Bindable var store: DemoStore
    var body: some View {
        if store.services.isEmpty && store.storageIssue == nil {
            ContentUnavailableView {
                Label(tr("还没有服务记录"), systemImage: "square.stack.3d.up")
            } description: {
                Text(tr("添加你的第一项订阅或软件授权，也可以先看看使用向导。"))
            } actions: {
                Button(tr("添加服务")) { store.edit(nil) }.buttonStyle(.borderedProminent)
                Button(tr("查看使用向导")) { store.destination = .guide }
            }
        } else {
            serviceList
        }
    }
    private var serviceList: some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeading(title: tr("服务与授权"), subtitle: tr("有效期、自动扣款与优惠，各自清楚。"))
                    HStack(spacing: 0) {
                        metric(tr("已开通"), value: "\(store.services.filter { $0.paid && !$0.example }.count)", note: tr("\(store.services.filter { !$0.example }.count) 项真实服务范围"), color: .primary)
                        Divider().frame(height: 44)
                        metric(tr("30 天内到期"), value: "\(store.expiringSoonCount)", note: store.expiryNote(language: .current), color: store.expiringSoonCount == 0 ? .green : .orange)
                        Divider().frame(height: 44)
                        metric(tr("待核实扣款"), value: "\(store.pendingRenewalCount)", note: tr("与会员续费分开管理"), color: .orange)
                    }.padding(.vertical, 3)
                    HStack {
                        Picker(tr("筛选"), selection: $store.filter) {
                            ForEach(["全部", "已开通", "未开通"], id: \.self) { Text(L10n.label($0)) }
                        }.pickerStyle(.segmented).frame(width: 225)
                        Spacer()
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(tr("搜索服务"), text: $store.search).textFieldStyle(.plain).frame(width: 120)
                    }
                }.padding(24)
                HStack {
                    Text(tr("服务 / 当前等级")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(tr("主要授权到期")).frame(width: 105, alignment: .leading)
                    Text(tr("状态")).frame(width: 85, alignment: .trailing)
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 24).padding(.bottom, 9)
                Divider()
                List(selection: $store.selectedID) {
                    ForEach(store.filtered) { service in
                        HStack(spacing: 11) {
                            ServiceIcon(service: service, catalog: store.catalog)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 5) {
                                    Text(service.name).font(.system(size: 12, weight: .semibold))
                                    if service.example { Pill(text: tr("示例"), color: .purple) }
                                }
                                Text(service.entitlements.first?.tier ?? tr("尚未开通"))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.nextExpiry ?? (service.entitlements.first?.perpetual == true ? tr("永久授权") : "—"))
                                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                                if let days = ServiceDate.days(service.nextExpiry) {
                                    Text(days < 0 ? tr("已到期 \(-days) 天") : tr("剩余 \(days) 天")).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }.frame(width: 105, alignment: .leading)
                            Group {
                                if service.renewalPlan?.showsReviewPrompt == true { Pill(text: tr("自动扣款待核实"), color: .orange) }
                                else if service.example { Pill(text: tr("演示授权"), color: .purple) }
                                else if service.paid, let days = ServiceDate.days(service.nextExpiry), days < 0 { Pill(text: tr("主要授权已到期"), color: .orange) }
                                else { Pill(text: service.paid ? tr("已开通") : tr("未开通"), color: service.paid ? .green : .secondary) }
                            }.frame(width: 85, alignment: .trailing)
                        }.padding(.vertical, 8).tag(service.id)
                        .contextMenu { Button(tr("编辑服务…")) { store.edit(service) } }
                    }
                }.listStyle(.inset).overlay {
                    if store.filtered.isEmpty {
                        ContentUnavailableView(tr("未找到结果"), systemImage: "magnifyingglass",
                            description: store.search.isEmpty ? nil : Text(tr("与“\(store.search)”匹配的服务为空")))
                    }
                }
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(tr("授权修改保存在本机"))
                    Spacer()
                    Text(store.isTestData ? tr("隔离测试") : tr("本机保存"))
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(12)
            }.frame(minWidth: 530)
            if let service = store.selectedService {
                ServiceDetail(service: service, store: store).frame(minWidth: 300, idealWidth: 340, maxWidth: 390)
            } else {
                ContentUnavailableView(tr("选择一项服务"), systemImage: "sidebar.right")
                    .frame(minWidth: 300, maxWidth: 390)
            }
        }
    }
    private func metric(_ name: String, value: String, note: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, name == tr("已开通") ? 0 : 20)
    }
}
