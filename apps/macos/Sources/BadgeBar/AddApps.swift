import SwiftUI
import UniformTypeIdentifiers

/// Searchable app chooser: suggested messaging and work apps first, then Dock apps,
/// then everything installed. Used by onboarding (as a grid) and settings (as a list).
struct AppChooser: View {
    enum Layout { case grid, list }

    @Binding var selection: Set<String>
    let excluded: Set<String>
    let dockApps: [DockEntry]
    let badges: [String: Badge]
    var layout: Layout = .list

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private struct Section: Identifiable {
        let id: String
        let title: String
        let apps: [AppInfo]
    }

    var body: some View {
        VStack(spacing: 12) {
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            content(for: section.apps)
                        }
                    }
                    if sections.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear { searchFocused = layout == .list }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search apps", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.cardFill))
        .overlay(Capsule().strokeBorder(searchFocused ? Color.brand.opacity(0.6) : .clear, lineWidth: 2))
        .animation(.feedback, value: searchFocused)
    }

    @ViewBuilder
    private func content(for apps: [AppInfo]) -> some View {
        switch layout {
        case .grid:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(apps) { app in
                    AppChoiceTile(app: app, badge: badges[app.bundleID], isOn: selection.contains(app.bundleID)) {
                        toggle(app.bundleID)
                    }
                }
            }
        case .list:
            VStack(spacing: 2) {
                ForEach(apps) { app in
                    AppChoiceRow(app: app, badge: badges[app.bundleID], isOn: selection.contains(app.bundleID)) {
                        toggle(app.bundleID)
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private var sections: [Section] {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            let results = AppCatalog.search(query).filter { !excluded.contains($0.bundleID) }
            return results.isEmpty ? [] : [Section(id: "results", title: "Results", apps: results)]
        }

        var shown = excluded
        func take(_ apps: [AppInfo]) -> [AppInfo] {
            apps.filter { shown.insert($0.bundleID).inserted }
        }

        let suggested = AppCatalog.suggestions()
        let messaging = take(suggested.filter { $0.category != .apple })
        let dock = take(dockApps.map {
            AppInfo(bundleID: $0.bundleID, name: $0.name, url: $0.url, category: nil)
        })
        let apple = take(suggested.filter { $0.category == .apple })
        let rest = take(AppCatalog.installed())

        return [
            Section(id: "suggested", title: "Suggested — Messaging & Work", apps: messaging),
            Section(id: "dock", title: "In Your Dock", apps: dock),
            Section(id: "apple", title: "Apple Apps", apps: apple),
            Section(id: "all", title: "All Applications", apps: rest),
        ].filter { !$0.apps.isEmpty }
    }
}

private struct AppChoiceTile: View {
    let app: AppInfo
    let badge: Badge?
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                AppIconView(bundleID: app.bundleID, size: 44)
                    .overlay(alignment: .topTrailing) {
                        if let badge { CountPill(badge: badge).offset(x: 6, y: -4) }
                    }
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(alignment: .topLeading) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.brand : Color.secondary.opacity(0.5))
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? Color.brand.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? Color.brand.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: isOn ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.feedback, value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct AppChoiceRow: View {
    let app: AppInfo
    let badge: Badge?
    let isOn: Bool
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.brand : Color.secondary.opacity(0.5))
                AppIconView(bundleID: app.bundleID, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.name)
                    if let category = app.category, category != .apple {
                        Text(category.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let badge { CountPill(badge: badge) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.brand.opacity(0.1) : Color.primary.opacity(hovering ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The settings sheet for adding several apps at once.
struct AddAppsSheet: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    var onAdd: (_ firstAdded: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Apps to the Menu Bar").font(.title3.weight(.semibold))
                Text("Pick the apps whose unread counts you want to see. You can also drag apps from Finder onto the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            AppChooser(
                selection: $selection,
                excluded: Set(store.apps.map(\.bundleID)),
                dockApps: monitor.entries,
                badges: monitor.badges
            )
            .padding(.horizontal, 20)

            Divider()
            HStack {
                Text(selection.isEmpty ? "" : "\(selection.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .nativeButton()
                    .keyboardShortcut(.cancelAction)
                Button(selection.isEmpty ? "Add" : "Add \(selection.count) App\(selection.count == 1 ? "" : "s")") {
                    let added = store.track(bundleIDs: selection, names: names(for: selection))
                    onAdd(added.first)
                    dismiss()
                }
                .nativeButton(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 500, height: 600)
        .tint(.brand)
    }

    private func names(for ids: Set<String>) -> [String: String] {
        AppChooser.names(for: ids, dockApps: monitor.entries)
    }
}

extension AppChooser {
    /// Display names for chosen apps, preferring the Dock's name when the app is there.
    @MainActor
    static func names(for ids: Set<String>, dockApps: [DockEntry]) -> [String: String] {
        var names: [String: String] = [:]
        for id in ids {
            names[id] = dockApps.first { $0.bundleID == id }?.name ?? AppCatalog.info(for: id)?.name ?? id
        }
        return names
    }
}

extension View {
    /// Accepts .app bundles dragged from Finder and adds them to the menu bar.
    func acceptsDroppedApps(into store: Store, onAdd: @escaping (String?) -> Void) -> some View {
        dropDestination(for: URL.self) { urls, _ in
            var names: [String: String] = [:]
            for url in urls where url.pathExtension == "app" {
                if let id = Bundle(url: url)?.bundleIdentifier {
                    names[id] = url.deletingPathExtension().lastPathComponent
                }
            }
            guard !names.isEmpty else { return false }
            let added = store.track(bundleIDs: Set(names.keys), names: names)
            onAdd(added.first)
            return true
        }
    }
}
