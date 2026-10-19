import AppKit
import SwiftUI

extension NSColor {
    convenience init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FF3B30" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}

extension Binding where Value == String {
    /// Adapts a hex string binding for use with `ColorPicker`.
    var color: Binding<Color> {
        Binding<Color>(
            get: { Color(nsColor: NSColor(hex: wrappedValue) ?? .systemRed) },
            set: { wrappedValue = NSColor($0).hexString }
        )
    }
}
