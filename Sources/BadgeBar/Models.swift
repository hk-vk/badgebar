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
