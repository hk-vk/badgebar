import SwiftUI

/// One app's notifications in the viewer.
struct AppNotifications: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let badge: Badge?
    let isRunning: Bool
    let notifications: [DeliveredNotification]
}

struct ViewerModel {
    enum Scope {
        case app(bundleID: String)
        case group(symbol: String)
        case all
    }

    let scope: Scope
    let title: String
    let badge: Badge?
    let apps: [AppNotifications]
    let canReadNotifications: Bool
    let showsContent: Bool
}

/// A Notification Center–style viewer used for hover previews, groups, and the all-apps list.
struct NotificationViewer: View {
    let model: ViewerModel
    @ObservedObject var store: Store
    var openSettings: () -> Void

    @Environment(\.closePreview) private var close
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.showsContent && !model.canReadNotifications {
                FullDiskAccessCard()
            }

            content
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .tint(.brand)
        .animation(.spring(duration: 0.35, bounce: 0.12), value: expanded)
        .animation(.spring(duration: 0.35, bounce: 0.12), value: store.cleared)
    }

    private var showContent: Bool { model.canReadNotifications && model.showsContent }

    private func visible(_ app: AppNotifications) -> [DeliveredNotification] {
        showContent ? app.notifications.filter(store.isVisible) : []
    }

    private var hasVisibleNotifications: Bool {
        model.apps.contains { !visible($0).isEmpty }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            switch model.scope {
            case let .app(bundleID):
                AppIconView(bundleID: bundleID, size: 30)
            case let .group(symbol):
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .glassSurface(cornerRadius: 9)
            case .all:
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(model.title)
                    .font(model.scope.isAll ? .title3.weight(.bold) : .headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)

            if hasVisibleNotifications {
                Button(model.scope.isAll ? "Clear All" : "Clear") {
                    store.clear(model.apps.map(\.bundleID))
                }
                .nativeButton()
                .controlSize(.small)
            }

            if case let .app(bundleID) = model.scope {
                Button("Open") { open(bundleID) }
                    .nativeButton(prominent: true)
                    .controlSize(.small)
            } else {
                Button {
                    close()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
        }
    }

    private var summary: String {
        if case let .app(bundleID) = model.scope, !AppIcons.isRunning(bundleID) { return "Not running" }
        guard let badge = model.badge else {
            return model.scope.isAll ? "You're all caught up" : "No new notifications"
        }
        guard let count = badge.count else { return "New activity" }
        return count == 1 ? "1 unread" : "\(count) unread"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.scope {
        case .app:
            if let app = model.apps.first {
                let notes = visible(app)
                if notes.isEmpty {
                    EmptyState(text: showContent ? "No recent notifications" : "Open the app to read new messages.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(notes.prefix(5).enumerated()), id: \.element.id) { index, note in
                            card(note, app: app, unread: index < (app.badge?.count ?? 0), showIcon: false)
                        }
                        if notes.count > 5 {
                            Text("\(notes.count - 5) more in Notification Center")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        case .group, .all:
            let apps = model.apps.filter { $0.badge != nil || !visible($0).isEmpty || !model.scope.isAll }
            if apps.isEmpty {
                EmptyState(text: "No notifications", symbol: "bell.slash")
            } else {
                FittedScrollView(maxHeight: 480) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(apps) { app in
                            stack(for: app)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stack(for app: AppNotifications) -> some View {
        let notes = visible(app)
        let isExpanded = expanded.contains(app.bundleID)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(app.name)
                    .font(.subheadline.weight(.semibold))
                if let badge = app.badge { CountPill(badge: badge) }
                Spacer()
                if notes.count > 1 {
                    Button(isExpanded ? "Show Less" : "\(notes.count - 1) More") { toggle(app.bundleID) }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.medium))
                }
                if !notes.isEmpty {
                    ClearButton { store.clear([app.bundleID]) }
                }
            }
            .padding(.horizontal, 4)

            if notes.isEmpty {
                // A compact card for apps with a badge but nothing to preview.
                Button { open(app.bundleID) } label: {
                    HStack(spacing: 10) {
                        AppIconView(bundleID: app.bundleID, size: 30)
                        Text(app.isRunning ? "Open \(app.name) to see what's new" : "\(app.name) isn't running")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .cardBackground()
                }
                .buttonStyle(.plain)
            } else if isExpanded {
                ForEach(Array(notes.prefix(8).enumerated()), id: \.element.id) { index, note in
                    card(note, app: app, unread: index < (app.badge?.count ?? 0), showIcon: true)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else {
                StackedCard(depth: min(notes.count - 1, 2)) {
                    card(notes[0], app: app, unread: (app.badge?.count ?? 0) > 0, showIcon: true) {
                        if notes.count > 1 { toggle(app.bundleID) } else { open(app.bundleID) }
                    }
                }
            }
        }
    }

    private func card(
        _ note: DeliveredNotification,
        app: AppNotifications,
        unread: Bool,
        showIcon: Bool,
        onTap: (() -> Void)? = nil
    ) -> some View {
        NotificationCard(
            note: note,
            bundleID: app.bundleID,
            isUnread: unread,
            onTap: onTap ?? { open(app.bundleID) },
            onDismiss: { store.dismiss(note) }
        )
    }

    private func toggle(_ bundleID: String) {
        if expanded.contains(bundleID) { expanded.remove(bundleID) } else { expanded.insert(bundleID) }
    }

    private func open(_ bundleID: String) {
        close()
        AppIcons.open(bundleID)
    }
}

private extension ViewerModel.Scope {
    var isAll: Bool {
        if case .all = self { return true }
        return false
    }
}

// MARK: - Cards

/// A single notification, drawn like a macOS notification banner.
struct NotificationCard: View {
    let note: DeliveredNotification
    let bundleID: String
    let isUnread: Bool
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                AppIconView(bundleID: bundleID, size: 32)
                    .overlay(alignment: .topLeading) {
                        if isUnread {
                            Circle()
                                .fill(Color.brand)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                                .offset(x: -3, y: -2)
                        }
                    }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(note.title.isEmpty ? note.subtitle : note.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(Self.time(note.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    if !note.subtitle.isEmpty && !note.title.isEmpty {
                        Text(note.subtitle)
                            .font(.callout)
                            .lineLimit(1)
                    }
                    if !note.body.isEmpty {
                        Text(note.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(highlighted: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        // Like Notification Center: a close button appears on the corner while hovering.
        .overlay(alignment: .topLeading) {
            if hovering {
                ClearButton(action: onDismiss)
                    .offset(x: -6, y: -6)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    /// "now", "5m", "2h", then the time or date, as Notification Center shows it.
    static func time(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Shows a card with one or two cards peeking out underneath, like a collapsed notification stack.
private struct StackedCard<Content: View>: View {
    let depth: Int
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    ForEach((1...max(depth, 1)).reversed(), id: \.self) { level in
                        if level <= depth {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.regularMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
                                .frame(height: 20)
                                .padding(.horizontal, CGFloat(level) * 10)
                                .offset(y: CGFloat(level) * 6)
                                .opacity(1 - Double(level) * 0.25)
                        }
                    }
                }
            }
            .padding(.bottom, CGFloat(depth) * 6)
    }
}

private struct ClearButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help("Clear")
        .accessibilityLabel("Clear")
    }
}

private extension View {
    func cardBackground(highlighted: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(highlighted ? 0.05 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07))
                )
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        )
    }
}

/// A scroll view that is only as tall as its content, up to a maximum.
private struct FittedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
        }
        .scrollIndicators(.automatic)
        .frame(height: min(max(contentHeight, 1), maxHeight))
        .padding(.horizontal, -6)
    }
}

// MARK: - Supporting views

private struct FullDiskAccessCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) {
                Text("See your messages here").font(.subheadline.weight(.semibold))
                Text("Allow Full Disk Access to preview notifications. They're read on your Mac and never leave it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow in System Settings…") { Permissions.openFullDiskAccessSettings() }
                    .nativeButton()
                    .controlSize(.small)
            }
        }
        .padding(12)
        .glassSurface(cornerRadius: 14)
    }
}

private struct EmptyState: View {
    let text: String
    var symbol: String?

    var body: some View {
        VStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, symbol == nil ? 6 : 18)
    }
}

struct CountPill: View {
    let badge: Badge
    var color: Color = .red

    var body: some View {
        Text(badge.count == nil ? "•" : BadgeRenderer.displayLabel(badge))
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(color))
            .contentTransition(.numericText())
    }
}
