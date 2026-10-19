import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Which settings page is showing. Shared so the menu bar can deep-link into a page.
@MainActor
final class SettingsRouter: ObservableObject {
    @Published var selection: SidebarItem? = .menuBar
    @Published var addingApps = false
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    @ObservedObject var router: SettingsRouter
    var openGuide: () -> Void

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, monitor: monitor, selection: $router.selection, addingApps: $router.addingApps)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            detail
                .frame(minWidth: 460)
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(WindowTitle(title: pageTitle))
        .sheet(isPresented: $router.addingApps) {
            AddAppsSheet(store: store, monitor: monitor) { added in
                if let added { router.selection = .app(added) }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch router.selection {
        case let .app(id):
            if let binding = appBinding(id) {
                AppPane(app: binding, store: store, monitor: monitor) {
                    store.apps.removeAll { $0.bundleID == id }
                    router.selection = .menuBar
                }
                .id(id)
            } else {
                placeholder
            }
        case let .group(id):
            if let binding = groupBinding(id) {
                GroupPane(group: binding, store: store, monitor: monitor) {
                    store.deleteGroup(id)
                    router.selection = .menuBar
                }
                .id(id)
            } else {
                placeholder
            }
        case .menuBar, .none:
            MenuBarPane(store: store, monitor: monitor, select: { router.selection = $0 }) {
                router.addingApps = true
            }
        case .general:
            GeneralPane(store: store, monitor: monitor, openGuide: openGuide)
        }
    }

    /// The page name, shown in the window's toolbar like System Settings.
    private var pageTitle: String {
        switch router.selection {
        case .menuBar, .none: "Menu Bar"
        case .general: "General"
        case let .app(id): store.apps.first { $0.bundleID == id }?.name ?? "BadgeBar"
        case let .group(id): store.groups.first { $0.id == id }?.name ?? "Group"
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
    @Binding var addingApps: Bool

    var body: some View {
        List(selection: $selection) {
            Label {
                Text("Menu Bar")
            } icon: {
                SidebarSymbol(name: "menubar.rectangle", color: .brand)
            }
            .tag(SidebarItem.menuBar)

            Label {
                Text("General")
            } icon: {
                SidebarSymbol(name: "gearshape.fill", color: .gray)
            }
            .tag(SidebarItem.general)

            Section("Apps") {
                ForEach(store.apps.filter { $0.groupID == nil }) { app in
                    appRow(app)
                }
                .onMove(perform: moveUngrouped)

                addRow("Add Apps…") { addingApps = true }
            }

            Section("Groups") {
                ForEach(store.groups) { group in
                    Label {
                        HStack {
                            Text(group.name)
                            Spacer()
                            badgeLabel(Badge.combine(store.members(of: group).compactMap { monitor.badges[$0.bundleID] }))
                        }
                    } icon: {
                        SidebarSymbol(name: group.symbol, color: .gray)
                    }
                    .tag(SidebarItem.group(group.id))
                    .contextMenu { groupMenu(group) }

                    ForEach(store.members(of: group)) { app in
                        appRow(app).padding(.leading, 12)
                    }
                }

                addRow("New Group") {
                    selection = .group(store.addGroup().id)
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand(perform: deleteSelection)
        .acceptsDroppedApps(into: store) { added in
            if let added { selection = .app(added) }
        }
    }

    /// An always-visible action row, so adding things never hides behind a small + button.
    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
            }
            .foregroundStyle(Color.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectionDisabled()
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
        case .menuBar, .general: return
        }
        let remaining = rowOrder
        if let index, !remaining.isEmpty {
            selection = remaining[min(index, remaining.count - 1)]
        } else {
            selection = .menuBar
        }
    }

    private var rowOrder: [SidebarItem] {
        var rows: [SidebarItem] = [.menuBar, .general]
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
}

/// Picker options for an app's nothing-new rule, spelling out what "Use Default" means.
private struct EmptyBehaviorOptions: View {
    let global: EmptyBehavior

    var body: some View {
        Text("Use Default (\(global.label))").tag(EmptyBehavior.useDefault)
        Divider()
        ForEach(EmptyBehavior.concrete) { Text($0.label).tag($0) }
    }
}

/// A white SF Symbol on a colored rounded square, like System Settings' sidebar icons.
private struct SidebarSymbol: View {
    let name: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(color.gradient))
    }
}

// MARK: - Menu Bar page

/// The landing page: what's in the menu bar now, and the quickest ways to add more.
private struct MenuBarPane: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    let select: (SidebarItem) -> Void
    let addApps: () -> Void

    /// Looked up once; scanning installed apps on every redraw would be wasteful.
    @State private var suggestions: [AppInfo] = []

    var body: some View {
        Form {
            Section {
                if stripItems.isEmpty {
                    Text("Nothing in the menu bar yet.").foregroundStyle(.secondary)
                } else {
                    ReorderStrip(items: stripItems, move: move) { id in
                        if id.hasPrefix("app.") { select(.app(String(id.dropFirst(4)))) }
                        if id.hasPrefix("group."), let uuid = UUID(uuidString: String(id.dropFirst(6))) { select(.group(uuid)) }
                    }
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("New Group") { select(.group(store.addGroup().id)) }
                        .nativeButton()
                    Button(action: addApps) {
                        Label("Add Apps…", systemImage: "plus")
                    }
                    .nativeButton(prominent: true)
                }
            } header: {
                Text("Arrange")
            } footer: {
                FooterNote("Drag icons left or right to arrange them; the menu bar follows. You can also hold ⌘ and drag icons in the menu bar itself.")
            }

            Section {
                if store.apps.isEmpty && store.groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Apps Yet", systemImage: "menubar.rectangle")
                    } description: {
                        Text("Add the apps whose unread counts you want to see, or drag apps here from Finder.")
                    }
                }
                ForEach(store.apps.filter { $0.groupID == nil }) { app in
                    row(.app(app.bundleID)) {
                        AppIconView(bundleID: app.bundleID, size: 28)
                    } title: {
                        Text(app.name)
                    } detail: {
                        status(app.bundleID)
                    }
                }
                ForEach(store.groups) { group in
                    let members = store.members(of: group)
                    row(.group(group.id)) {
                        SidebarSymbol(name: group.symbol, color: .gray, size: 28)
                    } title: {
                        Text(group.name)
                    } detail: {
                        Text(members.isEmpty ? "No apps" : members.map(\.name).formatted(.list(type: .and)))
                    }
                }
            } header: {
                Text("In Your Menu Bar")
            }

            let available = suggestions.filter { !store.isTracked($0.bundleID) }
            if !available.isEmpty {
                Section {
                    ForEach(available) { app in
                        HStack(spacing: 10) {
                            AppIconView(bundleID: app.bundleID, size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(app.name)
                                if let category = app.category {
                                    Text(category.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let badge = monitor.badges[app.bundleID] { CountPill(badge: badge) }
                            Button("Add") {
                                store.track(bundleID: app.bundleID, name: app.name)
                            }
                            .nativeButton()
                            .accessibilityLabel("Add \(app.name)")
                        }
                    }
                } header: {
                    Text("Suggested Apps")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Menu Bar")
        .acceptsDroppedApps(into: store) { _ in }
        .onAppear {
            suggestions = AppCatalog.suggestions().filter { $0.category != .apple }
        }
    }

    /// Every app and group in menu bar order, drawn the way the menu bar draws them.
    private var stripItems: [ReorderStrip.Item] {
        let badges = store.visibleBadges(monitor.badges)
        let apps = store.apps.filter { $0.groupID == nil }.map { app in
            let appearance = app.appearance.resolved(store.general)
            let badge = badges[app.bundleID]
            return ReorderStrip.Item(
                id: "app.\(app.bundleID)",
                name: app.name,
                image: BadgeRenderer.image(icon: AppIcons.menuBarIcon(for: app), badge: badge, appearance: appearance),
                hidden: badge == nil && appearance.emptyBehavior == .hide
            )
        }
        let groups = store.groups.map { group in
            let appearance = group.appearance.resolved(store.general)
            let badge = Badge.combine(store.members(of: group).compactMap { badges[$0.bundleID] })
            return ReorderStrip.Item(
                id: "group.\(group.id.uuidString)",
                name: group.name,
                image: BadgeRenderer.image(icon: AppIcons.symbol(group.symbol), badge: badge, appearance: appearance),
                hidden: badge == nil && appearance.emptyBehavior == .hide
            )
        }
        return apps + groups
    }

    /// Applies a new strip order. The menu bar shows apps before groups, so each kind keeps
    /// its own run of positions.
    private func move(_ order: [String]) {
        store.reorder(byKeys: order)
    }

    private func status(_ bundleID: String) -> Text {
        if let badge = store.visibleBadge(for: bundleID, monitor.badges[bundleID]) {
            return Text(badge.count.map { "\($0) unread" } ?? "New activity")
        }
        return Text(AppIcons.isRunning(bundleID) ? "Nothing new" : "Not running")
    }

    /// A navigation row, like System Settings: tapping anywhere opens the item's page.
    private func row(
        _ item: SidebarItem,
        @ViewBuilder icon: () -> some View,
        @ViewBuilder title: () -> some View,
        @ViewBuilder detail: () -> some View
    ) -> some View {
        Button {
            select(item)
        } label: {
            HStack(spacing: 10) {
                icon()
                VStack(alignment: .leading, spacing: 0) {
                    title()
                    detail().font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App page

private struct AppPane: View {
    @Binding var app: TrackedApp
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    let remove: () -> Void

    @State private var confirmingRemoval = false

    var body: some View {
        Form {
            Section {
                PaneHeader(subtitle: status) {
                    AppIconView(bundleID: app.bundleID, size: 52)
                } title: {
                    Text(app.name)
                } trailing: {
                    Button("Open") { AppIcons.open(app.bundleID) }
                        .nativeButton()
                }
            }

            Section("Appearance") {
                LabeledContent("Style") {
                    StylePicker(appearance: $app.appearance, icon: AppIcons.menuBarIcon(for: app))
                }
                LabeledContent("Color") { ColorSwatches(hex: $app.appearance.colorHex) }
                Picker("When nothing is new", selection: $app.appearance.emptyBehavior) {
                    EmptyBehaviorOptions(global: store.general.emptyBehavior)
                }
                Picker("Icon", selection: $app.iconStyle) {
                    ForEach(IconStyle.allCases) { Text($0.label).tag($0) }
                }
                if app.iconStyle == .custom {
                    LabeledContent("Image") {
                        HStack(spacing: 8) {
                            Text(app.customIconPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button("Choose…", action: chooseIcon)
                                .nativeButton()
                        }
                    }
                }
            }

            Section("Details") {
                TextField("Name", text: $app.name)
                Picker("Group", selection: $app.groupID) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.groups) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Remove from Menu Bar…", role: .destructive) { confirmingRemoval = true }
                        .nativeButton()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(app.name)
        .confirmationDialog("Remove \(app.name) from the menu bar?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive, action: remove)
        } message: {
            Text("You can add it again at any time.")
        }
    }

    private var status: String {
        guard AppIcons.isRunning(app.bundleID) else { return "Not running · open it to receive badges" }
        guard let badge = monitor.badges[app.bundleID] else { return "Running · Nothing new" }
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

    @State private var confirmingRemoval = false

    private static let symbols: [(name: String, title: String)] = [
        ("tray.full.fill", "Inbox"), ("bubble.left.and.bubble.right.fill", "Chats"),
        ("message.fill", "Message"), ("envelope.fill", "Mail"), ("bell.fill", "Bell"),
        ("person.2.fill", "People"), ("briefcase.fill", "Work"), ("house.fill", "Home"),
        ("star.fill", "Star"), ("phone.fill", "Phone"), ("megaphone.fill", "Announcements"),
        ("gamecontroller.fill", "Games"),
    ]

    var body: some View {
        Form {
            Section {
                PaneHeader(subtitle: memberSummary) {
                    // Same squircle as the sidebar, at header size.
                    Image(systemName: group.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.gray.gradient))
                } title: {
                    TextField("Group Name", text: $group.name, prompt: Text("Group Name"))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                } trailing: {
                    EmptyView()
                }
            } footer: {
                FooterNote("A group shows several apps as one menu bar icon, with their unread counts added together.")
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
                }
            } header: {
                Text("Apps in This Group")
            }

            Section("Appearance") {
                Picker("Symbol", selection: $group.symbol) {
                    ForEach(Self.symbols, id: \.name) { Label($0.title, systemImage: $0.name).tag($0.name) }
                }
                LabeledContent("Style") {
                    StylePicker(appearance: $group.appearance, icon: AppIcons.symbol(group.symbol))
                }
                LabeledContent("Color") { ColorSwatches(hex: $group.appearance.colorHex) }
                Picker("When nothing is new", selection: $group.appearance.emptyBehavior) {
                    EmptyBehaviorOptions(global: store.general.emptyBehavior)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Delete Group…", role: .destructive) { confirmingRemoval = true }
                        .nativeButton()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(group.name.isEmpty ? "Group" : group.name)
        .confirmationDialog("Delete the group “\(group.name)”?", isPresented: $confirmingRemoval) {
            Button("Delete Group", role: .destructive, action: remove)
        } message: {
            Text("Its apps go back to having their own menu bar icons.")
        }
    }

    private var memberSummary: String {
        let members = store.members(of: group)
        switch members.count {
        case 0: return "No apps yet · choose them below"
        case 1: return "1 app · shown as one icon"
        default: return "\(members.count) apps · shown as one icon"
        }
    }
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
                    actionTitle: "Set Up…",
                    action: openGuide
                )
                PermissionRow(
                    title: "Full Disk Access",
                    detail: "Shows message previews from Notification Center.",
                    symbol: "text.bubble",
                    granted: hasFullDiskAccess,
                    optional: true,
                    actionTitle: "Open Settings…",
                    action: Permissions.openFullDiskAccessSettings
                )
            } header: {
                Text("Permissions")
            }

            Section {
                Picker("When nothing is new", selection: $store.general.emptyBehavior) {
                    ForEach(EmptyBehavior.concrete) { Text($0.label).tag($0) }
                }
                Toggle("Show apps automatically when they have notifications", isOn: $store.general.autoShowBadgedApps)
                Toggle("Always show BadgeBar icon", isOn: $store.general.showMainIcon)
                Picker("Refresh badges", selection: $store.general.pollInterval) {
                    ForEach(Self.intervals, id: \.1) { Text($0.0).tag($0.1) }
                }
            } header: {
                Text("Menu Bar")
            } footer: {
                FooterNote("Apps can override what happens when nothing is new on their own pages. Refreshing less often uses a little less energy.")
            }

            Section {
                Toggle("Preview notifications on hover", isOn: $store.general.showHoverPreviews)
                Toggle("Show message text", isOn: $store.general.showMessageContent)
            } header: {
                Text("Previews")
            } footer: {
                FooterNote("Message text comes from Notification Center and needs Full Disk Access. It's read on your Mac and never leaves it.")
            }

            Section("About") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Welcome guide") {
                    Button("Show…", action: openGuide)
                        .nativeButton()
                }
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Permissions.hasFullDiskAccess
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // Also called when the toggle catches up with a change made in System Settings.
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
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

/// A section footer note, leading-aligned like System Settings.
private struct FooterNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sets the hosting window's title. The window is created by AppKit, so SwiftUI's
/// `navigationTitle` doesn't reach its toolbar on its own.
private struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.title = title }
    }
}
