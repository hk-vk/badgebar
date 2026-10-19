// Renders BadgeBar's app icon to a 1024×1024 PNG.
// Usage: swift scripts/make-icon.swift <output.png>   (scripts/make-icon.sh builds the .icns)
//
// The design is deliberately simple: a white app tile with a red notification badge on a
// blue squircle.
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func shadow(_ y: CGFloat, _ blur: CGFloat, _ alpha: CGFloat, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: y), blur: blur, color: NSColor.black.withAlphaComponent(alpha).cgColor)
    draw()
    ctx.restoreGState()
}

func clipped(_ path: NSBezierPath, _ draw: () -> Void) {
    ctx.saveGState()
    path.addClip()
    draw()
    ctx.restoreGState()
}

// macOS icon grid: an 824pt body centered in the 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

shadow(-10, 24, 0.25) {
    color(0x2F6BF0).setFill()
    bodyPath.fill()
}
clipped(bodyPath) {
    NSGradient(colors: [color(0x5AA9FF), color(0x2F6BF0), color(0x2F4FD8)], atLocations: [0, 0.6, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -90)
}

// The app tile.
let tile = NSRect(x: 292, y: 262, width: 420, height: 420)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 100, yRadius: 100)
shadow(-16, 36, 0.22) {
    NSColor.white.setFill()
    tilePath.fill()
}
clipped(tilePath) {
    NSGradient(colors: [color(0xFFFFFF), color(0xEEF2FB)])!.draw(in: tile, angle: -90)
}

// The badge, with a ring of the background colour so it reads as sitting on top.
let badgeD: CGFloat = 196
let badge = NSRect(x: tile.maxX - badgeD * 0.6, y: tile.maxY - badgeD * 0.6, width: badgeD, height: badgeD)
shadow(-8, 18, 0.2) {
    NSColor.white.setFill()
    NSBezierPath(ovalIn: badge.insetBy(dx: -16, dy: -16)).fill()
}
let badgePath = NSBezierPath(ovalIn: badge)
clipped(badgePath) {
    NSGradient(colors: [color(0xFF6259), color(0xFF3B30), color(0xE82A20)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
        .draw(in: badge, angle: -90)
}

// A faint inner rim, as on Apple's icons.
clipped(bodyPath) {
    NSColor.white.withAlphaComponent(0.2).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    rim.lineWidth = 4
    rim.stroke()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
