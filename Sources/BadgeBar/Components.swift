import SwiftUI

struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: AppIcons.icon(for: bundleID))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// A slice of a menu bar on glass, showing exactly what BadgeBar will draw.
struct MenuBarStrip: View {
    let images: [NSImage]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image)
                    .frame(width: image.size.width, height: image.size.height)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .glassCapsule()
    }
}

/// Shows a badge both with and without notifications, so changes are visible immediately.
struct BadgePreview: View {
    let icon: NSImage
    let appearance: BadgeAppearance
    var badge: Badge?

    var body: some View {
        HStack(spacing: 24) {
            labeled("With notifications") {
                MenuBarStrip(images: [BadgeRenderer.image(icon: icon, badge: badge ?? Badge(label: "3"), appearance: appearance)])
            }
            labeled("Nothing new") {
                MenuBarStrip(images: [BadgeRenderer.image(icon: icon, badge: nil, appearance: appearance)])
                    .opacity(appearance.emptyBehavior == .hide ? 0.25 : 1)
                    .overlay {
                        if appearance.emptyBehavior == .hide {
                            Image(systemName: "eye.slash").foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.snappy, value: appearance)
    }

    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 6) {
            content()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Three selectable tiles that each preview a badge style.
struct StylePicker: View {
    @Binding var appearance: BadgeAppearance
    let icon: NSImage

    var body: some View {
        HStack(spacing: 10) {
            ForEach(BadgeStyle.allCases) { style in
                let selected = appearance.style == style
                Button {
                    withAnimation(.snappy) { appearance.style = style }
                } label: {
                    VStack(spacing: 6) {
                        Image(nsImage: BadgeRenderer.image(icon: icon, badge: Badge(label: "3"), appearance: sample(style)))
                            .frame(height: 24)
                        Text(style.label)
                            .font(.caption)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(selected ? 0.06 : 0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Color.brand : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func sample(_ style: BadgeStyle) -> BadgeAppearance {
        var sample = appearance
        sample.style = style
        return sample
    }
}

/// Color swatches in the style of System Settings' accent color picker, plus a custom well.
struct ColorSwatches: View {
    @Binding var hex: String

    static let presets = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
        "#0A84FF", "#5E5CE6", "#AF52DE", "#FF2D55", "#8E8E93",
    ]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Self.presets, id: \.self) { preset in
                let selected = preset.caseInsensitiveCompare(hex) == .orderedSame
                Button {
                    hex = preset
                } label: {
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: preset) ?? .red))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                        .overlay {
                            if selected {
                                Circle().fill(.white).frame(width: 6, height: 6)
                            }
                        }
                        .padding(2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset)
            }
            ColorPicker("Custom color", selection: $hex.color, supportsOpacity: false)
                .labelsHidden()
        }
    }
}

/// A rounded list row used for permission status in onboarding and settings.
struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    var optional = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(granted ? Color.green : Color.brand)
                .frame(width: 34, height: 34)
                .glassSurface(cornerRadius: 9)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.body.weight(.medium))
                    if optional {
                        Text("Optional")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Allow…", action: action).nativeButton()
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: granted)
    }
}
