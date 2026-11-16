# 续期 · ServiceWatch 0.1.2

适用于 Apple Silicon Mac，macOS 14 或更新版本。

- 主界面、授权编辑与导入、优惠发现、比价和使用向导支持英文和简体中文。默认跟随系统首选语言，找不到支持的语言时使用英文。在主窗口工具栏的地球菜单可以直接切换，所选语言会保存。
- 已有授权和价格历史沿用原数据目录。商家原文和个人记录按原文显示。
- 「关于续期」显示 MIT 许可和 `Copyright (c) 2026 Sevacenix`，安装包随附[完整许可](https://github.com/Sevacenix/ServiceWatch/blob/v0.1.2/LICENSE)。

ServiceWatch now supports English and Simplified Chinese. It follows your preferred system languages by default and falls back to English. Select a language from the globe menu in the main window toolbar. Your choice persists across launches. Existing licenses and price history stay in the same data directory. Merchant content and personal entries retain their original text.

The About panel displays the MIT license and the Sevacenix copyright. The full license is included in the app bundle.

## 安装与首次打开 / Installation and first launch

1. 从本页 Assets 下载 DMG 或 ZIP。在终端运行 `shasum -a 256 <下载的文件名>`，对照 `SHA256SUMS.txt` 中该文件的哈希。
2. 打开 DMG，把「续期 Open」拖到「Applications」，或解压 ZIP 后把 App 移到「应用程序」。在 Finder 的「应用程序」中打开。
3. 此版使用 ad-hoc 签名，尚未通过 Apple 公证。如果系统提示无法验证开发者，而你已核对来源和哈希并选择信任此文件，先关闭提示，再到「系统设置 → 隐私与安全性 → 安全性」为此 App 选择「仍要打开」。部分 macOS 版本先显示「打开」。按照提示确认并完成身份验证。 [Apple 支持](https://support.apple.com/zh-cn/102445)

遇到哈希不匹配、应用已损坏或恶意软件提示时，请停止打开。若系统未提供单独打开的选项，可从源码构建。 [README 安装说明](https://github.com/Sevacenix/ServiceWatch#readme)

Download an archive from Assets and check it against `SHA256SUMS.txt`. Move the app to Applications and open it from Finder. If macOS blocks the verified ad-hoc signed app, use the app-specific **Open Anyway** option in **System Settings → Privacy & Security → Security** after attempting to open it. Follow Apple's guidance or use the local build instructions if this option is unavailable. [Apple Support](https://support.apple.com/en-us/102445)
