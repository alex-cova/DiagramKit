import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// sRGB color stored in documents. Defaults keep CloudKit-style / Codable models complete.
public nonisolated struct CodableColor: Codable, Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// Bridges an arbitrary `ColorPicker` selection back into document storage. Resolves through
    /// `.sRGB` explicitly since `NSColor(Color)` can otherwise hand back a dynamic/catalog color
    /// whose components aren't directly readable.
    public init(from color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    /// Legacy UML light-class defaults (also match `DiagramThemeCatalog.light` node colors).
    public static let classFill = CodableColor(red: 0.97, green: 0.98, blue: 1.0, opacity: 1)
    public static let classStroke = CodableColor(red: 0.35, green: 0.40, blue: 0.50, opacity: 1)
    /// Dark diagram node fill — kept noticeably above `DiagramThemeCatalog.dark.canvasBackground`.
    public static let classFillDark = CodableColor(red: 0.30, green: 0.32, blue: 0.38, opacity: 1)
    public static let classStrokeDark = CodableColor(red: 0.62, green: 0.67, blue: 0.76, opacity: 1)

    public var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    /// Near-black or near-white label color chosen for contrast against this fill.
    /// Independent of app appearance — diagram fills are absolute sRGB, so adaptive
    /// `.primary` vanishes when the app is Dark and the fill is still light (or vice versa).
    public var contrastingLabel: CodableColor {
        relativeLuminance > 0.45 ? .labelOnLight : .labelOnDark
    }

    /// Lifts fills that sit too close to a dark canvas so nodes stay visible in dark mode.
    public func diagramDisplayFill(
        isDark: Bool,
        canvasBackground: CodableColor = DiagramThemeCatalog.dark.canvasBackground
    ) -> CodableColor {
        guard isDark else { return self }
        return liftedIfNeeded(over: canvasBackground, minimumDelta: 0.14)
    }

    /// Ensures strokes remain legible against dark canvas and node fills.
    public func diagramDisplayStroke(
        isDark: Bool,
        canvasBackground: CodableColor = DiagramThemeCatalog.dark.canvasBackground
    ) -> CodableColor {
        guard isDark else { return self }
        return liftedIfNeeded(over: canvasBackground, minimumDelta: 0.22)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: opacity)
    }

    private var relativeLuminance: Double {
        Self.relativeLuminance(red: red, green: green, blue: blue)
    }

    private func liftedIfNeeded(over background: CodableColor, minimumDelta: Double) -> CodableColor {
        let bgLum = background.relativeLuminance
        let lum = relativeLuminance
        guard lum < bgLum + minimumDelta else { return self }
        let lift = (bgLum + minimumDelta) - lum
        return CodableColor(
            red: min(red + lift * 0.85, 1),
            green: min(green + lift * 0.85, 1),
            blue: min(blue + lift * 0.95, 1),
            opacity: opacity
        )
    }

    private static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linearize(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    private static let labelOnLight = CodableColor(red: 0.12, green: 0.13, blue: 0.16, opacity: 1)
    private static let labelOnDark = CodableColor(red: 0.96, green: 0.97, blue: 0.98, opacity: 1)

    public var svgHex: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        let rr = min(max(r, 0), 255)
        let gg = min(max(g, 0), 255)
        let bb = min(max(b, 0), 255)
        return String(format: "#%02X%02X%02X", rr, gg, bb)
    }

    public var svgOpacity: String {
        opacity.formatted(.number.precision(.fractionLength(3)))
    }
}
