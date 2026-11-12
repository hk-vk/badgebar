import XCTest
@testable import BadgeBar

/// Settings files are a format other Macs depend on.
final class IntegrationTests: XCTestCase {
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
        XCTAssertEqual(general.pollInterval, 3)
    }
}
