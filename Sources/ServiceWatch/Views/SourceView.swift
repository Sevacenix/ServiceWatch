import SwiftUI

struct SourceView: View {
    @Bindable var store: DemoStore
    private var catalog: CatalogStore { store.catalog }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(title: "数据源与更新", subtitle: "手动即时校验，每日自动一批，各自记账。")
                Surface(title: "有好价 · 全部服务目录") {
                    HStack { Pill(text: "真实HTTP读取", color: .blue); Pill(text: "系统SQLite保存", color: .teal) }
                    Fact(title: "已入库", value: "\(catalog.products.count)项服务 · \(catalog.snapshot.offers.count)个具体方案/渠道")
                    Fact(title: "服务图标", value: "\(catalog.icons.cachedRemoteCount)个真实品牌图标 · 本机缓存")
                    Text("公开分页目录 + 具体方案语义字段；JSON-LD只验证产品身份，不将聚合最低价套给其它等级。不请求robots禁止的/data/，不运行站点脚本，不使用模拟点击。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Link("打开有好价首页", destination: CatalogSource.base)
                        Link("robots规则", destination: CatalogSource.url("/robots.txt"))
                        Spacer()
                        Button("更新服务目录") { Task { await catalog.refreshDirectory() } }.disabled(catalog.isUpdating)
                        Button("立即更新全部价格") { Task { await catalog.refreshAll(.manual) } }.disabled(catalog.isUpdating)
                    }
                    CatalogStatusView(catalog: catalog)
                }
                Surface(title: "每日自动更新") {
                    Toggle("每天自动更新全部服务与方案", isOn: Binding(get: { catalog.snapshot.dailyEnabled }, set: { enabled in Task { await catalog.setDailyEnabled(enabled) } }))
                    Text("Asia/Shanghai自然日内最多尝试一批，失败也计入当天。手动添加和刷新另行联网，不占用或推迟每日额度。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("启动与唤醒时补一次，运行中约每30分钟检查资格。关闭主窗口后菜单栏继续运行；完全退出或休眠期间不执行，下次运行不补抓历史日期。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("条件GET：ETag / Last-Modified；304保留价格并追加校验记录。请求失败保留旧价，限流遵守Retry-After，不后台反复重试。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Surface(title: "最近更新记录") {
                    ForEach(catalog.snapshot.runs) { run in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(run.trigger.title).fontWeight(.medium); Spacer(); Text(run.status) }
                            Text(run.startedAt, format: .dateTime.year().month().day().hour().minute().second()).foregroundStyle(.secondary)
                            Text(run.note).foregroundStyle(.secondary).textSelection(.enabled)
                        }.font(.caption)
                        Divider()
                    }
                }
                Surface(title: "本机数据与个人授权") {
                    Text(catalog.databaseURL.path).font(.caption).textSelection(.enabled)
                    Text("优惠数据库与个人授权文件独立。联网不会修改已确认的等级、有效期、历史实付或自动扣款设置。授权导入只读取你提供的本地文件或剪贴板内容。系统通知尚未启用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}
