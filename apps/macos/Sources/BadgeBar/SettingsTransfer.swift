import AppKit
import UniformTypeIdentifiers

/// Everything needed to set BadgeBar up the same way on another Mac: apps, groups and
/// general settings, plus the images used as custom icons. Notification history and
/// read marks stay behind, since they belong to this Mac's notifications.
struct SettingsFile: Codable {
    /// The format this version of BadgeBar writes and understands.
    static let currentVersion = 1

    var version = Self.currentVersion
    var apps: [TrackedApp]
    var groups: [AppGroup]
    var general: GeneralSettings
    /// Custom icon images by file name. `customIconPath`s in the file hold just these names.
    var icons: [String: Data] = [:]

    /// Packs the current settings, reading each custom icon image from disk.
    init(apps: [TrackedApp], groups: [AppGroup], general: GeneralSettings, readIcon: (String) -> Data? = { try? Data(contentsOf: URL(fileURLWithPath: $0)) }) {
        var icons: [String: Data] = [:]
        // Numbered names: icons set by older versions live anywhere and may share a file name.
        var names: [String: String] = [:]
        func pack(_ path: String?) -> String? {
            guard let path else { return nil }
            if let name = names[path] { return name }
            guard let data = readIcon(path) else { return nil }
            let ext = URL(fileURLWithPath: path).pathExtension
            let name = "icon-\(names.count + 1)" + (ext.isEmpty ? "" : ".\(ext)")
            names[path] = name
            icons[name] = data
            return name
        }
        self.apps = apps.map { app in
            var app = app
            app.customIconPath = pack(app.customIconPath)
            return app
        }
        self.groups = groups.map { group in
            var group = group
            group.customIconPath = pack(group.customIconPath)
            return group
        }
        self.general = general
        self.icons = icons
    }

    /// The apps and groups with their icons saved on this Mac, through `saveIcon`, which
    /// returns the new path. Icons that are missing or can't be saved fall back to the default.
    func unpacked(saveIcon: (Data, String) -> String?) -> (apps: [TrackedApp], groups: [AppGroup]) {
        var saved: [String: String] = [:]
        func unpack(_ name: String?) -> String? {
            guard let name, let data = icons[name] else { return nil }
            if let path = saved[name] { return path }
            let path = saveIcon(data, URL(fileURLWithPath: name).pathExtension)
            saved[name] = path
            return path
        }
        let apps = apps.map { app in
            var app = app
            app.customIconPath = unpack(app.customIconPath)
            return app
        }
        let groups = groups.map { group in
            var group = group
            group.customIconPath = unpack(group.customIconPath)
            return group
        }
        return (apps, groups)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    enum DecodeError: Error {
        case newerVersion
    }

    static func decode(_ data: Data) throws -> SettingsFile {
        try JSONDecoder().decode(SettingsFile.self, from: data)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        // A newer format may mean something different by the same fields.
        guard version <= Self.currentVersion else { throw DecodeError.newerVersion }
        apps = try c.decode([TrackedApp].self, forKey: .apps)
        groups = try c.decodeIfPresent([AppGroup].self, forKey: .groups) ?? []
        general = try c.decode(GeneralSettings.self, forKey: .general)
        // Optional, so a file can be shared without its images.
        icons = try c.decodeIfPresent([String: Data].self, forKey: .icons) ?? [:]
    }
}

/// The Export and Import buttons in Settings.
@MainActor
enum SettingsTransfer {
    static func export(_ store: Store) {
        let panel = NSSavePanel()
        panel.title = "Export Settings"
        panel.nameFieldStringValue = "BadgeBar Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = SettingsFile(apps: store.apps, groups: store.groups, general: store.general)
            try file.encoded().write(to: url, options: .atomic)
        } catch {
            alert("Couldn't export settings", error.localizedDescription)
        }
    }

    static func `import`(into store: Store) {
        let panel = NSOpenPanel()
        panel.title = "Import Settings"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let file: SettingsFile
        do {
            file = try SettingsFile.decode(Data(contentsOf: url))
        } catch SettingsFile.DecodeError.newerVersion {
            alert("Couldn't import settings", "This file was made by a newer version of BadgeBar. Update BadgeBar, then try again.")
            return
        } catch {
            alert("Couldn't import settings", "This file isn't a BadgeBar settings file.")
            return
        }

        let confirm = NSAlert()
        confirm.messageText = "Replace your current settings?"
        confirm.informativeText = "Your apps, groups and settings will be replaced with the ones in “\(url.lastPathComponent)”. Notification history stays as it is."
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        store.replaceSettings(with: file)
    }

    private static func alert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
