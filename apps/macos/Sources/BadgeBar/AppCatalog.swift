import AppKit

/// An installed application that can be added to the menu bar.
struct AppInfo: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let url: URL
    var category: AppCatalog.Category?
}

/// Knows which installed apps are worth suggesting, and lists every installed app for search.
@MainActor
enum AppCatalog {
    enum Category: String {
        case messaging = "Messaging"
        case work = "Work"
        case apple = "Apple"
    }

    /// Apps that commonly show unread badges, in the order they're suggested.
    /// Several apps ship under more than one bundle ID (App Store vs. direct download).
    private static let known: [(ids: [String], category: Category)] = [
        (["com.tinyspeck.slackmacgap"], .work),
        (["com.microsoft.teams2", "com.microsoft.teams"], .work),
        (["com.microsoft.Outlook"], .work),
        (["us.zoom.xos"], .work),
        (["com.readdle.smartemail-Mac", "com.readdle.SparkDesktop"], .work),
        (["com.superhuman.electron"], .work),
        (["com.linear"], .work),
        (["notion.id"], .work),
        (["com.basecamp.bc3-mac"], .work),
        (["com.apple.MobileSMS"], .messaging),
        (["net.whatsapp.WhatsApp", "desktop.WhatsApp"], .messaging),
        (["com.hnc.Discord"], .messaging),
        (["ru.keepcoder.Telegram", "org.telegram.desktop"], .messaging),
        (["org.whispersystems.signal-desktop"], .messaging),
        (["com.facebook.archon", "com.facebook.archon.developerID"], .messaging),
        (["com.tencent.xinWeChat"], .messaging),
        (["jp.naver.line.mac"], .messaging),
        (["com.viber.osx"], .messaging),
        (["com.skype.skype"], .messaging),
        (["com.apple.mail"], .apple),
        (["com.apple.FaceTime"], .apple),
        (["com.apple.iCal"], .apple),
        (["com.apple.reminders"], .apple),
        (["com.apple.AppStore"], .apple),
    ]

    private static var installedCache: [AppInfo]?

    /// Installed apps from the known list, messaging and work apps first.
    static func suggestions() -> [AppInfo] {
        known.compactMap { entry in
            for id in entry.ids {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    return AppInfo(bundleID: Bundle(url: url)?.bundleIdentifier ?? id, name: name(of: url), url: url, category: entry.category)
                }
            }
            return nil
        }
    }

    /// Every app in the standard Applications folders, sorted by name.
    static func installed() -> [AppInfo] {
        if let installedCache { return installedCache }

        let fm = FileManager.default
        let folders = [
            "/Applications", "/Applications/Utilities",
            "/System/Applications", "/System/Applications/Utilities",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
        ]
        var seen = Set<String>()
        var apps: [AppInfo] = []
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            // Skip hidden helper apps such as ".Karabiner-VirtualHIDDevice-Manager.app".
            for item in items where item.hasSuffix(".app") && !item.hasPrefix(".") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(item)
                guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted else { continue }
                apps.append(AppInfo(bundleID: id, name: name(of: url), url: url, category: category(of: id)))
            }
        }
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        installedCache = apps
        return apps
    }

    /// Case- and diacritic-insensitive search across installed apps.
    static func search(_ query: String) -> [AppInfo] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return installed() }
        return installed()
            .filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            // Names that start with the query come first.
            .sorted { a, b in
                let ap = a.name.lowercased().hasPrefix(query.lowercased())
                let bp = b.name.lowercased().hasPrefix(query.lowercased())
                return ap != bp ? ap : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    static func info(for bundleID: String) -> AppInfo? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return AppInfo(bundleID: bundleID, name: name(of: url), url: url, category: category(of: bundleID))
    }

    private static func category(of bundleID: String) -> Category? {
        known.first { $0.ids.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame } }?.category
    }

    private static func name(of url: URL) -> String {
        let display = FileManager.default.displayName(atPath: url.path)
        return display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    }
}
