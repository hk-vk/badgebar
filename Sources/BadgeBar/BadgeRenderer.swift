import AppKit
import CoreImage

/// Draws a menu bar image: an icon with a badge in one of the supported styles.
enum BadgeRenderer {
    static let iconSize: CGFloat = 16
    private static let barHeight: CGFloat = 22

    static func image(icon: NSImage, badge: Badge?, appearance: BadgeAppearance) -> NSImage {
        let color = NSColor(hex: appearance.colorHex) ?? .systemRed
        let dimmed = badge == nil && appearance.emptyBehavior == .dim
        let iconRect = NSRect(x: 0, y: (barHeight - iconSize) / 2, width: iconSize, height: iconSize)

        guard let badge else {
            return draw(width: iconSize) { _ in
                drawIcon(icon, in: iconRect, alpha: dimmed ? 0.35 : 1)
            }
        }

        switch appearance.style {
        case .dot:
            let d: CGFloat = 6
            return draw(width: iconSize + 2) { _ in
                drawIcon(icon, in: iconRect, alpha: 1)
                let dot = NSRect(x: iconSize + 2 - d, y: iconRect.maxY - d + 1, width: d, height: d)
                strokedFill(NSBezierPath(ovalIn: dot), color)
            }

        case .circle:
            let text = badge.count == nil ? "" : displayLabel(badge)
            let font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let h: CGFloat = text.isEmpty ? 7 : 11
            let w = max(h, textSize.width + 5)
            // The pill overlaps the icon's top-right corner and may extend past it.
            let x = max(iconSize - w * 0.65, iconSize * 0.35)
            let width = max(iconSize, x + w)
            return draw(width: width) { _ in
                drawIcon(icon, in: iconRect, alpha: 1)
                let pill = NSRect(x: x, y: iconRect.maxY - h + 2, width: w, height: h)
                strokedFill(NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2), color)
                if !text.isEmpty {
                    let origin = NSPoint(
                        x: pill.midX - textSize.width / 2,
                        y: pill.midY - textSize.height / 2 + 0.5
                    )
                    (text as NSString).draw(at: origin, withAttributes: attrs)
                }
            }

        case .text:
            let text = displayLabel(badge)
            let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let gap: CGFloat = 3
            return draw(width: iconSize + gap + ceil(textSize.width)) { _ in
                drawIcon(icon, in: iconRect, alpha: 1)
                let origin = NSPoint(x: iconSize + gap, y: (barHeight - textSize.height) / 2)
                (text as NSString).draw(at: origin, withAttributes: attrs)
            }
        }
    }

    static func displayLabel(_ badge: Badge) -> String {
        if let count = badge.count, count > 99 { return "99+" }
        return badge.label
    }

    /// Converts an icon to grayscale for the monochrome icon style.
    static func monochrome(_ image: NSImage) -> NSImage {
        guard
            let tiff = image.tiffRepresentation,
            let input = CIImage(data: tiff),
            let filter = CIFilter(name: "CIColorControls")
        else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return image }
        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: image.size)
        result.addRepresentation(rep)
        return result
    }

    private static func draw(width: CGFloat, _ body: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: ceil(width), height: barHeight), flipped: false) { rect in
            body(rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawIcon(_ icon: NSImage, in rect: NSRect, alpha: CGFloat) {
        guard icon.isTemplate else {
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            return
        }
        // Template images (SF Symbols for groups) are tinted with the menu bar's text color.
        // This runs at draw time, so labelColor resolves against the current light/dark appearance.
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            icon.draw(in: bounds)
            NSColor.labelColor.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
    }

    /// Fills a badge shape with a thin outline so it stays legible over the icon.
    private static func strokedFill(_ path: NSBezierPath, _ color: NSColor) {
        color.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}
