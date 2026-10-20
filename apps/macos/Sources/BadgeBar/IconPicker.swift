import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// An icon chosen for an app or group in place of its usual one.
enum CustomIcon: Equatable {
    case symbol(String)
    /// A copy of the image in BadgeBar's own folder.
    case image(path: String)
}

// MARK: - Symbol catalog

/// Every SF Symbol on this Mac, with Apple's categories and search keywords, read from the
/// same data the SF Symbols app uses. Loaded on first use and kept; it's a few hundred KB.
@MainActor
enum SymbolCatalog {
    struct Category: Identifiable, Hashable {
        let id: String
        let title: String
        let symbol: String
    }

    /// Symbols that read well at menu bar size, for the first page of the picker.
    static let suggested: [String] = [
        "tray.full.fill", "bubble.left.and.bubble.right.fill", "message.fill", "envelope.fill",
        "bell.fill", "bell.badge.fill", "at", "paperplane.fill", "phone.fill", "video.fill",
        "person.fill", "person.2.fill", "person.3.fill", "briefcase.fill", "building.2.fill",
        "house.fill", "graduationcap.fill", "calendar", "checklist", "list.bullet.rectangle.fill",
        "doc.text.fill", "folder.fill", "tray.2.fill", "archivebox.fill", "megaphone.fill",
        "newspaper.fill", "globe", "network", "terminal.fill", "chevron.left.forwardslash.chevron.right",
        "hammer.fill", "wrench.and.screwdriver.fill", "gearshape.fill", "cpu.fill", "server.rack",
        "cart.fill", "bag.fill", "creditcard.fill", "dollarsign.circle.fill", "chart.line.uptrend.xyaxis",
        "gamecontroller.fill", "music.note", "play.rectangle.fill", "camera.fill", "photo.fill",
        "heart.fill", "star.fill", "flag.fill", "bookmark.fill", "tag.fill", "bolt.fill", "flame.fill",
        "sparkles", "leaf.fill", "sun.max.fill", "moon.fill", "cloud.fill", "airplane", "car.fill",
        "cup.and.saucer.fill", "fork.knife", "pawprint.fill", "lightbulb.fill", "lock.fill",
    ].filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }

    static let categories: [Category] = [
        Category(id: "suggested", title: "Suggested", symbol: "star"),
        Category(id: "all", title: "All", symbol: "square.grid.2x2"),
        Category(id: "communication", title: "Communication", symbol: "message"),
        Category(id: "objectsandtools", title: "Objects", symbol: "folder"),
        Category(id: "devices", title: "Devices", symbol: "desktopcomputer"),
        Category(id: "human", title: "People", symbol: "person.crop.circle"),
        Category(id: "home", title: "Home", symbol: "house"),
        Category(id: "commerce", title: "Commerce", symbol: "cart"),
        Category(id: "time", title: "Time", symbol: "timer"),
        Category(id: "media", title: "Media", symbol: "playpause"),
        Category(id: "gaming", title: "Gaming", symbol: "gamecontroller"),
        Category(id: "connectivity", title: "Connectivity", symbol: "antenna.radiowaves.left.and.right"),
        Category(id: "transportation", title: "Travel", symbol: "car"),
        Category(id: "nature", title: "Nature", symbol: "leaf"),
        Category(id: "weather", title: "Weather", symbol: "cloud.sun"),
        Category(id: "health", title: "Health", symbol: "heart"),
        Category(id: "fitness", title: "Fitness", symbol: "figure.run"),
        Category(id: "shapes", title: "Shapes", symbol: "square.on.circle"),
        Category(id: "arrows", title: "Arrows", symbol: "arrow.forward"),
        Category(id: "indices", title: "Letters & Numbers", symbol: "a.circle"),
    ]

    private static let resources = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")

    /// Symbol names in Apple's order, without the per-language variants (".ar", ".hi", …).
    static let names: [String] = {
        guard let order = plist("symbol_order.plist") as? [String] else { return suggested }
        let languages: Set<String> = [
            "ar", "hi", "he", "th", "zh", "ja", "ko", "el", "ru", "my", "km", "mr", "bn", "gu", "kn",
            "ml", "or", "pa", "si", "ta", "te", "sat", "mni", "ur", "tr", "ckb", "nl", "fa", "ps",
            "sd", "ug", "dv", "ks", "uz", "az", "kk", "ky", "tg", "tk", "mn", "rtl", "ar.rtl",
        ]
        return order.filter { name in
            guard let last = name.split(separator: ".").last else { return false }
            return !languages.contains(String(last))
        }
    }()

    private static let categoriesByName = plist("symbol_categories.plist") as? [String: [String]] ?? [:]
    private static let keywordsByName = plist("symbol_search.plist") as? [String: [String]] ?? [:]

    private static func plist(_ name: String) -> Any? {
        guard let data = try? Data(contentsOf: resources.appendingPathComponent(name)) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    /// Symbols matching a search, or in a category when the search is empty.
    static func symbols(matching query: String, in category: String) -> [String] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "." }).map(String.init)
        guard !words.isEmpty else {
            switch category {
            case "suggested": return suggested
            case "all": return names
            default: return names.filter { categoriesByName[$0]?.contains(category) == true }
            }
        }
        // Names that match come before names found only through keywords.
        var byName: [String] = []
        var byKeyword: [String] = []
        for name in names {
            if words.allSatisfy({ name.contains($0) }) {
                byName.append(name)
            } else if let keywords = keywordsByName[name],
                      words.allSatisfy({ word in keywords.contains { $0.contains(word) } }) {
                byKeyword.append(name)
            }
        }
        return byName + byKeyword
    }
}

// MARK: - Icon well

/// A button showing the current icon. Clicking it opens the icon library.
struct IconWell: View {
    let image: NSImage
    @Binding var selection: CustomIcon?
    /// Apps whose icons are offered as images, e.g. a group's members.
    var apps: [String] = []
    /// What the library starts on when nothing is chosen yet.
    var initialTab: IconLibrary.Tab = .symbols
    /// Whether "Remove" clears the choice entirely (apps fall back to their own icon).
    var canRemove = true

    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 8) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(hovering ? 1 : 0.6)))
                Text(label)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            IconLibrary(selection: $selection, apps: apps, canRemove: canRemove, initialTab: startTab)
        }
        .accessibilityLabel("Icon: \(label)")
    }

    private var label: String {
        switch selection {
        case let .symbol(name): return name
        case .image: return "Image"
        case nil: return "Choose…"
        }
    }

    private var startTab: IconLibrary.Tab {
        switch selection {
        case .symbol: return .symbols
        case .image: return .image
        case nil: return initialTab
        }
    }
}

// MARK: - Editable header icon

/// A page's large header icon that can be changed in place, as in Contacts: hovering shows a
/// pencil, clicking opens the icon library, and an image can be dropped straight onto it.
struct EditableIcon<Content: View>: View {
    @Binding var selection: CustomIcon?
    var apps: [String] = []
    var canRemove = true
    @ViewBuilder let content: () -> Content

    @State private var showing = false
    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        Button { showing.toggle() } label: {
            content()
                .brightness(hovering ? -0.06 : 0)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor))
                        .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                        .offset(x: 4, y: 4)
                        .opacity(hovering || dropTargeted || showing ? 1 : 0)
                        .scaleEffect(hovering || dropTargeted || showing ? 1 : 0.8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: dropTargeted ? 2 : 0)
                        .padding(-3)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let path = AppIcons.importCustomIcon(from: url) else { return false }
            selection = .image(path: path)
            return true
        } isTargeted: { dropTargeted = $0 }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            IconLibrary(selection: $selection, apps: apps, canRemove: canRemove, initialTab: startTab)
        }
        .help("Change icon")
        .accessibilityLabel("Change icon")
    }

    private var startTab: IconLibrary.Tab {
        if case .image = selection { return .image }
        return .symbols
    }
}

// MARK: - Library

/// Browse SF Symbols or use an image, like the icon pickers in Reminders and Shortcuts.
/// Choices apply right away, so the menu bar and previews update while browsing.
struct IconLibrary: View {
    enum Tab: Hashable { case symbols, image }

    @Binding var selection: CustomIcon?
    let apps: [String]
    let canRemove: Bool

    @State private var tab: Tab
    @State private var query = ""
    @State private var category = "suggested"
    @State private var dropTargeted = false
    @FocusState private var searchFocused: Bool

    init(selection: Binding<CustomIcon?>, apps: [String], canRemove: Bool, initialTab: Tab) {
        _selection = selection
        self.apps = apps
        self.canRemove = canRemove
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Icon type", selection: $tab) {
                Text("Symbols").tag(Tab.symbols)
                Text("Image").tag(Tab.image)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            switch tab {
            case .symbols: symbolsTab
            case .image: imageTab
            }
        }
        .frame(width: 400, height: 470)
    }

    // MARK: Symbols

    private var symbolsTab: some View {
        let results = SymbolCatalog.symbols(matching: query, in: category)
        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                searchField
                if query.isEmpty { categoryChips }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 8), spacing: 6) {
                        ForEach(results, id: \.self) { name in
                            SymbolCell(name: name, selected: selection == .symbol(name)) {
                                selection = .symbol(name)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                // A new category or search starts at the top.
                .id("\(category)|\(query)")
            }

            Divider()
            HStack {
                if case let .symbol(name) = selection {
                    Image(systemName: name)
                    Text(name).font(.callout.monospaced())
                } else {
                    Text("\(results.count) symbols").font(.callout)
                }
                Spacer()
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search symbols", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.7)))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SymbolCatalog.categories) { item in
                    let selected = item.id == category
                    Button { category = item.id } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.7))))
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Image

    private var imageTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            dropZone

            HStack(spacing: 8) {
                Button("Choose Image…", action: chooseImage)
                    .nativeButton(prominent: true)
                if case .image = selection, canRemove {
                    Button("Remove", role: .destructive) { selection = nil }
                        .nativeButton()
                }
            }
            .frame(maxWidth: .infinity)

            if !apps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use an App's Icon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(apps, id: \.self) { bundleID in
                                Button {
                                    if let path = AppIcons.importAppIcon(bundleID) { selection = .image(path: path) }
                                } label: {
                                    AppIconView(bundleID: bundleID, size: 36)
                                }
                                .buttonStyle(.plain)
                                .help(AppIcons.name(for: bundleID))
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            if case let .image(path) = selection, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                Text("Drop another image to replace it")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
                Text("Drop an Image Here")
                    .font(.headline)
                Text("PNG, PDF or SVG. A transparent background looks best in the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(dropTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [6, 4]))
        )
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let path = AppIcons.importCustomIcon(from: url) else { return false }
            selection = .image(path: path)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image for the menu bar"
        // Settings is a regular window of an accessory app; bring the panel to the front.
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let path = AppIcons.importCustomIcon(from: url) else { return }
            selection = .image(path: path)
        }
    }
}

/// One symbol in the grid.
private struct SymbolCell: View {
    let name: String
    let selected: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            Image(systemName: name)
                .font(.system(size: 17))
                .frame(width: 40, height: 40)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.07 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 1.5 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(name)
        .accessibilityLabel(name)
    }
}
