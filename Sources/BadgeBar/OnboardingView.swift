import AppKit
import ServiceManagement
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, accessibility, apps, previews, done
}

struct OnboardingView: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    @State var step: OnboardingStep
    var finish: (_ openSettings: Bool) -> Void

    @State private var forward = true
    @State private var selectedApps: Set<String> = []
    @State private var style: BadgeStyle = .circle

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
        }
        .frame(width: 640, height: 600)
        .background(backdrop)
        .tint(.brand)
        .onChange(of: monitor.isTrusted) { _, trusted in
            // Move on by itself once access is granted, so there's nothing to click.
            if trusted, step == .accessibility {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { go(to: .apps) }
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Color.brand.opacity(0.16), .clear, Color.pink.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: WelcomePage()
        case .accessibility: AccessibilityPage(isTrusted: monitor.isTrusted, needsRelaunch: monitor.needsRelaunch)
        case .apps: AppsPage(monitor: monitor, store: store, selected: $selectedApps, style: $style)
        case .previews: PreviewsPage()
        case .done: DonePage(store: store, monitor: monitor)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Back") { go(to: OnboardingStep(rawValue: step.rawValue - 1)!) }
                    .nativeButton()
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
            }
            Spacer()
            PageDots(current: step)
            Spacer()
            primaryButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .controlSize(.large)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Get Started") { go(to: monitor.isTrusted ? .apps : .accessibility) }
                .nativeButton(prominent: true)
                .keyboardShortcut(.defaultAction)
        case .accessibility:
            Button(monitor.isTrusted ? "Continue" : "Skip for Now") { go(to: .apps) }
                .nativeButton(prominent: monitor.isTrusted)
                .keyboardShortcut(.defaultAction)
        case .apps:
            Button(selectedApps.isEmpty ? "Skip" : "Add \(selectedApps.count) App\(selectedApps.count == 1 ? "" : "s")") {
                applySelection()
                go(to: .previews)
            }
            .nativeButton(prominent: true)
            .keyboardShortcut(.defaultAction)
        case .previews:
            Button(Permissions.hasFullDiskAccess ? "Continue" : "Skip") { go(to: .done) }
                .nativeButton(prominent: true)
                .keyboardShortcut(.defaultAction)
        case .done:
            HStack {
                Button("Open Settings") { complete(openSettings: true) }
                    .nativeButton()
                Button("Done") { complete(openSettings: false) }
                    .nativeButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func go(to next: OnboardingStep) {
        forward = next.rawValue > step.rawValue
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { step = next }
    }

    private func applySelection() {
        for entry in monitor.entries where selectedApps.contains(entry.bundleID) && !store.isTracked(entry.bundleID) {
            var app = TrackedApp(bundleID: entry.bundleID, name: entry.name)
            app.appearance.style = style
            store.apps.append(app)
        }
    }

    private func complete(openSettings: Bool) {
        store.general.hasCompletedOnboarding = true
        finish(openSettings)
    }
}

// MARK: - Pages

private struct PageHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 68, height: 68)
                .glassSurface(cornerRadius: 20)
            Text(title)
                .font(.system(size: 26, weight: .bold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            VStack(spacing: 8) {
                Text("Welcome to BadgeBar")
                    .font(.system(size: 30, weight: .bold))
                Text("Unread counts from your apps, right in the menu bar.\nHide the Dock without missing a message.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            DemoStrip()

            GlassGroup {
                VStack(alignment: .leading, spacing: 14) {
                    Feature(symbol: "app.badge", title: "Badges at a glance", detail: "Slack, Mail, Messages and more — counts update live.")
                    Feature(symbol: "cursorarrow.rays", title: "Hover to preview", detail: "See recent notifications without switching apps.")
                    Feature(symbol: "square.stack", title: "Group and style", detail: "Combine apps under one icon, pick colors and badge styles.")
                }
                .padding(18)
                .frame(width: 440, alignment: .leading)
                .glassSurface(cornerRadius: 18)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
}

/// An animated menu bar mock-up whose counts tick up, to show what BadgeBar does.
private struct DemoStrip: View {
    private let apps = ["com.apple.mail", "com.apple.MobileSMS", "com.apple.iCal", "com.apple.reminders"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.4)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 1.4)
            MenuBarStrip(images: apps.enumerated().map { index, id in
                let count = (tick + index * 3) % 7
                var appearance = BadgeAppearance()
                appearance.style = index == 2 ? .dot : .circle
                return BadgeRenderer.image(
                    icon: AppIcons.icon(for: id),
                    badge: count == 0 ? nil : Badge(label: String(count)),
                    appearance: appearance
                )
            })
            .scaleEffect(1.5)
            .frame(height: 44)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccessibilityPage: View {
    let isTrusted: Bool
    let needsRelaunch: Bool
    @State private var showHelp = false
    /// Set once the user has been sent to System Settings, to offer a restart if needed.
    @State private var openedSettings = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            PageHeader(
                symbol: "accessibility",
                title: "Allow Accessibility Access",
                subtitle: "Apps show unread counts on their Dock icons. BadgeBar reads those counts, and nothing else."
            )

            VStack(alignment: .leading, spacing: 0) {
                StepRow(number: 1, text: "Click **Open System Settings** below.", done: isTrusted)
                Divider().padding(.leading, 44)
                StepRow(number: 2, text: "Turn on **BadgeBar** in the Accessibility list.", done: isTrusted)
                Divider().padding(.leading, 44)
                StepRow(number: 3, text: "Come back here — BadgeBar notices automatically.", done: isTrusted)
            }
            .padding(.vertical, 4)
            .frame(width: 460)
            .glassSurface(cornerRadius: 16)

            status

            if !isTrusted && !needsRelaunch {
                HStack(spacing: 10) {
                    Button {
                        openedSettings = true
                        Permissions.requestAccessibility()
                    } label: {
                        Label("Open System Settings", systemImage: "gear")
                    }
                    .nativeButton(prominent: true)
                    .controlSize(.large)

                    DraggableAppTile()
                }

                if openedSettings && !needsRelaunch {
                    HStack(spacing: 6) {
                        Text("Turned it on but still waiting?").foregroundStyle(.secondary)
                        Button("Restart BadgeBar") { Permissions.relaunch(resumingAt: .accessibility) }
                            .buttonStyle(.link)
                    }
                    .font(.callout)
                }

                DisclosureGroup("Already turned on, or BadgeBar isn't listed?", isExpanded: $showHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If BadgeBar is switched on but not detected, macOS may be remembering an older copy. Reset it and allow it again.")
                        HStack {
                            Button("Reset & Ask Again") { Permissions.resetAccessibility() }
                            Button("Show BadgeBar in Finder") { Permissions.revealApp() }
                        }
                        .nativeButton()
                        .controlSize(.small)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                }
                .frame(width: 460)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: isTrusted)
    }

    @ViewBuilder
    private var status: some View {
        if needsRelaunch {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Access allowed — restarting BadgeBar to finish…")
            }
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassCapsule()
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else if isTrusted {
            Label("Access granted — you're good to go", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassCapsule()
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for access…").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassCapsule()
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.brand.opacity(0.15))
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            .frame(width: 24, height: 24)
            Text(text)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// The app's own icon, which can be dragged straight into System Settings' permission list.
private struct DraggableAppTile: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)
            Text("Drag into the list")
                .font(.callout)
                .foregroundStyle(.secondary)
            Image(systemName: "hand.draw").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassCapsule(interactive: true)
        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
        .help("If BadgeBar isn't in the Accessibility list, drag this into it.")
    }
}

private struct AppsPage: View {
    @ObservedObject var monitor: BadgeMonitor
    @ObservedObject var store: Store
    @Binding var selected: Set<String>
    @Binding var style: BadgeStyle

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 18) {
            PageHeader(
                symbol: "square.grid.2x2",
                title: "Choose Your Apps",
                subtitle: "These stay in the menu bar. Other apps still appear whenever they have something new."
            )
            .padding(.top, 24)

            if candidates.isEmpty {
                ContentUnavailableView(
                    monitor.isTrusted ? "No Apps in the Dock" : "Waiting for Access",
                    systemImage: "dock.rectangle",
                    description: Text(monitor.isTrusted
                        ? "Open the apps you want to track, or add them later in Settings."
                        : "Allow Accessibility access to see your Dock apps here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(candidates, id: \.bundleID) { entry in
                            AppTile(entry: entry, isOn: selected.contains(entry.bundleID)) {
                                if selected.contains(entry.bundleID) {
                                    selected.remove(entry.bundleID)
                                } else {
                                    selected.insert(entry.bundleID)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 4)
                }

                VStack(spacing: 8) {
                    Text("Badge style").font(.callout).foregroundStyle(.secondary)
                    StylePicker(appearance: styleAppearance, icon: previewIcon)
                        .frame(width: 360)
                }
                .padding(.bottom, 4)
            }
        }
        .onAppear(perform: preselect)
    }

    private var candidates: [DockEntry] {
        monitor.entries.filter { !store.isTracked($0.bundleID) }
    }

    /// Adapts the single style choice to the appearance-based `StylePicker`.
    private var styleAppearance: Binding<BadgeAppearance> {
        Binding(
            get: {
                var appearance = BadgeAppearance()
                appearance.style = style
                return appearance
            },
            set: { style = $0.style }
        )
    }

    /// Preview with one of the chosen apps, so the tiles show the user's own icon.
    private var previewIcon: NSImage {
        let id = candidates.first { selected.contains($0.bundleID) }?.bundleID ?? "com.apple.MobileSMS"
        return AppIcons.icon(for: id)
    }

    /// Start with whatever already has notifications selected.
    private func preselect() {
        guard selected.isEmpty else { return }
        selected = Set(candidates.filter { $0.badge != nil }.map(\.bundleID))
    }
}

private struct AppTile: View {
    let entry: DockEntry
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                AppIconView(bundleID: entry.bundleID, size: 44)
                    .overlay(alignment: .topTrailing) {
                        if let badge = entry.badge {
                            CountPill(badge: badge).offset(x: 6, y: -4)
                        }
                    }
                Text(entry.name)
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
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct PreviewsPage: View {
    @State private var granted = Permissions.hasFullDiskAccess
    @State private var openedSettings = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            PageHeader(
                symbol: "text.bubble",
                title: "Preview Messages on Hover",
                subtitle: "Optional. Rest the pointer on an icon to read recent notifications without switching apps."
            )

            NotificationCard(
                note: DeliveredNotification(
                    id: -1, bundleID: "com.apple.MobileSMS", title: "Alex", subtitle: "",
                    body: "Are we still on for lunch tomorrow?", date: Date().addingTimeInterval(-120)
                ),
                bundleID: "com.apple.MobileSMS",
                isUnread: true,
                onTap: {},
                onDismiss: {}
            )
            .frame(width: 380)
            .allowsHitTesting(false)

            if granted {
                Label("Previews are on", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassCapsule()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    StepRow(number: 1, text: "Click **Open System Settings** below.", done: openedSettings)
                    Divider().padding(.leading, 44)
                    StepRow(number: 2, text: "Drag the **BadgeBar** icon that appears into the list.", done: false)
                    Divider().padding(.leading, 44)
                    StepRow(number: 3, text: "Make sure its switch is on. That's it.", done: false)
                }
                .padding(.vertical, 4)
                .frame(width: 460)
                .glassSurface(cornerRadius: 16)

                HStack(spacing: 10) {
                    Button {
                        openedSettings = true
                        Permissions.requestFullDiskAccess()
                    } label: {
                        Label("Open System Settings", systemImage: "gear")
                    }
                    .nativeButton(prominent: true)
                    .controlSize(.large)

                    DraggableAppTile()
                }

                if openedSettings {
                    HStack(spacing: 6) {
                        Text("Switched on but nothing happened?").foregroundStyle(.secondary)
                        Button("Restart BadgeBar") { Permissions.relaunch(resumingAt: .previews) }
                            .buttonStyle(.link)
                    }
                    .font(.callout)
                } else {
                    Text("Skip this and hovering still shows unread counts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: granted)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            let now = Permissions.hasFullDiskAccess
            if now != granted { granted = now }
        }
    }
}

private struct DonePage: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor: BadgeMonitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: true)
            VStack(spacing: 8) {
                Text("You're All Set").font(.system(size: 28, weight: .bold))
                Text("Look up at your menu bar. Click an icon to open its app, hover to preview, or right-click for more.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            if !store.apps.isEmpty {
                MenuBarStrip(images: store.apps.prefix(6).map {
                    BadgeRenderer.image(icon: AppIcons.menuBarIcon(for: $0), badge: monitor.badges[$0.bundleID], appearance: $0.appearance)
                })
                .scaleEffect(1.4)
                .frame(height: 44)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Open BadgeBar at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                Label("Hold ⌘ and drag icons to rearrange them.", systemImage: "hand.point.up.left")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 420, alignment: .leading)
            .glassSurface(cornerRadius: 16)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
}

private struct PageDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == current ? Color.brand : Color.secondary.opacity(0.3))
                    .frame(width: step == current ? 18 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.35), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }
}
