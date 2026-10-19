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
        // A plain capsule rather than glass: it usually sits inside a form row already.
        .background(Capsule().fill(Color.cardFill))
    }
}

/// A choice shown as a thumbnail with a caption, like System Settings' Appearance picker:
/// the selected one gets an accent ring around its thumbnail. Used for every visual choice.
struct ChoiceTile<Thumbnail: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var thumbnail: Thumbnail

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                thumbnail
                    .frame(width: 56, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.cardFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.hairline.opacity(selected ? 0 : 1), lineWidth: 1)
                    )
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                            .opacity(selected ? 1 : 0)
                    )
                Text(title)
                    .font(.caption)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .motionAware(.feedback, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The three badge styles, each previewed on the app's own icon.
struct StylePicker: View {
    @Binding var appearance: BadgeAppearance
    let icon: NSImage

    var body: some View {
        HStack(spacing: 14) {
            ForEach(BadgeStyle.allCases) { style in
                ChoiceTile(title: style.label, selected: appearance.style == style) {
                    appearance.style = style
                } thumbnail: {
                    Image(nsImage: BadgeRenderer.image(icon: icon, badge: Badge(label: "3"), appearance: sample(style)))
                }
            }
        }
    }

    private func sample(_ style: BadgeStyle) -> BadgeAppearance {
        var sample = appearance
        sample.style = style
        return sample
    }
}

/// Color circles in the style of System Settings' accent color picker, plus "Other…", which
/// opens the system color panel.
struct ColorSwatches: View {
    @Binding var hex: String

    static let presets = ["#FF3B30", "#FF9500", "#34C759", "#0A84FF", "#AF52DE", "#8E8E93"]
    private static let names = ["Red", "Orange", "Green", "Blue", "Purple", "Gray"]

    private var isCustom: Bool {
        !Self.presets.contains { $0.caseInsensitiveCompare(hex) == .orderedSame }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(zip(Self.presets, Self.names)), id: \.0) { preset, name in
                let selected = preset.caseInsensitiveCompare(hex) == .orderedSame
                Button {
                    hex = preset
                } label: {
                    swatch(Color(nsColor: NSColor(hex: preset) ?? .red), selected: selected)
                }
                .buttonStyle(.plain)
                .help(name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            // "Other…" sits in front of an invisible system color well, which opens the panel.
            ZStack {
                HStack(spacing: 5) {
                    if isCustom {
                        swatch($hex.color.wrappedValue, selected: true)
                    } else {
                        Circle()
                            .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                            .frame(width: 18, height: 18)
                    }
                    Text("Other…").font(.callout).foregroundStyle(.secondary)
                }
                ColorPicker("Other Color", selection: $hex.color, supportsOpacity: false)
                    .labelsHidden()
                    .opacity(0.02)
                    .frame(width: 70, height: 22)
                    .clipped()
            }
            .padding(.leading, 4)
            .help("Choose any color")
        }
    }

    private func swatch(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(.black.opacity(0.12)))
            .overlay {
                Circle().fill(.white).frame(width: 6, height: 6).opacity(selected ? 1 : 0)
            }
            .contentShape(Circle())
    }
}

/// The top of every settings page: a large icon, a title (editable for groups), a status line,
/// and an optional action on the right.
struct PaneHeader<Icon: View, Title: View, Trailing: View>: View {
    let subtitle: String
    @ViewBuilder var icon: Icon
    @ViewBuilder var title: Title
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            icon.frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 4)
    }
}

/// A rounded list row used for permission status in onboarding and settings.
struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    var optional = false
    var actionTitle = "Allow…"
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(granted ? Color.green : Color.brand)
                .frame(width: 32)
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
                    .transition(.opacity)
            } else {
                Button(actionTitle, action: action).nativeButton()
            }
        }
        .motionAware(.ui, value: granted)
    }
}

/// A copy of BadgeBar's part of the menu bar whose icons can be dragged left and right to
/// arrange them. Neighbours slide aside while dragging, and the new order is applied on drop.
struct ReorderStrip: View {
    struct Item: Identifiable {
        let id: String
        let name: String
        let image: NSImage
        /// Hidden in the menu bar right now (nothing new, and set to hide).
        let hidden: Bool

        /// "app" or "group": items only move among their own kind, as in the menu bar.
        var kind: Substring { id.prefix { $0 != "." } }
    }

    let items: [Item]
    let move: ([String]) -> Void
    var open: (String) -> Void = { _ in }

    @State private var dragging: String?
    @State private var translation: CGFloat = 0

    private static let scale: CGFloat = 1.5
    private static let spacing: CGFloat = 6

    private var tileWidth: CGFloat {
        max(64, (items.map(\.image.size.width).max() ?? 16) * Self.scale + 16)
    }

    private var slot: CGFloat { tileWidth + Self.spacing }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.spacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    tile(item, index: index)
                }
            }
            .padding(6)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.cardFill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu bar order")
    }

    private func tile(_ item: Item, index: Int) -> some View {
        let isDragging = dragging == item.id
        return VStack(spacing: 4) {
            Image(nsImage: item.image)
                .resizable()
                .interpolation(.high)
                .frame(width: item.image.size.width * Self.scale, height: item.image.size.height * Self.scale)
                .opacity(item.hidden ? 0.4 : 1)
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: tileWidth, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 8, y: 3)
                .opacity(isDragging ? 1 : 0)
        )
        .scaleEffect(isDragging ? 1.06 : 1)
        .offset(x: offset(for: index, item: item))
        .zIndex(isDragging ? 1 : 0)
        .contentShape(Rectangle())
        .help(item.hidden ? "\(item.name) · hidden while nothing is new" : item.name)
        .onHover { inside in
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { open(item.id) }
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { value in
                    if dragging == nil { NSCursor.closedHand.push() }
                    dragging = item.id
                    translation = value.translation.width
                }
                .onEnded { _ in
                    NSCursor.pop()
                    let target = targetIndex(from: index, item: item)
                    var order = items.map(\.id)
                    order.move(fromOffsets: [index], toOffset: target > index ? target + 1 : target)
                    withAnimation(.ui) {
                        if target != index { move(order) }
                        dragging = nil
                        translation = 0
                    }
                }
        )
        .animation(.feedback, value: targetIndexForAnimation)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Move Left") { nudge(item, index: index, by: -1) }
        .accessibilityAction(named: "Move Right") { nudge(item, index: index, by: 1) }
    }

    /// Where the dragged item would land, kept within its own kind's run of positions.
    private func targetIndex(from index: Int, item: Item) -> Int {
        let range = items.indices.filter { items[$0].kind == item.kind }
        guard let low = range.first, let high = range.last else { return index }
        let proposed = index + Int((translation / slot).rounded())
        return min(max(proposed, low), high)
    }

    /// Changes whenever the drop position changes, so neighbours animate as they slide aside.
    private var targetIndexForAnimation: Int {
        guard let dragging, let index = items.firstIndex(where: { $0.id == dragging }) else { return -1 }
        return targetIndex(from: index, item: items[index])
    }

    private func offset(for index: Int, item: Item) -> CGFloat {
        guard let dragging, let from = items.firstIndex(where: { $0.id == dragging }) else { return 0 }
        if item.id == dragging { return translation }
        let to = targetIndex(from: from, item: items[from])
        if from < to, index > from, index <= to { return -slot }
        if from > to, index >= to, index < from { return slot }
        return 0
    }

    private func nudge(_ item: Item, index: Int, by step: Int) {
        let target = index + step
        guard items.indices.contains(target), items[target].kind == item.kind else { return }
        var order = items.map(\.id)
        order.swapAt(index, target)
        withAnimation(.ui) { move(order) }
    }
}
