import SwiftUI

struct ServiceDetail: View {
    var service: Service
    @Bindable var store: DemoStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    ServiceIcon(service: service, catalog: store.catalog, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.name).font(.system(size: 20, weight: .bold))
                        Text(L10n.label(service.category)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.edit(service) } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.borderless)
                }
                if service.example {
                    Label(tr("示例授权，不是你的实际有效期"), systemImage: "flask")
                        .font(.caption).foregroundStyle(.purple)
                }
                Surface(title: tr("权益有效期")) {
                    Button { store.edit(service, adding: true) } label: {
                        Label(tr("添加授权 / 自定义等级"), systemImage: "plus.circle")
                    }.buttonStyle(.borderless).font(.caption)
                    if service.entitlements.isEmpty {
                        Text(tr("尚未开通付费权益")).foregroundStyle(.secondary)
                        Text(tr("可以先记录关注等级与报价，购买后再补充授权。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(service.entitlements) { entitlement in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(service.color).frame(width: 7, height: 7).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    Text(entitlement.tier).font(.system(size: 12, weight: .semibold))
                                    Spacer(minLength: 6)
                                    Button(tr("修改")) { store.edit(service, entitlementID: entitlement.id) }
                                        .buttonStyle(.borderless).font(.caption)
                                        .accessibilityLabel(tr("修改\(entitlement.tier)授权"))
                                }
                                Text(entitlement.perpetual ? tr("永久 · 当前版本") : entitlement.expires ?? tr("到期时间待确认"))
                                    .font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
                                if !entitlement.note.isEmpty {
                                    Text(entitlement.note).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                if let origin = entitlement.importOrigin {
                                    Text(tr("\(L10n.label(origin.rawValue)) · 已核对")).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if entitlement.id != service.entitlements.last?.id { Divider() }
                    }
                }
                if let plan = service.renewalPlan {
                    RenewalPlanCard(service: service, plan: plan, store: store)
                } else {
                    Button(tr("添加自动扣款计划…")) { store.manageRenewal(service) }.font(.caption)
                }
                Surface(title: tr("付费与凭据")) {
                    Fact(title: tr("购买渠道"), value: L10n.label(service.channel))
                    Fact(title: tr("付费方式"), value: L10n.label(service.method))
                    Fact(title: tr("付费周期"), value: L10n.label(service.billingCycle))
                    Fact(title: tr("自动扣款"), value: service.renewalPlan?.summary(language: .current) ?? tr("未记录计划"))
                    Fact(title: tr("历史实付"), value: service.paidAmount.map { service.currency + " " + $0 } ?? tr("未提供金额"))
                    Divider()
                    Label(service.evidence, systemImage: "doc.viewfinder")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                let recentChanges = store.changes.filter { $0.after.id == service.id }.suffix(3).reversed()
                if !recentChanges.isEmpty {
                    Surface(title: tr("最近修改记录")) {
                        ForEach(Array(recentChanges)) { change in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(change.recordedAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(change.summary(language: .current)).font(.system(size: 11)).textSelection(.enabled)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 11) {
                    Text(tr("优惠与续费")).font(.system(size: 13, weight: .semibold))
                    if let path = service.offerPath {
                        Text(service.paid ? tr("已有权益，无需因折扣提前续同档。") : tr("开通前，先比等级、设备与赠送时长。"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        ExternalOfferLink(path: path).buttonStyle(.borderedProminent).controlSize(.small)
                        Text(tr("打开有好价最新页面；最终价格以商家结算为准。"))
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    } else if let text = service.customURL, let url = URL(string: text) {
                        Link(destination: url) { Label(tr("查看自定义站点"), systemImage: "arrow.up.right") }
                    } else {
                        Text(tr("未关联优惠站点。可自行添加官网或购买链接。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ServiceCatalogSection(service: service, catalog: store.catalog)
            }.padding(22)
        }.background(.quinary.opacity(0.35))
    }
}
