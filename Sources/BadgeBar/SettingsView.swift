import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor

    var body: some View {
        TabView {
            AppsTab(store: store, monitor: monitor)
                .tabItem { Label("Apps", systemImage: "app.badge") }
            GroupsTab(store: store)
                .tabItem { Label("Groups", systemImage: "square.stack") }
            GeneralTab(store: store, monitor: monitor)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding()
        .frame(width: 620, height: 440)
    }
}

// MARK: - Apps

private struct AppsTab: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    @State private var selection: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.apps) { app in
                        HStack {
                            AppIcon(bundleID: app.bundleID)
                            Text(app.name)
                            Spacer()
                            if let badge = monitor.badges[app.bundleID] {
                                Text(badge.label)
                                    .font(.caption.monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .background(Capsule().fill(Color.red.opacity(0.85)))
                                    .foregroundStyle(.white)
                            }
                        }
                        .tag(app.bundleID)
                    }
                    .onMove { store.apps.move(fromOffsets: $0, toOffset: $1) }
                }
                .overlay {
                    if store.apps.isEmpty {
                        Text("Add apps to keep them in the menu bar.\nBadged apps also appear automatically.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                Divider()
                HStack(spacing: 0) {
                    addMenu
                    Button {
                        store.apps.removeAll { $0.bundleID == selection }
                        selection = nil
                    } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 230)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))

            if let index = store.apps.firstIndex(where: { $0.bundleID == selection }) {
                AppDetail(app: $store.apps[index], groups: store.groups)
            } else {
                Text("Select an app to customize its badge.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var addMenu: some View {
        Menu {
            let candidates = monitor.entries.filter { !store.isTracked($0.bundleID) }
            Section("From the Dock") {
                if candidates.isEmpty {
                    Text("No other Dock apps")
                }
                ForEach(candidates, id: \.bundleID) { entry in
                    Button(entry.name) {
                        store.track(bundleID: entry.bundleID, name: entry.name)
                        selection = entry.bundleID
                    }
                }
            }
            Divider()
            Button("Choose Application…", action: chooseApplication)
        } label: {
            Image(systemName: "plus").frame(width: 24, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            store.track(bundleID: id, name: name)
            selection = id
        }
    }
}

private struct AppDetail: View {
    @Binding var app: TrackedApp
    let groups: [AppGroup]

    var body: some View {
        Form {
            Section {
                HStack {
                    AppIcon(bundleID: app.bundleID, size: 32)
                    TextField("Name", text: $app.name)
                }
            }
            AppearanceFields(appearance: $app.appearance)
            Section {
                Picker("Icon", selection: $app.iconStyle) {
                    ForEach(IconStyle.allCases) { Text($0.label).tag($0) }
                }
                if app.iconStyle == .custom {
                    HStack {
                        Text(app.customIconPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No image chosen")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Choose…", action: chooseIcon)
                    }
                }
                Picker("Group", selection: $app.groupID) {
                    Text("None").tag(UUID?.none)
                    ForEach(groups) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.customIconPath = url.path
    }
}

private struct AppearanceFields: View {
    @Binding var appearance: BadgeAppearance

    var body: some View {
        Section("Badge") {
            Picker("Style", selection: $appearance.style) {
                ForEach(BadgeStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            ColorPicker("Color", selection: $appearance.colorHex.color, supportsOpacity: false)
            Picker("When there's no badge", selection: $appearance.emptyBehavior) {
                ForEach(EmptyBehavior.allCases) { Text($0.label).tag($0) }
            }
        }
    }
}

// MARK: - Groups

private struct GroupsTab: View {
    @ObservedObject var store: Store
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.groups) { group in
                        Label(group.name, systemImage: group.symbol).tag(group.id)
                    }
                }
                .overlay {
                    if store.groups.isEmpty {
                        Text("Groups combine several apps\nunder one menu bar icon.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack(spacing: 0) {
                    Button {
                        let group = AppGroup(name: "New Group")
                        store.groups.append(group)
                        selection = group.id
                    } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                    Button {
                        if let selection { store.deleteGroup(selection) }
                        selection = nil
                    } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 230)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))

            if let index = store.groups.firstIndex(where: { $0.id == selection }) {
                GroupDetail(group: $store.groups[index], store: store)
            } else {
                Text("Select a group to edit it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct GroupDetail: View {
    @Binding var group: AppGroup
    @ObservedObject var store: Store

    private static let symbols = [
        "tray.full", "bubble.left.and.bubble.right", "envelope", "bell",
        "person.2", "briefcase", "message", "star",
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $group.name)
                Picker("Icon", selection: $group.symbol) {
                    ForEach(Self.symbols, id: \.self) { Label($0, systemImage: $0).tag($0) }
                }
            }
            AppearanceFields(appearance: $group.appearance)
            Section("Apps") {
                if store.apps.isEmpty {
                    Text("Add apps in the Apps tab first.").foregroundStyle(.secondary)
                }
                ForEach($store.apps) { $app in
                    Toggle(isOn: Binding(
                        get: { app.groupID == group.id },
                        set: { app.groupID = $0 ? group.id : nil }
                    )) {
                        HStack {
                            AppIcon(bundleID: app.bundleID)
                            Text(app.name)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Permissions") {
                HStack {
                    Image(systemName: monitor.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(monitor.isTrusted ? .green : .orange)
                    Text(monitor.isTrusted
                         ? "Accessibility access granted"
                         : "BadgeBar needs Accessibility access to read Dock badges")
                    Spacer()
                    if !monitor.isTrusted {
                        Button("Grant Access…") { DockReader.requestTrust() }
                    }
                }
            }
            Section("Behavior") {
                Toggle("Automatically show any app with a badge", isOn: $store.general.autoShowBadgedApps)
                Toggle("Show BadgeBar icon in menu bar", isOn: $store.general.showMainIcon)
                LabeledContent("Check for badges every") {
                    Stepper(
                        String(format: "%.1f s", store.general.pollInterval),
                        value: $store.general.pollInterval,
                        in: 0.5...10,
                        step: 0.5
                    )
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin, perform: setLaunchAtLogin)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Text("Badges come from the Dock, so apps must be running to report them. ⌘-drag menu bar icons to reorder them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
}

// MARK: - Shared

private struct AppIcon: View {
    let bundleID: String
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: size, height: size)
    }

    private var image: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
