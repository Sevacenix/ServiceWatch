import SwiftUI

struct EntitlementEditorRow: View {
    @Binding var draft: EntitlementDraft
    var body: some View {
        TextField("等级 / 版本", text: $draft.tier, prompt: Text("可任意录入，例如 SVIP / Pro / 终身版"))
        Picker("有效期类型", selection: $draft.validity) {
            ForEach(["有到期日", "永久授权", "待确认"], id: \.self) { Text($0) }
        }
        if draft.validity == "有到期日" {
            TextField("到期日期", text: $draft.expiryText, prompt: Text("YYYY-MM-DD，例如 2028-06-19"))
                .monospacedDigit().accessibilityLabel("\(draft.tier.isEmpty ? "新增授权" : draft.tier)到期日期")
            if ServiceDate.parse(draft.expiryText) == nil {
                Text("请输入有效日期，格式为 YYYY-MM-DD。").font(.caption).foregroundStyle(.orange)
            }
        } else if draft.validity == "永久授权" {
            Text("使用权无到期日，版本升级或维护期可以再添加一条授权。").font(.caption).foregroundStyle(.secondary)
        }
        TextField("备注 / 生效关系", text: $draft.note, prompt: Text("例如当前使用、到期后继续或已续费"))
    }
}
