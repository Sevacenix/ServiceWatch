import SwiftUI

struct RenewalPlanCard: View {
    var service: Service
    var plan: RenewalPlan
    @Bindable var store: DemoStore
    private var title: String {
        if !plan.isTracked { return tr("自动扣款 · 已停止跟踪") }
        if plan.status == .disabled { return tr("自动扣款 · 已确认关闭") }
        if !plan.remindersEnabled { return tr("自动扣款 · 本地提醒已关闭") }
        return plan.showsReviewPrompt ? tr("自动扣款待核实") : tr("自动扣款 · 已确认开启")
    }
    private var tint: Color { plan.showsReviewPrompt ? .orange : plan.status == .disabled ? .green : .secondary }
    private var explanation: String {
        if !plan.isTracked { return tr("已停止本机跟踪，原扣款记录保留。可在管理中恢复。") }
        if plan.status == .disabled { return tr("你已记录此计划关闭，不再为它生成扣款提示。本机记录不会替你操作平台订阅。") }
        if !plan.remindersEnabled { return tr("本机提醒和首页核实待办已关闭，扣款记录仍保留。平台状态仍以核实结果为准。") }
        if plan.status == .enabled { return tr("你已确认此计划仍开启。记录日期与金额以平台为准，会员有效期单独管理。") }
        return tr("这是一条尚未核实的自动扣款记录。会员续费或一次性购买，不会自动取消原扣款计划。")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: plan.showsReviewPrompt ? "exclamationmark.circle.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            if plan.isTracked && plan.status != .disabled {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.label(plan.amountLabel)).font(.system(size: 21, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(plan.dateLabel(language: .current)).font(.system(size: 10)).multilineTextAlignment(.trailing)
                }
                Fact(title: tr("扣款渠道"), value: L10n.label(plan.channel))
            }
            Text(explanation).font(.system(size: 11)).foregroundStyle(.secondary)
            if let verifiedAt = plan.verifiedAt {
                Text(tr("最近核实：\(ServiceDate.string(verifiedAt))")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if plan.isTracked, let day = plan.nextCharge, (ServiceDate.days(day) ?? 0) < 0, plan.status != .disabled {
                Text(tr("所记扣款日已过去，不代表未来仍会按此日扣款；请核对并更新计划。"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Button(tr("管理自动扣款…")) { store.manageRenewal(service) }.controlSize(.small)
            if plan.isTracked && plan.status == .unverified {
                Button(tr("查看核实建议")) {
                    store.message = tr("请到\(L10n.label(plan.channel))的订阅或自动扣款管理中核实“\(service.name)”的记录：\(plan.dateLabel(language: .current))，\(L10n.label(plan.amountLabel))。核实后在“管理自动扣款”中登记结果，或选择不再提醒/停止跟踪。续期只修改本机记录，不会操作平台订阅。")
                }.buttonStyle(.borderless).font(.system(size: 10))
            }
            Text(tr("记录来源：\(L10n.label(plan.evidence))")).font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(15).background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}
