import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Which settings page is showing. Shared so the menu bar can deep-link into a page.
@MainActor
final class SettingsRouter: ObservableObject {
    @Published var selection: SidebarItem? = .general
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    @ObservedObject var router: SettingsRouter
    var openGuide: () -> Void

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, monitor: monitor, selection: $router.selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            detail
                .frame(minWidth: 460)
        }
        .frame(minWidth: 720, minHeight: 520)
        .tint(.brand)
    }

    @ViewBuilder
    private var detail: some View {
        switch router.selection {
        case let .app(id):
            if let binding = appBinding(id) {
                AppPane(app: binding, store: store, monitor: monitor) {
                    store.apps.removeAll { $0.bundleID == id }
                    router.selection = .general
                }
                .id(id)
            } else {
                placeholder
            }
        case let .group(id):
            if let binding = groupBinding(id) {
                GroupPane(group: binding, store: store, monitor: monitor) {
                    store.deleteGroup(id)
                    router.selection = .general
                }
                .id(id)
            } else {
                placeholder
            }
        case .general, .none:
            GeneralPane(store: store, monitor: monitor, openGuide: openGuide)
        }
    }

    private var placeholder: some View {
        ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left", description: Text("Choose an item in the sidebar."))
    }

    // Bindings that look items up by id, so a page never indexes into a stale array position.
    private func appBinding(_ id: String) -> Binding<TrackedApp>? {
        guard let current = store.apps.first(where: { $0.bundleID == id }) else { return nil }
        return Binding(
            get: { store.apps.first(where: { $0.bundleID == id }) ?? current },
            set: { new in
                if let i = store.apps.firstIndex(where: { $0.bundleID == id }) { store.apps[i] = new }
            }
        )
    }

    private func groupBinding(_ id: UUID) -> Binding<AppGroup>? {
        guard let current = store.groups.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.groups.first(where: { $0.id == id }) ?? current },
            set: { new in
                if let i = store.groups.firstIndex(where: { $0.id == id }) { store.groups[i] = new }
            }
        )
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Label {
                Text("General")
            } icon: {
                SidebarSymbol(name: "gearshape.fill", color: .gray)
            }
            .tag(SidebarItem.general)

            Section("Menu Bar Apps") {
                ForEach(store.apps.filter { $0.groupID == nil }) { app in
                    appRow(app)
                }
                .onMove(perform: moveUngrouped)

                if store.apps.isEmpty {
                    Text("No apps yet")
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
            }

            ForEach(store.groups) { group in
                Section {
                    Label {
                        HStack {
                            Text(group.name)
                            Spacer()
                            badgeLabel(Badge.combine(store.members(of: group).compactMap { monitor.badges[$0.bundleID] }))
                        }
                    } icon: {
                        SidebarSymbol(name: group.symbol, color: Color(nsColor: NSColor(hex: group.appearance.colorHex) ?? .systemBlue))
                    }
                    .tag(SidebarItem.group(group.id))
                    .contextMenu { groupMenu(group) }

                    ForEach(store.members(of: group)) { app in
                        appRow(app).padding(.leading, 12)
                    }
                } header: {
                    Text("Group")
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand(perform: deleteSelection)
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private func appRow(_ app: TrackedApp) -> some View {
        Label {
            HStack {
                Text(app.name).lineLimit(1)
                Spacer()
                badgeLabel(monitor.badges[app.bundleID])
            }
        } icon: {
            AppIconView(bundleID: app.bundleID, size: 20)
        }
        .tag(SidebarItem.app(app.bundleID))
        .contextMenu {
            Button("Open \(app.name)") { AppIcons.open(app.bundleID) }
            Divider()
            Menu("Move to Group") {
                Button("None") { setGroup(app.bundleID, nil) }
                ForEach(store.groups) { group in
                    Button(group.name) { setGroup(app.bundleID, group.id) }
                }
            }
            Divider()
            Button("Remove from Menu Bar", role: .destructive) { remove(.app(app.bundleID)) }
        }
    }

    @ViewBuilder
    private func badgeLabel(_ badge: Badge?) -> some View {
        if let badge {
            Text(badge.count == nil ? "•" : BadgeRenderer.displayLabel(badge))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private func groupMenu(_ group: AppGroup) -> some View {
        Button("Delete Group", role: .destructive) { remove(.group(group.id)) }
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            Menu {
                let candidates = monitor.entries.filter { !store.isTracked($0.bundleID) }
                Section("Apps in the Dock") {
                    if candidates.isEmpty {
                        Text(monitor.isTrusted ? "All Dock apps added" : "Needs Accessibility access")
                    }
                    ForEach(candidates, id: \.bundleID) { entry in
                        Button {
                            store.track(bundleID: entry.bundleID, name: entry.name)
                            selection = .app(entry.bundleID)
                        } label: {
                            Label {
                                Text(entry.badge.map { "\(entry.name)  (\($0.label))" } ?? entry.name)
                            } icon: {
                                Image(nsImage: AppIcons.icon(for: entry.bundleID))
                            }
                        }
                    }
                }
                Button("Other Application…", action: chooseApplication)
                Divider()
                Button("New Group") {
                    let group = AppGroup(name: "New Group")
                    store.groups.append(group)
                    selection = .group(group.id)
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add an app or group")

            Button {
                deleteSelection()
            } label: {
                Label("Remove", systemImage: "minus")
            }
            .disabled(!canDelete)
            .help("Remove the selected item")

            Spacer()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.large)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canDelete: Bool {
        switch selection {
        case .app, .group: return true
        default: return false
        }
    }

    private func deleteSelection() {
        guard let selection, canDelete else { return }
        remove(selection)
    }

    private func remove(_ item: SidebarItem) {
        // Keep keyboard focus useful: select the neighbouring row after deleting.
        let order = rowOrder
        let index = order.firstIndex(of: item)
        switch item {
        case let .app(id): store.apps.removeAll { $0.bundleID == id }
        case let .group(id): store.deleteGroup(id)
        case .general: return
        }
        let remaining = rowOrder
        if let index, !remaining.isEmpty {
            selection = remaining[min(index, remaining.count - 1)]
        } else {
            selection = .general
        }
    }

    private var rowOrder: [SidebarItem] {
        var rows: [SidebarItem] = [.general]
        rows += store.apps.filter { $0.groupID == nil }.map { .app($0.bundleID) }
        for group in store.groups {
            rows.append(.group(group.id))
            rows += store.members(of: group).map { .app($0.bundleID) }
        }
        return rows
    }

    private func setGroup(_ bundleID: String, _ group: UUID?) {
        if let i = store.apps.firstIndex(where: { $0.bundleID == bundleID }) {
            store.apps[i].groupID = group
        }
    }

    private func moveUngrouped(from source: IndexSet, to destination: Int) {
        var ungrouped = store.apps.filter { $0.groupID == nil }
        ungrouped.move(fromOffsets: source, toOffset: destination)
        store.apps = ungrouped + store.apps.filter { $0.groupID != nil }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            store.track(bundleID: id, name: name)
            selection = .app(id)
        }
    }
}

/// A white SF Symbol on a colored rounded square, like System Settings' sidebar icons.
private struct SidebarSymbol: View {
    let name: String
    let color: Color

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.gradient))
    }
}

// MARK: - App page

private struct AppPane: View {
    @Binding var app: TrackedApp
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    let remove: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppIconView(bundleID: app.bundleID, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.title2.weight(.semibold))
                        Text(status)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Button("Open") { AppIcons.open(app.bundleID) }
                        .nativeButton()
                }
                .padding(.vertical, 4)

                BadgePreview(icon: AppIcons.menuBarIcon(for: app), appearance: app.appearance, badge: monitor.badges[app.bundleID])
            }

            Section("Badge") {
                StylePicker(appearance: $app.appearance, icon: AppIcons.menuBarIcon(for: app))
                LabeledContent("Color") { ColorSwatches(hex: $app.appearance.colorHex) }
                Picker("When nothing is new", selection: $app.appearance.emptyBehavior) {
                    ForEach(EmptyBehavior.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Icon") {
                Picker("Icon", selection: $app.iconStyle) {
                    ForEach(IconStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if app.iconStyle == .custom {
                    LabeledContent("Image") {
                        HStack {
                            Text(app.customIconPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button("Choose…", action: chooseIcon)
                        }
                    }
                }
            }

            Section("Organization") {
                TextField("Name", text: $app.name)
                Picker("Group", selection: $app.groupID) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.groups) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Remove from Menu Bar", role: .destructive, action: remove)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(app.name)
    }

    private var status: String {
        guard AppIcons.isRunning(app.bundleID) else { return "Not running — open it to receive badges" }
        guard let badge = monitor.badges[app.bundleID] else { return "Running · No new notifications" }
        guard let count = badge.count else { return "Running · New activity" }
        return "Running · \(count) unread"
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.customIconPath = url.path
    }
}

// MARK: - Group page

private struct GroupPane: View {
    @Binding var group: AppGroup
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    let remove: () -> Void

    private static let symbols = [
        "tray.full", "bubble.left.and.bubble.right.fill", "envelope.fill", "bell.fill",
        "person.2.fill", "briefcase.fill", "message.fill", "star.fill",
        "house.fill", "gamecontroller.fill", "phone.fill", "megaphone.fill",
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: group.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .glassSurface(cornerRadius: 14, tint: color.opacity(0.35))
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Group name", text: $group.name)
                            .textFieldStyle(.plain)
                            .font(.title2.weight(.semibold))
                        Text("\(store.members(of: group).count) apps · shown as one icon")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                BadgePreview(
                    icon: AppIcons.symbol(group.symbol),
                    appearance: group.appearance,
                    badge: Badge.combine(store.members(of: group).compactMap { monitor.badges[$0.bundleID] })
                )
            }

            Section("Symbol") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        let selected = group.symbol == symbol
                        Button {
                            withAnimation(.snappy) { group.symbol = symbol }
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 15))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selected ? Color.brand.opacity(0.18) : Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(selected ? Color.brand : .clear, lineWidth: 1.5)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Badge") {
                StylePicker(appearance: $group.appearance, icon: AppIcons.symbol(group.symbol))
                LabeledContent("Color") { ColorSwatches(hex: $group.appearance.colorHex) }
                Picker("When nothing is new", selection: $group.appearance.emptyBehavior) {
                    ForEach(EmptyBehavior.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                if store.apps.isEmpty {
                    Text("Add apps to the menu bar first, then include them here.")
                        .foregroundStyle(.secondary)
                }
                ForEach($store.apps) { $app in
                    Toggle(isOn: Binding(
                        get: { app.groupID == group.id },
                        set: { app.groupID = $0 ? group.id : nil }
                    )) {
                        Label {
                            Text(app.name)
                        } icon: {
                            AppIconView(bundleID: app.bundleID)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            } header: {
                Text("Apps in This Group")
            } footer: {
                Text("Hover over the group's icon to see each app's notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Delete Group", role: .destructive, action: remove)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(group.name)
    }

    private var color: Color { Color(nsColor: NSColor(hex: group.appearance.colorHex) ?? .systemBlue) }
}

// MARK: - General page

private struct GeneralPane: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    var openGuide: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess

    private static let intervals: [(String, Double)] = [
        ("Every half second", 0.5), ("Every second", 1), ("Every 1.5 seconds", 1.5),
        ("Every 3 seconds", 3), ("Every 5 seconds", 5),
    ]

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Reads unread counts from Dock icons.",
                    symbol: "accessibility",
                    granted: monitor.isTrusted,
                    action: openGuide
                )
                PermissionRow(
                    title: "Full Disk Access",
                    detail: "Shows message previews from Notification Center.",
                    symbol: "text.bubble",
                    granted: hasFullDiskAccess,
                    optional: true,
                    action: Permissions.openFullDiskAccessSettings
                )
            } header: {
                Text("Permissions")
            } footer: {
                Text("Everything stays on your Mac. BadgeBar never connects to the internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Show apps automatically when they have notifications", isOn: $store.general.autoShowBadgedApps)
                Toggle("Show BadgeBar icon", isOn: $store.general.showMainIcon)
            }

            Section("Previews") {
                Toggle("Preview notifications on hover", isOn: $store.general.showHoverPreviews)
                Toggle("Include message content", isOn: $store.general.showMessageContent)
                    .disabled(!store.general.showHoverPreviews)
            }

            Section("System") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Picker("Check for badges", selection: $store.general.pollInterval) {
                    ForEach(Self.intervals, id: \.1) { Text($0.0).tag($0.1) }
                }
            }

            Section {
                LabeledContent("Welcome guide") {
                    Button("Show…", action: openGuide)
                }
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            } footer: {
                Text("Tip: hold ⌘ and drag menu bar icons to rearrange them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Permissions.hasFullDiskAccess
        }
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
