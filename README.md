# 续期 · ServiceWatch

在 Mac 上记录订阅、软件授权和续费日期，比较同一套餐的历史价格。授权保存在本机。

ServiceWatch is a native macOS app for tracking subscriptions, software licenses, renewal dates, and observed deal prices. The UI is currently in Simplified Chinese.

[下载 / Download](https://github.com/Sevacenix/ServiceWatch/releases) · [数据说明 / Data](docs/DATA.md) · [样例 / Examples](examples/) · [发布说明 / Release notes](RELEASE-NOTES.md)

## 开始使用 / Quick start

1. 从 GitHub Releases 的 Assets 下载 Apple Silicon DMG 或 ZIP。打开 DMG 后把「续期 Open」拖到「Applications」，或解压 ZIP 并把 App 移到「应用程序」。然后在「应用程序」中打开。需要 macOS 14 或更新版本。
2. 在空白首页点「添加服务」，填入等级和到期日。也可在「授权导入」选取邮件或截图，核对草稿后保存。
3. 在「优惠发现」点「刷新全部最新价格」，再从具体报价打开「比价记录」。在「数据源与更新」可开启每日更新。
4. 侧栏「使用向导」有简明操作入口和虚构样例。

Open **续期 Open**, add a service manually or review an imported email or screenshot, then refresh the catalog if you want to compare offers. The built-in guide includes read-only fictional examples. Automatic catalog refresh is opt-in.

### 首次打开与 macOS 提示 / First launch on macOS

当前安装包使用 ad-hoc 签名，尚未通过 Apple 公证。下载后可运行以下命令，将输出的哈希与同一发布页的 `SHA256SUMS.txt` 对应行比较。按实际版本和文件类型替换文件名。

```sh
shasum -a 256 ServiceWatch-0.1.1-macOS-arm64.dmg
```

若首次打开时出现「无法验证开发者」或 Apple 无法检查该 App 的提示，先确认文件来自本仓库的发布页且校验值相符。如果你选择信任这份安装包：

1. 先在 Finder 的「应用程序」中尝试打开 App，再关闭拦截提示。
2. 打开「系统设置 → 隐私与安全性」，下滚至「安全性」，在「续期 Open」的提示旁点击「仍要打开」。部分 macOS 版本先显示「打开」，点击后才显示「仍要打开」。该选项通常在首次尝试后约一小时内可用。
3. 按系统提示确认并完成身份验证。系统只为这一个 App 保存例外。

如果哈希不匹配，或系统报告应用已损坏、会损坏电脑，请停止打开，重新从发布页下载并核对。若系统未提供单独打开的选项，也可以按下文从源码构建。 [Apple 支持](https://support.apple.com/zh-cn/102445)

The release is ad-hoc signed and has no Apple notarization. Compare the downloaded archive's SHA-256 hash with the release checksum file. If macOS blocks a verified download with a developer or notarization warning, try opening it in Finder, then go to **System Settings → Privacy & Security → Security** and use the app-specific **Open Anyway** option. On some versions, **Open** appears first. Stop if the checksum differs or macOS reports damage or malware. When the app-specific option is unavailable, build locally. [Apple Support](https://support.apple.com/en-us/102445)

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

自 `v0.1.1` 起，源代码及本项目创作的样例采用 [MIT 许可](LICENSE)，版权署名为 `Copyright (c) 2026 Sevacenix`。[v0.1.0](https://github.com/Sevacenix/ServiceWatch/tree/v0.1.0) 继续采用发布时的 0BSD 许可。在线报价、品牌标识与商家页面由相应来源提供。

Source code and project-created examples are licensed under MIT starting with `v0.1.1`. The original `v0.1.0` release remains under 0BSD.
