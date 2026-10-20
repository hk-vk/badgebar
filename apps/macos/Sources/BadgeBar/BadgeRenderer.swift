import AppKit
import CoreImage

/// Draws a menu bar image: an icon with a badge in one of the supported styles.
enum BadgeRenderer {
    /// Matches the visual size of other menu bar icons once app icons' built-in margins are
    /// trimmed (see `rasterized(_:trimmingMargins:)`).
    static let iconSize: CGFloat = 16
    private static let barHeight: CGFloat = 22

    /// - Parameters:
    ///   - effect: an attention effect to draw at `phase`.
    ///   - phase: progress through one cycle of the effect, from 0 to 1. At 0 and 1 the
    ///     image is the same as with no effect, so cycles join up without a jump.
    static func image(
        icon: NSImage,
        badge: Badge?,
        appearance: BadgeAppearance,
        effect: BadgeEffect = .off,
        phase: CGFloat = 0
    ) -> NSImage {
        // A badge without a number (Slack's unread-channel dot, for example) only signals
        // quiet activity, so it's drawn in a muted gray instead of the badge color.
        let color = badge?.count == nil ? NSColor.secondaryLabelColor : NSColor(hex: appearance.colorHex) ?? .systemRed
        let dimmed = badge == nil && appearance.emptyBehavior == .dim
        let iconRect = NSRect(x: 0, y: (barHeight - iconSize) / 2, width: iconSize, height: iconSize)

        guard let badge else {
            return draw(width: iconSize) { _ in
                drawIcon(icon, in: iconRect, alpha: dimmed ? 0.35 : 1)
            }
        }

        // Rises and falls once per cycle, easing in and out at both ends.
        let amount = effect == .off ? 0 : sin(.pi * min(max(phase, 0), 1))
        let effect = amount > 0 ? effect : .off

        switch appearance.style {
        case .dot:
            let d: CGFloat = 6
            // One extra point so the dot's outline isn't cut off at the right edge.
            return draw(width: iconSize + 1, shimmer: effect == .shimmer ? phase : nil) { _ in
                drawIcon(icon, in: iconRect, alpha: 1)
                let dot = NSRect(x: iconSize - d + 0.5, y: iconRect.maxY - d + 1.5, width: d, height: d)
                emphasized(dot, anchor: NSPoint(x: dot.maxX, y: dot.maxY), color: color, effect: effect, amount: amount) {
                    strokedFill(NSBezierPath(ovalIn: dot), color)
                }
            }

        case .circle:
            let text = badge.count == nil ? "" : displayLabel(badge)
            let font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let h: CGFloat = text.isEmpty ? 7 : 11
            let w = max(h, textSize.width + 5)
            // The pill sits on the icon's top-right corner, like a Dock badge, so the item is no
            // wider than the icon. Only long labels ("99+") widen it.
            let x = max(iconSize - w + 1, 0)
            let width = max(iconSize, x + w)
            return draw(width: width, shimmer: effect == .shimmer ? phase : nil) { _ in
                drawIcon(icon, in: iconRect, alpha: 1)
                let pill = NSRect(x: x, y: iconRect.maxY - h + 2, width: w, height: h)
                emphasized(pill, anchor: NSPoint(x: pill.maxX, y: pill.maxY), color: color, effect: effect, amount: amount) {
                    strokedFill(NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2), color)
                    if !text.isEmpty {
                        let origin = NSPoint(
                            x: pill.midX - textSize.width / 2,
                            y: pill.midY - textSize.height / 2 + 0.5
                        )
                        (text as NSString).draw(at: origin, withAttributes: attrs)
                    }
                }
            }

        case .text:
            let text = displayLabel(badge)
            let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let gap: CGFloat = 2
            return draw(width: iconSize + gap + ceil(textSize.width), shimmer: effect == .shimmer ? phase : nil) { _ in
                drawIcon(icon, in: iconRect, alpha: 1)
                let origin = NSPoint(x: iconSize + gap, y: (barHeight - textSize.height) / 2)
                let label = NSRect(origin: origin, size: textSize)
                emphasized(label, anchor: NSPoint(x: label.midX, y: label.midY), color: color, effect: effect, amount: amount) {
                    (text as NSString).draw(at: origin, withAttributes: attrs)
                }
            }
        }
    }

    /// Draws a badge with the pulse or glow effect applied. Shimmer is drawn over the whole
    /// image afterwards, in `draw`.
    /// - Parameter anchor: the point a pulse grows from. Corner badges grow from their outer
    ///   corner, inward over the icon, so the menu bar's edge never clips them.
    private static func emphasized(
        _ rect: NSRect,
        anchor: NSPoint,
        color: NSColor,
        effect: BadgeEffect,
        amount: CGFloat,
        _ body: () -> Void
    ) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        switch effect {
        case .pulse:
            let scale = 1 + 0.2 * amount
            let transform = NSAffineTransform()
            transform.translateX(by: anchor.x, yBy: anchor.y)
            transform.scale(by: scale)
            transform.translateX(by: -anchor.x, yBy: -anchor.y)
            transform.concat()
        case .glow:
            let glow = NSShadow()
            glow.shadowColor = color.withAlphaComponent(0.9 * amount)
            glow.shadowBlurRadius = 1 + 3.5 * amount
            glow.shadowOffset = .zero
            glow.set()
        case .shimmer, .off:
            break
        }
        body()
    }

    /// Draws an icon once at menu bar size, at 2x. Animations redraw every frame, and scaling a
    /// full-size app icon down each time costs far more than drawing this small bitmap.
    ///
    /// - Parameter trimmingMargins: crops the transparent margin macOS app icons carry around
    ///   their shape (about a tenth on each side), so the visible icon fills the space.
    static func rasterized(_ icon: NSImage, trimmingMargins: Bool = false) -> NSImage {
        let source = trimmingMargins && !icon.isTemplate ? visibleBounds(of: icon) : nil
        let pixels = Int(iconSize * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return icon }
        rep.size = NSSize(width: iconSize, height: iconSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(origin: .zero, size: rep.size), from: source ?? .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.isTemplate = icon.isTemplate
        return image
    }

    /// Draws an image into a 2x bitmap once, in the given appearance, so showing it again is a
    /// copy rather than a redraw. Used for animation frames that replay every cycle.
    static func bitmap(in appearance: NSAppearance?, _ make: () -> NSImage) -> NSImage {
        var result: NSImage?
        let work = {
            let image = make()
            let size = image.size
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else {
                result = image
                return
            }
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            let bitmap = NSImage(size: size)
            bitmap.addRepresentation(rep)
            result = bitmap
        }
        withoutActuallyEscaping(work) { work in
            if let appearance { appearance.performAsCurrentDrawingAppearance(work) } else { work() }
        }
        return result!
    }

    /// The square part of an image that holds its visible shape, in the image's coordinates.
    /// Faint pixels, like an icon's soft drop shadow, don't count.
    private static func visibleBounds(of icon: NSImage) -> NSRect? {
        let side = 64
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32
            ),
            let data = rep.bitmapData
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where data[(y * side + x) * 4 + 3] > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // Keep it square and centered on the shape, so the icon isn't stretched.
        let length = CGFloat(max(maxX - minX, maxY - minY) + 1)
        let midX = CGFloat(minX + maxX + 1) / 2
        let midY = CGFloat(minY + maxY + 1) / 2
        // Bitmap rows run top-down; image coordinates run bottom-up.
        let scale = icon.size.width / CGFloat(side)
        return NSRect(
            x: (midX - length / 2) * scale,
            y: (CGFloat(side) - midY - length / 2) * scale,
            width: length * scale,
            height: length * scale
        )
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

    /// - Parameter shimmer: when set, a band of light sweeps across everything drawn, this
    ///   far through its pass.
    private static func draw(width: CGFloat, shimmer: CGFloat? = nil, _ body: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: ceil(width), height: barHeight), flipped: false) { rect in
            body(rect)
            if let shimmer, let context = NSGraphicsContext.current?.cgContext {
                drawShimmer(in: rect, progress: shimmer, context: context)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// A slanted band of light that only lands on pixels already drawn, so it glints across
    /// the icon and badge rather than the empty menu bar.
    private static func drawShimmer(in rect: NSRect, progress: CGFloat, context: CGContext) {
        let band: CGFloat = 9
        let slant: CGFloat = 0.45
        // Ease in and out, so the glint speeds up across the middle like light catching a surface.
        let eased = (1 - cos(.pi * min(max(progress, 0), 1))) / 2
        let travel = rect.width + band * 2 + rect.height * slant
        let x = -band - rect.height * slant + travel * eased

        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(.sourceAtop)
        context.concatenate(CGAffineTransform(a: 1, b: 0, c: slant, d: 1, tx: x, ty: 0))
        let gradient = NSGradient(colors: [
            .white.withAlphaComponent(0),
            .white.withAlphaComponent(0.85),
            .white.withAlphaComponent(0),
        ])
        gradient?.draw(in: NSRect(x: 0, y: 0, width: band, height: rect.height), angle: 0)
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
