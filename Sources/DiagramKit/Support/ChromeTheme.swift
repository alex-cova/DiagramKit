import SwiftUI

// Internal copy of the Hextech tokens the workspace chrome reads (`Theme`, `cardSurface`,
// `inspectorSurface`, `themedAnimation`). Kept inside this module so DiagramKit does not
// depend on the app, and kept internal so the names do not collide with Hextech's own.

enum Theme {
    static let accent = Color.accentColor
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color.primary.opacity(0.08)
    static let quietStroke = Color.primary.opacity(0.06)
    static let elevatedShadow = Color.black.opacity(0.10)

    static var workbenchGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.10),
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
    }

    enum Typography {
        static let paneTitle: Font = .subheadline.weight(.semibold)
        static let caption: Font = .caption
    }

    enum Motion {
        static let quick: Animation = .snappy(duration: 0.15)
        static let standard: Animation = .snappy(duration: 0.2)
        static let reduced: Animation = .easeOut(duration: 0.1)
    }

    enum Opacity {
        static let subtle: Double = 0.08
    }

    enum Status {
        static let warning: Color = .orange
    }

    enum Interaction {
        static let hoverFill = Color.primary.opacity(0.06)
    }
}

private struct ThemedAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Theme.Motion.reduced : animation, value: value)
    }
}

private struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.md

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

private struct CardSurface: ViewModifier {
    var opacity: Double = 0.88

    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground.opacity(opacity), in: .rect(cornerRadius: Theme.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            }
    }
}

private struct InspectorSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.lg
    var shadowOpacity: Double = 0.35

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.cardBackground)
                    .glassBackground(cornerRadius: cornerRadius)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            }
            .shadow(color: Theme.elevatedShadow.opacity(shadowOpacity), radius: 18, y: 8)
    }
}

extension View {
    func cardSurface(opacity: Double = 0.88) -> some View {
        modifier(CardSurface(opacity: opacity))
    }

    func glassBackground(cornerRadius: CGFloat = Theme.Radius.md) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }

    func inspectorSurface(
        cornerRadius: CGFloat = Theme.Radius.lg,
        shadowOpacity: Double = 0.35
    ) -> some View {
        modifier(InspectorSurface(cornerRadius: cornerRadius, shadowOpacity: shadowOpacity))
    }

    func themedAnimation<Value: Equatable>(_ animation: Animation = Theme.Motion.standard, value: Value) -> some View {
        modifier(ThemedAnimationModifier(animation: animation, value: value))
    }
}
