import AppKit
import Combine
import Darwin
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = Store()
    private let monitor = BadgeMonitor()
    private let router = SettingsRouter()
    private var statusBar: StatusBarController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        // The bundle icon is the light design; swap in the dark one for the Dock and ⌘-Tab
        // while the system is in dark mode.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { app, _ in
            let dark = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let url = Bundle.main.url(forResource: "AppIcon-dark", withExtension: "png")
            DispatchQueue.main.async {
                app.applicationIconImage = dark ? url.flatMap(NSImage.init(contentsOf:)) : nil
            }
        }

        monitor.start(interval: store.general.pollInterval)
        store.$general
            .map(\.pollInterval)
            .removeDuplicates()
            .dropFirst()
            .sink { [monitor] in monitor.setInterval($0) }
            .store(in: &cancellables)

        statusBar = StatusBarController(
            store: store,
            monitor: monitor,
            openSettings: { [weak self] in self?.showSettings(selecting: $0) },
            openGuide: { [weak self] in self?.showOnboarding() }
        )

        // macOS sometimes applies a fresh Accessibility grant only after a relaunch.
        // Do that for the user instead of asking them to quit and reopen.
        monitor.$needsRelaunch
            .removeDuplicates()
            .filter { $0 }
            .delay(for: .seconds(1.2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                let onboarding = self?.onboardingWindow?.isVisible == true
                Permissions.relaunch(resumingAt: onboarding ? .apps : nil)
            }
            .store(in: &cancellables)

        let defaults = UserDefaults.standard
        if let raw = defaults.object(forKey: Permissions.resumeStepKey) as? Int,
           let step = OnboardingStep(rawValue: raw) {
            defaults.removeObject(forKey: Permissions.resumeStepKey)
            showOnboarding(at: step)
        } else if !store.general.hasCompletedOnboarding {
            showOnboarding()
        } else if !monitor.isTrusted {
            showOnboarding(at: .accessibility)
        }
    }

    /// Launching the app again (e.g. from Finder or Spotlight) while it's running opens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings() }
        return true
    }

    // MARK: - Windows

    func showSettings(selecting item: SidebarItem? = nil) {
        if let item { router.selection = item }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(
                store: store,
                monitor: monitor,
                router: router,
                openGuide: { [weak self] in self?.showOnboarding() }
            ))
            hosting.sceneBridgingOptions = [.title, .toolbars]

            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            // A toolbar gives the window the tall, modern title bar that the sidebar runs up
            // into, as in System Settings. Without one it gets a thin, old-style title bar.
            window.toolbar = NSToolbar(identifier: "BadgeBarSettings")
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .none
            window.title = "BadgeBar"
            window.setContentSize(NSSize(width: 820, height: 600))
            window.setFrameAutosaveName("BadgeBarSettings")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        present(settingsWindow)
    }

    func showOnboarding(at step: OnboardingStep = .welcome) {
        onboardingWindow?.close()
        let view = OnboardingView(store: store, monitor: monitor, step: step) { [weak self] openSettings in
            self?.onboardingWindow?.close()
            if openSettings { self?.showSettings(selecting: .menuBar) }
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        onboardingWindow = window
        present(window)
    }

    /// While a window is open BadgeBar behaves like a regular app (Dock icon, ⌘-Tab), then
    /// steps back to being menu-bar-only when the last window closes.
    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let others = [settingsWindow, onboardingWindow].compactMap { $0 }.filter { $0 !== closing && $0.isVisible }
        if others.isEmpty {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
        // Release closed windows and their view trees; BadgeBar mostly lives in the menu bar,
        // so there's no point holding on to them. The router keeps the selected page.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if closing === self.settingsWindow { self.settingsWindow = nil }
            if closing === self.onboardingWindow { self.onboardingWindow = nil }
        }
        guard others.isEmpty else { return }
        // Once the window's views are gone, drop the icons its lists loaded and hand freed
        // memory back to macOS now rather than whenever it gets around to reclaiming it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            AppIcons.releaseLargeIcons()
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    // MARK: - Main menu

    /// A standard menu so ⌘C/⌘V, ⌘W, ⌘Q and friends work in BadgeBar's windows.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About BadgeBar", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(ClosureMenuItem("Settings…", key: ",") { [weak self] in self?.showSettings() })
        appMenu.addItem(ClosureMenuItem("Welcome Guide") { [weak self] in self?.showOnboarding() })
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide BadgeBar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit BadgeBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "BadgeBar")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        submenu.title = title
        item.submenu = submenu
        addItem(item)
    }
}
