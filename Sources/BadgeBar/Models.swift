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

/// How a badge draws attention when something new arrives.
enum BadgeEffect: String, Codable, CaseIterable, Identifiable {
    case off, pulse, glow, shimmer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .pulse: return "Pulse"
        case .glow: return "Glow"
        case .shimmer: return "Shimmer"
        }
    }
}

/// Which version of BadgeBar's own icon the Dock and app switcher show.
enum AppIconChoice: String, Codable, CaseIterable, Identifiable {
    case automatic, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// What to do with a menu bar item when its app has no badge.
enum EmptyBehavior: String, Codable, CaseIterable, Identifiable {
    /// Follow the global setting in Appearance.
    case useDefault
    case dim, hide, show
    var id: String { rawValue }
    var label: String {
        switch self {
        case .useDefault: return "Use Default"
        case .dim: return "Dim icon"
        case .hide: return "Hide icon"
        case .show: return "Show normally"
        }
    }

    /// The concrete choices, for the global setting.
    static var concrete: [EmptyBehavior] { [.dim, .hide, .show] }
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
    var emptyBehavior: EmptyBehavior = .useDefault

    /// Replaces "Use Default" with the global rule.
    func resolved(_ general: GeneralSettings) -> BadgeAppearance {
        var appearance = self
        if appearance.emptyBehavior == .useDefault { appearance.emptyBehavior = general.emptyBehavior }
        return appearance
    }
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
    /// An image shown instead of the symbol: a copy in BadgeBar's own folder.
    var customIconPath: String?
    var appearance = BadgeAppearance()
}

struct GeneralSettings: Codable, Hashable {
    /// Show a temporary item for any badged app that isn't explicitly tracked.
    var autoShowBadgedApps = true
    /// Show BadgeBar's own icon in the menu bar. It also appears while permission is missing.
    var showMainIcon = false
    var pollInterval: Double = 1.5
    /// What icons do when their app has nothing new, unless an app overrides it.
    var emptyBehavior: EmptyBehavior = .dim
    /// Hide icons for apps that aren't open, unless they still show a badge.
    var hideWhenNotRunning = false
    /// Animates a badge when it appears or its count goes up.
    var badgeEffect: BadgeEffect = .pulse
    /// Keeps replaying the effect every few seconds while a badge is unread.
    var repeatBadgeEffect = false
    /// The icon shown in the Dock while a BadgeBar window is open.
    var appIcon: AppIconChoice = .automatic
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
        emptyBehavior = try c.decodeIfPresent(EmptyBehavior.self, forKey: .emptyBehavior) ?? d.emptyBehavior
        hideWhenNotRunning = try c.decodeIfPresent(Bool.self, forKey: .hideWhenNotRunning) ?? d.hideWhenNotRunning
        badgeEffect = try c.decodeIfPresent(BadgeEffect.self, forKey: .badgeEffect) ?? d.badgeEffect
        repeatBadgeEffect = try c.decodeIfPresent(Bool.self, forKey: .repeatBadgeEffect) ?? d.repeatBadgeEffect
        appIcon = try c.decodeIfPresent(AppIconChoice.self, forKey: .appIcon) ?? d.appIcon
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
    /// Per lowercased bundle ID: the badge the user marked as read. It stays hidden until the
    /// count goes up, a new notification arrives, or the badge disappears.
    var acknowledged: [String: String] = [:]
}

/// A page in the settings sidebar.
enum SidebarItem: Hashable {
    case menuBar
    case appearance
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
