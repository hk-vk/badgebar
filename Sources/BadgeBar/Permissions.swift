import AppKit

/// Helpers for the two privacy permissions BadgeBar uses.
@MainActor
enum Permissions {
    /// Required: lets BadgeBar read badge counts from the Dock.
    static var hasAccessibility: Bool { DockReader.isTrusted }

    /// Optional: lets BadgeBar read Notification Center's database for message previews.
    static var hasFullDiskAccess: Bool { NotificationDatabase.isReadable }

    static func requestAccessibility() {
        DockReader.requestTrust()
        openPane("Privacy_Accessibility")
        PermissionHelper.shared.show(.accessibility)
    }

    /// Full Disk Access has no system prompt and macOS won't list BadgeBar on its own,
    /// so open the pane and float a draggable BadgeBar icon next to it.
    static func requestFullDiskAccess() {
        openPane("Privacy_AllFiles")
        PermissionHelper.shared.show(.fullDiskAccess)
    }

    static func openFullDiskAccessSettings() {
        requestFullDiskAccess()
    }

    /// Clears a stale Accessibility entry (common after rebuilding with a new signature)
    /// so macOS will prompt again.
    static func resetAccessibility() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", id]
        try? process.run()
        process.waitUntilExit()
        requestAccessibility()
    }

    /// Quits and reopens BadgeBar, optionally resuming onboarding at a given step.
    static func relaunch(resumingAt step: OnboardingStep? = nil) {
        if let step { UserDefaults.standard.set(step.rawValue, forKey: resumeStepKey) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The shell outlives us, waits for this process to exit, then opens the app again.
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"",
                             Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
        NSApp.terminate(nil)
    }

    static let resumeStepKey = "resumeOnboardingStep"

    /// Reveals the running app in Finder so it can be dragged into the permission list.
    static func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private static func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
