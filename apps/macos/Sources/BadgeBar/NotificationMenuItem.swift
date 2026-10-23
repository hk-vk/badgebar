import AppKit

/// A menu row drawn like a notification: unread dot, app icon, bold title with the time on
/// the right, and up to two lines of message. Highlights like a native menu item.
final class NotificationMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ note: DeliveredNotification, icon: NSImage, unread: Bool, dimmed: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: note.title, action: #selector(run), keyEquivalent: "")
        target = self
        view = NotificationRowView(note: note, icon: icon, unread: unread, dimmed: dimmed) { [weak self] in
            self?.menu?.cancelTracking()
            self?.handler()
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

private final class NotificationRowView: NSView {
    private static let width: CGFloat = 330
    private static let iconSize: CGFloat = 28
    private static let textX: CGFloat = 54
    private static let vPadding: CGFloat = 6

    private let title: String
    private let message: String
    private let time: String
    private let icon: NSImage
    private let unread: Bool
    /// Drawn faded, for messages already gone from Notification Center.
    private let dimmed: Bool
    private let activate: () -> Void

    init(note: DeliveredNotification, icon: NSImage, unread: Bool, dimmed: Bool, activate: @escaping () -> Void) {
        let heading = note.title.isEmpty ? note.subtitle : note.title
        title = heading.isEmpty ? "Notification" : heading
        message = [note.title.isEmpty ? "" : note.subtitle, note.body]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        time = NotificationCard.time(note.date)
        self.icon = icon
        self.unread = unread
        self.dimmed = dimmed
        self.activate = activate
        super.init(frame: .zero)
        autoresizingMask = .width
        frame.size = NSSize(width: Self.width, height: Self.height(for: message))

        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel([unread ? "Unread" : nil, title, message, time].compactMap { $0 }.joined(separator: ", "))
        toolTip = message.count > 90 ? message : nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let bodyFont = NSFont.systemFont(ofSize: 12)
    private static let timeFont = NSFont.systemFont(ofSize: 11)

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private static func bodyHeight(_ message: String) -> CGFloat {
        guard !message.isEmpty else { return 0 }
        let bounds = (message as NSString).boundingRect(
            with: NSSize(width: width - textX - 14, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: bodyFont]
        )
        return min(ceil(bounds.height), lineHeight(bodyFont) * 2)
    }

    private static func height(for message: String) -> CGFloat {
        let text = lineHeight(titleFont) + (message.isEmpty ? 0 : 1 + bodyHeight(message))
        return max(text, iconSize) + vPadding * 2 + 2
    }

    override var isFlipped: Bool { true }

    private var highlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = highlighted
        if highlighted {
            // Matches the system's rounded menu selection.
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        let primary: NSColor = highlighted ? .white : dimmed ? .secondaryLabelColor : .labelColor
        let secondary: NSColor = highlighted ? .white.withAlphaComponent(0.8) : .secondaryLabelColor
        let right = bounds.width - 14
        let top = Self.vPadding + 1

        if unread {
            (highlighted ? NSColor.white : .systemBlue).setFill()
            NSBezierPath(ovalIn: NSRect(x: 11, y: top + Self.iconSize / 2 - 3.5, width: 7, height: 7)).fill()
        }
        icon.draw(
            in: NSRect(x: 21, y: top, width: Self.iconSize, height: Self.iconSize),
            from: .zero, operation: .sourceOver, fraction: dimmed && !highlighted ? 0.5 : 1, respectFlipped: true, hints: nil
        )

        let timeAttrs: [NSAttributedString.Key: Any] = [.font: Self.timeFont, .foregroundColor: secondary]
        let timeSize = (time as NSString).size(withAttributes: timeAttrs)
        let titleLine = Self.lineHeight(Self.titleFont)
        (time as NSString).draw(
            at: NSPoint(x: right - timeSize.width, y: top + (titleLine - timeSize.height) / 2 + 0.5),
            withAttributes: timeAttrs
        )

        (title as NSString).draw(
            with: NSRect(x: Self.textX, y: top, width: right - timeSize.width - 8 - Self.textX, height: titleLine),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: Self.titleFont, .foregroundColor: primary, .paragraphStyle: Self.style(.byTruncatingTail)]
        )

        guard !message.isEmpty else { return }
        (message as NSString).draw(
            with: NSRect(x: Self.textX, y: top + titleLine + 1, width: right - Self.textX, height: Self.bodyHeight(message)),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: Self.bodyFont, .foregroundColor: secondary, .paragraphStyle: Self.style(.byWordWrapping)]
        )
    }

    private static func style(_ mode: NSLineBreakMode) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = mode
        return style
    }

    // Custom menu views handle their own clicks.
    override func mouseUp(with event: NSEvent) {
        activate()
    }
}
