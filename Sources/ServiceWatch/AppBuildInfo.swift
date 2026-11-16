import AppKit
import Foundation

@MainActor enum AppBuildInfo {
    static var displayVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "ServiceWatchDisplayVersion") as? String ??
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"
    }
    static var releaseChannel: String? { Bundle.main.object(forInfoDictionaryKey: "ServiceWatchReleaseChannel") as? String }
    static let icon: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    static func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "续期",
            .applicationVersion: displayVersion,
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "开发构建",
            .credits: NSAttributedString(string: "网络服务与软件授权，本机管理。\nServiceWatch · MIT License\nCopyright (c) 2026 Sevacenix")
        ]
        if let image = icon ?? NSApp.applicationIconImage { options[.applicationIcon] = image }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
}
