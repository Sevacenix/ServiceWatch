# 续期 · ServiceWatch 0.1.1

适用于 Apple Silicon Mac，macOS 14 或更新版本。

- 从本版起采用 [MIT 许可](https://github.com/Sevacenix/ServiceWatch/blob/v0.1.1/LICENSE)，版权署名为 `Copyright (c) 2026 Sevacenix`。App 的「关于续期」显示许可和署名，安装包内随附完整许可文本。
- [v0.1.0](https://github.com/Sevacenix/ServiceWatch/releases/tag/v0.1.0) 继续采用发布时的 0BSD 许可。

The MIT license applies starting with v0.1.1, with copyright attributed to Sevacenix. The About panel displays the notice, and the app bundle includes the full license text. The original v0.1.0 release remains under 0BSD.

## 安装与首次打开 / Installation and first launch

1. 从本页 Assets 下载 DMG 或 ZIP。在终端运行 `shasum -a 256 <下载的文件名>`，对照 `SHA256SUMS.txt` 中该文件的哈希。
2. 打开 DMG，把「续期 Open」拖到「Applications」，或解压 ZIP 后把 App 移到「应用程序」。在 Finder 的「应用程序」中打开。
3. 此版使用 ad-hoc 签名，尚未通过 Apple 公证。如果系统提示无法验证开发者，而你已核对来源和哈希并选择信任此文件，先关闭提示，再到「系统设置 → 隐私与安全性 → 安全性」为此 App 选择「仍要打开」。部分 macOS 版本先显示「打开」。按照提示确认并完成身份验证。 [Apple 支持](https://support.apple.com/zh-cn/102445)

遇到哈希不匹配、应用已损坏或恶意软件提示时，请停止打开。若系统未提供单独打开的选项，可从源码构建。 [README 安装说明](https://github.com/Sevacenix/ServiceWatch#readme)

Download an archive from Assets and check it against `SHA256SUMS.txt`. Move the app to Applications and open it from Finder. If macOS blocks the verified ad-hoc signed app, use the app-specific **Open Anyway** option in **System Settings → Privacy & Security → Security** after attempting to open it. Follow Apple's guidance or use the local build instructions if this option is unavailable. [Apple Support](https://support.apple.com/en-us/102445)
