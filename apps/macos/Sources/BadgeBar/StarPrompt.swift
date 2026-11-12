import AppKit
import SwiftUI

/// Floats under the right end of the menu bar without taking focus, so BadgeBar stays usable
/// while it's open.
@MainActor
final class StarPrompt {
    private static let repository = URL(string: "https://github.com/hk-vk/badgebar")!
    private var panel: PreviewPanel?

    /// GitHub's logo isn't an SF Symbol.
    nonisolated static func gitHubMark() -> NSImage? {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"/></svg>"#
        return NSImage(data: Data(svg.utf8))
    }

    func show(on preferredScreen: NSScreen?) {
        guard let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let content = StarPromptView(
            star: { [weak self] in
                NSWorkspace.shared.open(Self.repository)
                self?.close()
            },
            dismiss: { [weak self] in self?.close() }
        )
        let hosting = FirstMouseHostingView(rootView: AnyView(content))

        let panel = PreviewPanel()
        panel.level = .floating
        // Panels hide when their app deactivates, and BadgeBar steps back as onboarding closes.
        panel.hidesOnDeactivate = false
        panel.setContent(hosting)
        panel.setFrame(
            PreviewPopover.frame(
                for: hosting.fittingSize,
                under: NSRect(x: screen.frame.maxX, y: 0, width: 0, height: 0),
                menuBarBottom: PreviewPopover.menuBarBottom(of: screen),
                screen: screen.frame
            ),
            display: true
        )
        self.panel = panel
        panel.fadeIn(duration: 0.2)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct StarPromptView: View {
    let star: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Star BadgeBar on GitHub")
                        .font(.body.weight(.semibold))
                    Text("BadgeBar is free and open source. A star helps other people find it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button(action: dismiss) {
                    Text("Not Now").starPromptButton(prominent: false)
                }
                .buttonStyle(PressableStyle())
                Button(action: star) {
                    HStack(spacing: 6) {
                        if let mark = StarPrompt.gitHubMark() {
                            Image(nsImage: mark)
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 14, height: 14)
                                .accessibilityHidden(true)
                        }
                        Text("Star on GitHub")
                    }
                    .starPromptButton(prominent: true)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

private extension View {
    /// Native buttons draw dimmed in a panel that never becomes key, which made these look disabled.
    func starPromptButton(prominent: Bool) -> some View {
        font(.callout.weight(.medium))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(prominent ? Color.brand : Color.primary.opacity(0.12), in: .capsule)
    }
}
