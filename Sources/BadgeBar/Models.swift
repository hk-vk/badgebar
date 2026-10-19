import Foundation

enum BadgeStyle: String, Codable, CaseIterable, Identifiable {
    case circle, text, dot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .circle: return "Circle"
        case .text: return "Text"
        case .dot: return "Dot"
        }
    }
}

/// What to do with a menu bar item when its app has no badge.
enum EmptyBehavior: String, Codable, CaseIterable, Identifiable {
    case dim, hide, show
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dim: return "Dim icon"
        case .hide: return "Hide icon"
        case .show: return "Show normally"
        }
    }
}

enum IconStyle: String, Codable, CaseIterable, Identifiable {
    case original, monochrome, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "Original"
        case .monochrome: return "Monochrome"
        case .custom: return "Custom image"
        }
    }
}

/// Visual settings shared by individual apps and groups.
struct BadgeAppearance: Codable, Hashable {
    var style: BadgeStyle = .circle
    var colorHex: String = "#FF3B30"
    var emptyBehavior: EmptyBehavior = .dim
}

struct TrackedApp: Codable, Identifiable, Hashable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var appearance = BadgeAppearance()
    var iconStyle: IconStyle = .original
    var customIconPath: String?
    /// When set, the app is shown inside this group instead of on its own.
    var groupID: UUID?
}

struct AppGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// SF Symbol shown in the menu bar for the group.
    var symbol: String = "tray.full"
    var appearance = BadgeAppearance()
}

struct GeneralSettings: Codable, Hashable {
    /// Show a temporary item for any badged app that isn't explicitly tracked.
    var autoShowBadgedApps = true
    var showMainIcon = true
    var pollInterval: Double = 1.5
    var showHoverPreviews = true
    /// Include notification titles and bodies in previews (needs Full Disk Access).
    var showMessageContent = true
    var hasCompletedOnboarding = false

    init() {}

    // Decode field by field so settings saved by older versions keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralSettings()
        autoShowBadgedApps = try c.decodeIfPresent(Bool.self, forKey: .autoShowBadgedApps) ?? d.autoShowBadgedApps
        showMainIcon = try c.decodeIfPresent(Bool.self, forKey: .showMainIcon) ?? d.showMainIcon
        pollInterval = try c.decodeIfPresent(Double.self, forKey: .pollInterval) ?? d.pollInterval
        showHoverPreviews = try c.decodeIfPresent(Bool.self, forKey: .showHoverPreviews) ?? d.showHoverPreviews
        showMessageContent = try c.decodeIfPresent(Bool.self, forKey: .showMessageContent) ?? d.showMessageContent
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
    }
}

/// Notifications the user has cleared from BadgeBar's viewer.
struct ClearedNotifications: Codable, Hashable {
    /// Per lowercased bundle ID: hide everything delivered at or before this date.
    var before: [String: Date] = [:]
    /// Individually dismissed notification record IDs.
    var ids: Set<Int64> = []
}

/// A page in the settings sidebar.
enum SidebarItem: Hashable {
    case general
    case app(String)
    case group(UUID)
}

/// A badge as read from the Dock. `count` is nil for non-numeric badges like "•" or "!".
struct Badge: Hashable {
    var label: String
    var count: Int? {
        Int(label.filter(\.isNumber))
    }

    /// Sums badges for a group. Non-numeric badges still mark the group as active.
    static func combine(_ badges: [Badge]) -> Badge? {
        guard !badges.isEmpty else { return nil }
        let total = badges.compactMap(\.count).reduce(0, +)
        return Badge(label: total > 0 ? String(total) : "•")
    }
}
