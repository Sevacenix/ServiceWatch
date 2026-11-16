import Foundation

enum RenewalStatus: String, Codable, CaseIterable {
    case unverified, enabled, disabled
    var title: String {
        switch self {
        case .unverified: "待核实"
        case .enabled: "已核实仍开启"
        case .disabled: "已核实已关闭"
        }
    }
}

struct RenewalPlan: Codable, Equatable {
    var status: RenewalStatus = .unverified
    var isTracked = true
    var remindersEnabled = true
    var nextCharge: String? = nil
    var amount: String? = nil
    var currency = "CNY"
    var channel = "待核实"
    var method = "待核实"
    var cycle = "待核实"
    var evidence = "手动录入的扣款计划"
    var note = ""
    var verifiedAt: Date? = nil
    var updatedAt: Date? = nil

    var showsReviewPrompt: Bool { isTracked && remindersEnabled && status == .unverified }
    var allowsLocalReminders: Bool { isTracked && remindersEnabled && status != .disabled }
    func summary(language: AppLanguage) -> String {
        if !isTracked { return L10n.label("已停止本机跟踪", language: language) }
        let title = L10n.label(status.title, language: language)
        if !remindersEnabled && status != .disabled {
            return L10n.text("\(title) · 本地提醒已关闭", language: language)
        }
        return title
    }
    var amountLabel: String { amount.map { currency + " " + $0 } ?? "金额待确认" }
    var dateLabel: String { dateLabel(language: .simplifiedChinese) }
    func dateLabel(language: AppLanguage) -> String {
        guard let date = nextCharge else { return L10n.label("扣款日期待确认", language: language) }
        guard (ServiceDate.days(date) ?? 0) < 0 else { return date }
        return L10n.text("记录日期 \(date)（已过）", language: language)
    }
    var isValid: Bool {
        guard nextCharge.map({ ServiceDate.parse($0) != nil }) ?? true,
              amount.map(Self.validAmount) ?? true,
              currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { return false }
        return true
    }
    static func validAmount(_ value: String) -> Bool {
        value.range(of: "^[0-9]+(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil
    }
    static func nonempty(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    static func migrate(service: Service, history: [ServiceChange]) -> RenewalPlan? {
        let date = nonempty(service.nextCharge)
        let amount = nonempty(service.nextAmount)
        let state = service.autoRenew.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasState = !["", "未知", "未提供", "待核实"].contains(state)
        guard date != nil || amount != nil || hasState else { return nil }

        // The newest purchase can be one-off. Recover the old recurring source
        // from history instead of relabeling an Apple agreement as a JD order.
        let isRecurring: (Service) -> Bool = { $0.billingCycle.contains("连续") || $0.billingCycle.contains("自动") }
        let original = isRecurring(service) ? service : history.compactMap(\.before).first {
            $0.id == service.id && nonempty($0.nextCharge) == date && nonempty($0.nextAmount) == amount && isRecurring($0)
        }
        var plan = RenewalPlan()
        if state.contains("已关闭") || state.contains("已取消") { plan.status = .disabled }
        plan.nextCharge = date.flatMap { ServiceDate.parse($0) != nil ? $0 : nil }
        plan.amount = amount.flatMap { validAmount($0) ? $0 : nil }
        plan.currency = original?.currency ?? service.currency
        plan.channel = original?.channel ?? "原自动扣款渠道待核实"
        plan.method = original?.method ?? "待核实"
        plan.cycle = original?.billingCycle ?? "待核实"
        plan.evidence = original?.evidence ?? "从旧自动扣款记录迁移，来源待核实"
        plan.note = "旧记录状态：\(service.autoRenew)。需在原扣款平台核实；会员续费不代表原计划已关闭。"
        if let date, plan.nextCharge == nil { plan.note += " 旧日期需确认：\(date)。" }
        if let amount, plan.amount == nil { plan.note += " 旧金额需确认：\(amount)。" }
        return plan
    }
}
