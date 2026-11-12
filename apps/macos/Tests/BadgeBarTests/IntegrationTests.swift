import XCTest
@testable import BadgeBar

/// The counts file, badgebar:// links and settings files are formats other tools and other
/// Macs depend on.
final class IntegrationTests: XCTestCase {
    // MARK: Counts file

    func testListsAddedAppsInOrderThenOtherBadgedAppsByName() {
        let group = AppGroup(name: "Chat")
        var slack = TrackedApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
        slack.groupID = group.id
        let mail = TrackedApp(bundleID: "com.apple.mail", name: "Mail")
        let apps = BadgeExport.apps(
            tracked: [slack, mail],
            groups: [group],
            badges: [
                "com.tinyspeck.slackmacgap": Badge(label: "12"),
                "com.apple.MobileSMS": Badge(label: "3"),
                "ru.keepcoder.Telegram": Badge(label: "•"),
            ],
            names: ["com.apple.MobileSMS": "Messages", "ru.keepcoder.Telegram": "Telegram"],
            running: ["com.tinyspeck.slackmacgap", "com.apple.mobilesms"]
        )

        XCTAssertEqual(apps.map(\.name), ["Slack", "Mail", "Messages", "Telegram"])
        XCTAssertEqual(apps[0], BadgeExport.App(
            bundleID: "com.tinyspeck.slackmacgap", name: "Slack", label: "12", count: 12,
            running: true, tracked: true, group: "Chat"
        ))
        XCTAssertNil(apps[1].label)
        XCTAssertFalse(apps[1].running)
        XCTAssertEqual(apps[2].count, 3)
        XCTAssertTrue(apps[2].running, "Running IDs are lowercased")
        XCTAssertFalse(apps[2].tracked)
        XCTAssertEqual(apps[3].label, "•")
        XCTAssertNil(apps[3].count)
    }

    func testMatchesBadgesRegardlessOfLetterCase() {
        let apps = BadgeExport.apps(
            tracked: [TrackedApp(bundleID: "com.apple.mobilesms", name: "Messages")],
            groups: [],
            badges: ["com.apple.MobileSMS": Badge(label: "3")],
            names: [:],
            running: []
        )
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].count, 3)
    }

    // MARK: Links

    func testParsesLinks() {
        func command(_ string: String) -> URLCommand? { URLCommand(URL(string: string)!) }
        XCTAssertEqual(command("badgebar://open?app=com.apple.mail"), .open(bundleID: "com.apple.mail"))
        XCTAssertEqual(command("BADGEBAR://Open?app=com.apple.mail"), .open(bundleID: "com.apple.mail"))
        XCTAssertNil(command("badgebar://toggle?app=com.apple.mail"), "Links can't tell which app is in front")
        XCTAssertEqual(command("badgebar://mark-read?app=com.apple.mail"), .markRead(bundleID: "com.apple.mail"))
        XCTAssertEqual(command("badgebar://mark-read"), .markRead(bundleID: nil))
        XCTAssertEqual(command("badgebar://settings"), .settings)
        XCTAssertNil(command("badgebar://open"), "Opening needs an app")
        XCTAssertNil(command("badgebar://open?app="))
        XCTAssertNil(command("badgebar://quit?app=com.apple.mail"))
        XCTAssertNil(command("https://open?app=com.apple.mail"))
    }

    // MARK: Settings files

    func testSettingsFileCarriesIconsToTheNewMac() throws {
        var app = TrackedApp(bundleID: "com.apple.mail", name: "Mail")
        app.iconStyle = .custom
        app.customIconPath = "/old/Icons/A.png"
        var group = AppGroup(name: "Work")
        group.customIconPath = "/old/Icons/A.png"
        var general = GeneralSettings()
        general.clickToHide = false

        let file = SettingsFile(apps: [app], groups: [group], general: general) { path in
            path == "/old/Icons/A.png" ? Data([1, 2, 3]) : nil
        }
        XCTAssertEqual(file.apps[0].customIconPath, "icon-1.png", "Paths become names in the file")
        XCTAssertEqual(file.groups[0].customIconPath, "icon-1.png", "One image shared by two items is packed once")
        XCTAssertEqual(file.icons, ["icon-1.png": Data([1, 2, 3])])

        let decoded = try SettingsFile.decode(file.encoded())
        var saves = 0
        let unpacked = decoded.unpacked { data, ext in
            XCTAssertEqual(data, Data([1, 2, 3]))
            XCTAssertEqual(ext, "png")
            saves += 1
            return "/new/Icons/B.png"
        }
        XCTAssertEqual(saves, 1, "An icon shared by two items is saved once")
        XCTAssertEqual(unpacked.apps[0].customIconPath, "/new/Icons/B.png")
        XCTAssertEqual(unpacked.groups[0].customIconPath, "/new/Icons/B.png")
        XCTAssertEqual(unpacked.groups[0].id, group.id)
        XCTAssertFalse(decoded.general.clickToHide)
    }

    @MainActor
    func testImportReplacesSetupButKeepsOnboardingDone() {
        let suite = "IntegrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = Store(defaults: defaults)
        store.general.hasCompletedOnboarding = true
        store.track(bundleID: "com.apple.mail", name: "Mail")

        var general = GeneralSettings()
        general.badgeEffect = .glow
        let file = SettingsFile(
            apps: [TrackedApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")],
            groups: [AppGroup(name: "Chat")],
            general: general
        )
        store.replaceSettings(with: file)

        XCTAssertEqual(store.apps.map(\.bundleID), ["com.tinyspeck.slackmacgap"])
        XCTAssertEqual(store.groups.map(\.name), ["Chat"])
        XCTAssertEqual(store.general.badgeEffect, .glow)
        XCTAssertTrue(store.general.hasCompletedOnboarding, "Importing doesn't bring back the welcome guide")
        XCTAssertEqual(Store(defaults: defaults).apps.map(\.bundleID), ["com.tinyspeck.slackmacgap"], "Saved")
    }

    func testIconsWithTheSameFileNameStaySeparate() {
        var a = TrackedApp(bundleID: "a", name: "A")
        a.customIconPath = "/Users/me/Pictures/slack/icon.png"
        var b = TrackedApp(bundleID: "b", name: "B")
        b.customIconPath = "/Users/me/Desktop/chat/icon.png"
        let file = SettingsFile(apps: [a, b], groups: [], general: GeneralSettings()) { path in
            Data(path.utf8)
        }
        XCTAssertNotEqual(file.apps[0].customIconPath, file.apps[1].customIconPath)
        XCTAssertEqual(file.icons.count, 2)
    }

    func testRefusesFilesFromNewerVersions() throws {
        var json = try JSONSerialization.jsonObject(
            with: SettingsFile(apps: [], groups: [], general: GeneralSettings()).encoded()
        ) as! [String: Any]
        json["version"] = SettingsFile.currentVersion + 1
        XCTAssertThrowsError(try SettingsFile.decode(JSONSerialization.data(withJSONObject: json))) { error in
            guard case SettingsFile.DecodeError.newerVersion = error else { return XCTFail("\(error)") }
        }
    }

    func testAcceptsFilesWithoutIcons() throws {
        var json = try JSONSerialization.jsonObject(
            with: SettingsFile(apps: [TrackedApp(bundleID: "a", name: "A")], groups: [], general: GeneralSettings()).encoded()
        ) as! [String: Any]
        json["icons"] = nil
        json["groups"] = nil
        let file = try SettingsFile.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(file.apps.map(\.bundleID), ["a"])
        XCTAssertTrue(file.icons.isEmpty)
    }

    func testMissingIconFallsBackToDefault() {
        var app = TrackedApp(bundleID: "com.apple.mail", name: "Mail")
        app.customIconPath = "/gone.png"
        let file = SettingsFile(apps: [app], groups: [], general: GeneralSettings()) { _ in nil }
        XCTAssertNil(file.apps[0].customIconPath)
    }

    func testOlderSettingsGetNewDefaults() throws {
        let general = try JSONDecoder().decode(GeneralSettings.self, from: Data(#"{"pollInterval": 3}"#.utf8))
        XCTAssertTrue(general.clickToHide)
        XCTAssertFalse(general.shareCounts)
        XCTAssertEqual(general.pollInterval, 3)
    }
}
