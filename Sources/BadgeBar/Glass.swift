import SwiftUI

// Liquid Glass on macOS 26 and later, with material fallbacks on older systems.

extension Color {
    /// BadgeBar's accent, used instead of the system accent so controls match the app icon.
    static let brand = Color(red: 0.25, green: 0.45, blue: 0.98)
}

extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func glassCapsule(interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(Glass.regular.interactive(interactive), in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }

    /// Standard macOS push buttons. On macOS 26 the system draws these with Liquid Glass.
    func nativeButton(prominent: Bool = false) -> some View {
        modifier(NativeButtonStyle(prominent: prominent))
    }
}

private struct NativeButtonStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent).tint(.brand)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// Groups glass shapes so they blend and morph together on macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
