import SwiftUI

struct GuideView: View {
    @Bindable var store: DemoStore
    @State private var showingExamples = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeading(title: "使用向导", subtitle: "记录到期时间，查阅同一方案的历史价格。")
                Surface(title: "记录订阅和授权") {
                    Text("添加服务，再填写等级和到期日。也可以导入邮件或截图，核对识别结果后保存。自动扣款日期在服务详情中单独管理。")
                        .font(.callout)
                    HStack {
                        Button("添加服务") { store.edit(nil) }
                        Button("导入授权") { store.destination = .inbox }
                    }
                }
                Surface(title: "获取报价并比较") {
                    Text("在「优惠发现」手动刷新，在报价旁点「比价记录」。历史最低、年度最低和活动最低来自实际采样。想每天更新，可在「数据源与更新」开启。")
                        .font(.callout)
                    HStack {
                        Button("优惠发现") { store.destination = .offers }
                        Button("数据源与更新") { store.destination = .sources }
                    }
                }
                Surface(title: "体验虚构样例") {
                    Text("样例仅在向导中展示。").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("查看授权与报价样例", isExpanded: $showingExamples) {
                        VStack(alignment: .leading, spacing: 10) {
                            Fact(title: "示例服务", value: "晨光笔记 · 专业版")
                            Fact(title: "授权有效期", value: "2030-09-30")
                            Fact(title: "下次自动扣款", value: "2030-09-25 · CNY 120")
                            Divider()
                            Fact(title: "示例最新报价", value: "CNY 120")
                            Fact(title: "示例双 11 最低", value: "CNY 100")
                            Fact(title: "差额", value: "+20（+20%）")
                        }.padding(.top, 8)
                    }
                }
            }.padding(28).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}
