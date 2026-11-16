# 数据说明 / Data and privacy

公开版的数据目录是当前用户的 Library/Application Support/ServiceWatch Open。首次运行建立空的报价数据库，首次保存后生成授权文件。安装包只含程序、界面素材和许可文件。向导样例在内存中展示。

The public build uses Library/Application Support/ServiceWatch Open under the current user's home directory. It creates an empty catalog database and creates an authorization file on the first save. Guide examples stay in memory.

| 文件 / File | 内容 / Contents |
| --- | --- |
| authorizations.json | 服务、等级、到期日、实付金额、用户确认的自动扣款状态，以及授权修改历史。 / Services, entitlement dates, payments, renewal settings and modification history. |
| catalog.sqlite | 目录、现有报价、逐次价格观测、更新状态与公开来源网页缓存。SQLite 运行时可能同时生成 WAL 和 SHM 文件。 / Directory, offers, observations, refresh state and public-page cache. |
| Icons/ | 资料页品牌图标缓存及用户选择导入的自定义图标。 / Cached brand icons and imported custom icons. |

## 导入和网络 / Imports and network

邮件解码和截图文字识别在 Mac 上执行。只有核对后保存的授权字段和来源类型进入授权文件。邮件原文、截图、识别全文和密钥不会随导入保存，也不会发送给报价站。

目录更新从有好价公开页面读取套餐信息，品牌图标来自该站公开资源。首次使用可点「刷新全部最新价格」，或在「数据源与更新」开启每日一次更新。联网请求含常规 HTTP 信息，例如网络地址和请求标头。点击来源或购买链接会在系统浏览器访问对应网站，由该网站处理。

Email decoding and OCR run locally. Explicit catalog actions refresh public source pages and brand icons. Automatic refresh is off at first launch. External links open in the browser.

## 历史报价 / Price history

最新价格按同一套餐条款、渠道和币种，与全部已采样最低价、所选年度最低价和活动最低价比较。按北京时间统计，618 取 6 月 1–18 日，双 11 取 11 月 1–11 日，黑五取美国感恩节次日起三天。无采样显示缺少记录。授权到期日与自动扣款日期由使用者确认。

Observed prices are grouped by equivalent offer, merchant and currency. Promotion windows are defined by the app for comparison and may differ from merchant schedules. Days with no observations have no historical price.

## 备份和反馈 / Backup and bug reports

完全退出应用后复制整个数据目录。请勿把本地数据库、授权 JSON、邮件、截图或自定义图标直接附到公开 issue。复现问题可使用本项目的虚构样例。

Quit the app before taking a folder backup. Use a fictional or redacted example in public issues.
