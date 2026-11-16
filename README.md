# 续期 · ServiceWatch

在 Mac 上记录订阅、软件授权和续费日期，比较同一套餐的历史价格。授权保存在本机。

ServiceWatch is a native macOS app for tracking subscriptions, software licenses, renewal dates, and observed deal prices. The UI is currently in Simplified Chinese.

[下载 / Download](https://github.com/Sevacenix/ServiceWatch/releases) · [数据说明 / Data](docs/DATA.md) · [样例 / Examples](examples/) · [发布说明 / Release notes](RELEASE-NOTES.md)

## 开始使用 / Quick start

1. 下载适用于 Apple Silicon 的 ZIP 或 DMG。将「续期 Open」放到「应用程序」并打开。需要 macOS 14 或更新版本。
2. 在空白首页点「添加服务」，填入等级和到期日。也可在「授权导入」选取邮件或截图，核对草稿后保存。
3. 在「优惠发现」点「刷新全部最新价格」，再从具体报价打开「比价记录」。在「数据源与更新」可开启每日更新。
4. 侧栏「使用向导」有简明操作入口和虚构样例。

Open **续期 Open**, add a service manually or review an imported email or screenshot, then refresh the catalog if you want to compare offers. The built-in guide includes read-only fictional examples. Automatic catalog refresh is opt-in.

GitHub 安装包使用本地签名。若 macOS 拒绝启动下载版，可按下文从公开源码构建。

## 功能 / Features

- 为同一服务保存多个会员等级、到期日或永久授权，另行记录自动扣款状态和历史实付金额。
- 从 EML 或邮件正文读取授权信息，用 Apple Vision 在本机识别截图。选择保存目标并确认后写入。
- 从[有好价](https://deals.iplaysoft.com/)读取公开套餐报价，按同一套餐条款、渠道和币种对比历史、年度及 618、双 11、黑五的最低观测价。
- 首次启动时授权列表和报价历史为空。已采样的价格按观察时间入库。商家实际结算金额以结算页为准。

## 本地构建 / Build locally

需要 macOS 14+、Swift 6 和 macOS SDK。项目使用 SwiftUI、AppKit、Vision、Charts 和系统 SQLite。

Requires macOS 14+, Swift 6 and a macOS SDK. There are no third-party package dependencies.

    swift test
    ./script/build_and_run.sh --verify

开发版使用独立数据目录。要生成 Apple Silicon ZIP、DMG 和 SHA-256 校验文件，运行：

    ./script/package_prerelease.sh

The packaging script puts local artifacts in the dist directory. See the data notes before sharing examples or debug logs.

## 反馈与许可 / Feedback & license

欢迎提交 issue，注明 macOS 版本、应用版本、复现步骤和预期结果。请使用虚构或已脱敏的样例附件。

源代码及本项目创作的样例以 [0BSD](LICENSE) 发布。在线报价、品牌标识与商家页面由相应来源提供。
