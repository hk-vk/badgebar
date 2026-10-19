import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let monitor = BadgeMonitor()
    private var statusBar: StatusBarController?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.start(interval: store.general.pollInterval)
        store.$general
            .map(\.pollInterval)
            .removeDuplicates()
            .dropFirst()
            .sink { [monitor] in monitor.setInterval($0) }
            .store(in: &cancellables)

        statusBar = StatusBarController(store: store, monitor: monitor) { [weak self] in
            self?.showSettings()
        }

        if !DockReader.isTrusted {
            DockReader.requestTrust()
            showSettings()
        }
    }

    /// Launching the app again (e.g. from Finder) while it's running opens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "BadgeBar Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView(store: store, monitor: monitor))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
