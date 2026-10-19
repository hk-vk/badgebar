// Renders Resources/AppIcon.svg to a 1024×1024 PNG.
// Usage: swift scripts/make-icon.swift <input.svg> <output.png>   (scripts/make-icon.sh builds the .icns)
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: make-icon.swift <input.svg> <output.png>")
    exit(1)
}
guard let svg = NSImage(contentsOfFile: args[1]) else {
    print("Couldn't load \(args[1])")
    exit(1)
}

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
svg.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2])")
