import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var reopenMonitor: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { reopenMonitor?() }
        return true
    }
}

@main struct ServiceWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = DemoStore()
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.system
    var body: some Scene {
        WindowGroup(tr("续期 · 服务与授权"), id: "main") {
            MonitorWindowContent(store: store, delegate: delegate, language: $language)
                .id(language)
                .environment(\.locale, language.locale)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(tr("关于续期")) { AppBuildInfo.showAbout() }
            }
            CommandGroup(replacing: .newItem) {
                Button(tr("添加服务…")) { store.edit(nil) }.keyboardShortcut("n", modifiers: .command)
                Button(tr("导入授权…")) { store.showingImport = true }.keyboardShortcut("i", modifiers: .command)
            }
            MonitorWindowCommands()
        }
        Settings {
            SourceView(store: store).frame(width: 750, height: 650)
                .id(language)
                .environment(\.locale, language.locale)
        }
        MenuBarExtra(tr("续期"), systemImage: "calendar.badge.clock") {
            ServiceWatchMenu(store: store).id(language)
        }
    }
}

private struct MonitorWindowContent: View {
    let store: DemoStore
    let delegate: AppDelegate
    @Binding var language: AppLanguage
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ContentView(store: store, language: $language).onAppear {
            let action = openWindow
            delegate.reopenMonitor = { action(id: "main") }
        }
    }
}

private struct MonitorWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(before: .windowArrangement) {
            Button(tr("打开监控窗口")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                .keyboardShortcut("1", modifiers: .command)
        }
    }
}

private struct ServiceWatchMenu: View {
    let store: DemoStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(tr("\(store.services.filter { $0.paid && !$0.example }.count) 项已开通 · 本地保存"))
        Text(AppBuildInfo.displayVersion)
        Divider()
        Button(tr("打开监控窗口")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(tr("退出续期")) { NSApp.terminate(nil) }
    }
}
