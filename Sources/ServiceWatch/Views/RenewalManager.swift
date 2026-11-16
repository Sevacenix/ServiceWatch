import SwiftUI

struct RenewalManager: View {
    @Bindable var store: DemoStore
    let service: Service
    @State private var plan: RenewalPlan
    @State private var saveError: String? = nil
    init(store: DemoStore, service: Service) {
        self.store = store
        self.service = service
        _plan = State(initialValue: service.renewalPlan ?? RenewalPlan())
    }
    private var canSave: Bool {
        let hasInput = service.renewalPlan != nil || !plan.isTracked || !plan.remindersEnabled || plan.status != .unverified ||
            plan.nextCharge != nil || plan.amount != nil ||
            [plan.channel, plan.method, plan.cycle].contains(where: { !["", "待核实"].contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) ||
            !plan.note.isEmpty
        return store.storageIssue == nil && plan.isValid && hasInput
    }
    private func optionalText(_ key: WritableKeyPath<RenewalPlan, String?>) -> Binding<String> {
        Binding(get: { plan[keyPath: key] ?? "" }, set: { plan[keyPath: key] = RenewalPlan.nonempty($0) })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("管理自动扣款").font(.title2.bold())
                    Text(service.name).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Pill(text: "仅管理本机记录", color: .blue)
            }.padding(22)
            Divider()
            Form {
                Section("本机跟踪与提醒") {
                    Toggle("跟踪这项自动扣款", isOn: $plan.isTracked)
                    Toggle("接收此计划的本地提醒与核实提示", isOn: Binding(
                        get: { plan.allowsLocalReminders }, set: { plan.remindersEnabled = $0 }
                    ))
                        .disabled(!plan.isTracked || plan.status == .disabled)
                    Text(!plan.isTracked ? "已选择停止跟踪：不再显示首页待办，历史记录保留，可随时恢复。" :
                            plan.status == .disabled ? "已登记平台扣款关闭：不再显示首页核实待办，也不生成该计划的本地提醒。" :
                            !plan.remindersEnabled ? "已选择不再提醒：首页不再提示，但仍保留扣款记录和核实状态。" :
                            "待核实的计划会显示首页待办。当前版本尚未启用系统通知推送。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("平台核实结果") {
                    Picker("自动扣款状态", selection: $plan.status) {
                        Text("待核实").tag(RenewalStatus.unverified)
                        Text("我已核实，仍开启").tag(RenewalStatus.enabled)
                        Text("我已核实，已关闭").tag(RenewalStatus.disabled)
                    }
                    Text("只登记你已核实的结果。选择“已关闭”、停止跟踪或关闭提醒，都不会替你取消平台订阅。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("扣款计划 · 独立于本次会员购买") {
                    TextField("扣款渠道", text: $plan.channel, prompt: Text("例如 App Store，不是本次购买店铺"))
                    TextField("扣款方式", text: $plan.method)
                    TextField("扣款周期", text: $plan.cycle)
                    TextField("记录扣款日", text: optionalText(\.nextCharge), prompt: Text("YYYY-MM-DD；未知可留空"))
                        .monospacedDigit()
                    if let date = plan.nextCharge, ServiceDate.parse(date) == nil {
                        Text("请输入有效日期，格式为 YYYY-MM-DD。").font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        TextField("扣款金额", text: optionalText(\.amount), prompt: Text("未知可留空"))
                        TextField("币种", text: Binding(get: { plan.currency }, set: { plan.currency = $0.uppercased() }))
                            .frame(width: 85)
                    }
                    if let amount = plan.amount, !RenewalPlan.validAmount(amount) {
                        Text("金额需为非负数，最多两位小数。").font(.caption).foregroundStyle(.orange)
                    }
                    if plan.currency.range(of: "^[A-Z]{3}$", options: .regularExpression) == nil {
                        Text("币种请输入三个英文字母，例如 CNY 或 USD。").font(.caption).foregroundStyle(.orange)
                    }
                    TextField("备注", text: $plan.note, axis: .vertical).lineLimit(2...4)
                    Text("来源：\(plan.evidence)").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Text("保存不会修改会员等级、有效期或已购订单。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { store.showingRenewalManager = false }.keyboardShortcut(.cancelAction)
                Button("保存本机设置") {
                    do {
                        try store.updateRenewal(serviceID: service.id, plan: plan)
                        store.showingRenewalManager = false
                    } catch { saveError = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(!canSave)
            }.padding(18)
        }.frame(width: 700, height: 760)
            .alert("未能保存扣款设置", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("知道了") { saveError = nil }
            } message: { Text(saveError ?? "") }
    }
}
