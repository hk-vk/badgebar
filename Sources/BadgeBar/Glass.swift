import SwiftUI

// Shared visual language.
//
// Liquid Glass is for the functional layer that floats over content: controls, the menu bar
// preview, floating panels. Content (cards, lists, steps) sits on quiet solid fills, so glass
// never stacks on glass. Both honor Reduce Transparency.

extension Color {
    /// BadgeBar's accent, used instead of the system accent so controls match the app icon.
    static let brand = Color(red: 0.25, green: 0.45, blue: 0.98)
    /// The quiet fill behind content cards, adapting to light and dark mode.
    static let cardFill = Color(nsColor: .quaternarySystemFill)
    static let hairline = Color(nsColor: .separatorColor)
}

extension Animation {
    /// Default UI spring: critically damped, so things settle without overshoot.
    static let ui = Animation.spring(duration: 0.35, bounce: 0)
    /// Quick response for hover and press feedback.
    static let feedback = Animation.spring(duration: 0.2, bounce: 0)
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: .rect(cornerRadius: cornerRadius), tint: tint, interactive: interactive))
    }

    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: .capsule, tint: nil, interactive: interactive))
    }

    /// A solid, low-contrast card for content.
    func contentCard(cornerRadius: CGFloat = 12, highlighted: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(highlighted ? 0.05 : 0))
                )
        )
    }

    /// Native push buttons: Liquid Glass capsules on macOS 26.
    func nativeButton(prominent: Bool = false, shape: ButtonBorderShape = .capsule) -> some View {
        modifier(NativeButtonStyle(prominent: prominent, shape: shape))
    }

    /// Picks a gentle cross-fade instead of motion when Reduce Motion is on.
    func motionAware<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAwareAnimation(animation: animation, value: value))
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(shape.stroke(Color.hairline))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// macOS 26's Liquid Glass buttons, capsule-shaped like the system's own; bordered capsules
/// on earlier versions. Prominent buttons use the brand tint rather than the system accent.
private struct NativeButtonStyle: ViewModifier {
    let prominent: Bool
    let shape: ButtonBorderShape

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(.brand).buttonBorderShape(shape)
            } else {
                // Secondary buttons stay neutral glass, even inside views tinted with the brand.
                content.buttonStyle(.glass).buttonBorderShape(shape).tint(nil)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).tint(.brand).buttonBorderShape(shape)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(shape).tint(nil)
        }
    }
}

private struct MotionAwareAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeInOut(duration: 0.2) : animation, value: value)
    }
}

/// For custom tappable surfaces (tiles, cards): responds the moment the pointer goes down.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.feedback, value: configuration.isPressed)
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
