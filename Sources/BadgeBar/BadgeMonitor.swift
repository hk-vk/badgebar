import AppKit
import Combine

/// Polls the Dock for badges and publishes changes.
@MainActor
final class BadgeMonitor: ObservableObject {
    @Published private(set) var entries: [DockEntry] = []
    @Published private(set) var isTrusted = DockReader.isTrusted
    @Published private(set) var needsRelaunch = false

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    var badges: [String: Badge] {
        var result: [String: Badge] = [:]
        for entry in entries {
            if let badge = entry.badge { result[entry.bundleID] = badge }
        }
        return result
    }

    func start(interval: TimeInterval) {
        setInterval(interval)

        // Refresh right away when apps launch or quit instead of waiting for the next tick.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated { self?.refresh() }
                }
            })
        }
        refresh()
    }

    func setInterval(_ interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(0.5, interval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Generous tolerance lets macOS batch this wake-up with others.
        timer?.tolerance = interval * 0.3
    }

    func refresh() {
        let (access, latest) = DockReader.read()
        let trusted = access == .granted
        if trusted != isTrusted { isTrusted = trusted }
        if (access == .needsRelaunch) != needsRelaunch { needsRelaunch = access == .needsRelaunch }
        guard trusted else { return }
        if latest != entries { entries = latest }
    }
}
