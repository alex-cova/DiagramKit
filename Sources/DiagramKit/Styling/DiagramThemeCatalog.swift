import Foundation

public nonisolated enum DiagramThemeCatalog {
    public static let light = DiagramTheme(
        id: "light",
        displayName: "Light",
        canvasBackground: CodableColor(red: 0.98, green: 0.98, blue: 0.99, opacity: 1),
        gridMinor: CodableColor(red: 0.55, green: 0.55, blue: 0.60, opacity: 0.12),
        gridMajor: CodableColor(red: 0.45, green: 0.45, blue: 0.50, opacity: 0.18),
        selectionFill: CodableColor(red: 0.20, green: 0.45, blue: 0.95, opacity: 0.12),
        selectionStroke: CodableColor(red: 0.20, green: 0.45, blue: 0.95, opacity: 0.70),
        defaultNodeFill: .classFill,
        defaultNodeStroke: .classStroke,
        defaultEdgeStroke: CodableColor(red: 0.20, green: 0.22, blue: 0.28, opacity: 1),
        accent: CodableColor(red: 0.20, green: 0.45, blue: 0.95, opacity: 1)
    )

    public static let dark = DiagramTheme(
        id: "dark",
        displayName: "Dark",
        canvasBackground: CodableColor(red: 0.12, green: 0.13, blue: 0.15, opacity: 1),
        gridMinor: CodableColor(red: 0.85, green: 0.88, blue: 0.95, opacity: 0.08),
        gridMajor: CodableColor(red: 0.85, green: 0.88, blue: 0.95, opacity: 0.14),
        selectionFill: CodableColor(red: 0.35, green: 0.60, blue: 1.0, opacity: 0.18),
        selectionStroke: CodableColor(red: 0.45, green: 0.70, blue: 1.0, opacity: 0.80),
        defaultNodeFill: .classFillDark,
        defaultNodeStroke: .classStrokeDark,
        defaultEdgeStroke: CodableColor(red: 0.75, green: 0.78, blue: 0.85, opacity: 1),
        accent: CodableColor(red: 0.40, green: 0.65, blue: 1.0, opacity: 1)
    )

    public static let blueprint = DiagramTheme(
        id: "blueprint",
        displayName: "Blueprint",
        canvasBackground: CodableColor(red: 0.08, green: 0.22, blue: 0.45, opacity: 1),
        gridMinor: CodableColor(red: 0.55, green: 0.75, blue: 1.0, opacity: 0.15),
        gridMajor: CodableColor(red: 0.70, green: 0.85, blue: 1.0, opacity: 0.28),
        selectionFill: CodableColor(red: 1.0, green: 0.85, blue: 0.20, opacity: 0.15),
        selectionStroke: CodableColor(red: 1.0, green: 0.90, blue: 0.30, opacity: 0.85),
        defaultNodeFill: CodableColor(red: 0.10, green: 0.28, blue: 0.55, opacity: 1),
        defaultNodeStroke: CodableColor(red: 0.75, green: 0.90, blue: 1.0, opacity: 1),
        defaultEdgeStroke: CodableColor(red: 0.85, green: 0.95, blue: 1.0, opacity: 1),
        accent: CodableColor(red: 1.0, green: 0.88, blue: 0.25, opacity: 1)
    )

    public static let sketch = DiagramTheme(
        id: "sketch",
        displayName: "Sketch",
        canvasBackground: CodableColor(red: 0.96, green: 0.94, blue: 0.88, opacity: 1),
        gridMinor: CodableColor(red: 0.55, green: 0.50, blue: 0.40, opacity: 0.10),
        gridMajor: CodableColor(red: 0.45, green: 0.40, blue: 0.30, opacity: 0.18),
        selectionFill: CodableColor(red: 0.85, green: 0.35, blue: 0.20, opacity: 0.12),
        selectionStroke: CodableColor(red: 0.75, green: 0.30, blue: 0.15, opacity: 0.75),
        defaultNodeFill: CodableColor(red: 1.0, green: 0.99, blue: 0.95, opacity: 1),
        defaultNodeStroke: CodableColor(red: 0.25, green: 0.22, blue: 0.18, opacity: 1),
        defaultEdgeStroke: CodableColor(red: 0.28, green: 0.24, blue: 0.20, opacity: 1),
        accent: CodableColor(red: 0.80, green: 0.32, blue: 0.18, opacity: 1)
    )

    public static let presentation = DiagramTheme(
        id: "presentation",
        displayName: "Presentation",
        canvasBackground: CodableColor(red: 1.0, green: 1.0, blue: 1.0, opacity: 1),
        gridMinor: CodableColor(red: 0.70, green: 0.72, blue: 0.76, opacity: 0.10),
        gridMajor: CodableColor(red: 0.55, green: 0.58, blue: 0.64, opacity: 0.16),
        selectionFill: CodableColor(red: 0.10, green: 0.55, blue: 0.75, opacity: 0.12),
        selectionStroke: CodableColor(red: 0.05, green: 0.45, blue: 0.70, opacity: 0.80),
        defaultNodeFill: CodableColor(red: 0.95, green: 0.97, blue: 1.0, opacity: 1),
        defaultNodeStroke: CodableColor(red: 0.15, green: 0.35, blue: 0.55, opacity: 1),
        defaultEdgeStroke: CodableColor(red: 0.15, green: 0.25, blue: 0.40, opacity: 1),
        accent: CodableColor(red: 0.05, green: 0.50, blue: 0.75, opacity: 1)
    )

    public static let chalkboard = DiagramTheme(
        id: "chalkboard",
        displayName: "Chalkboard",
        canvasBackground: CodableColor(red: 0.17, green: 0.28, blue: 0.22, opacity: 1),
        gridMinor: CodableColor(red: 0.85, green: 0.90, blue: 0.80, opacity: 0.08),
        gridMajor: CodableColor(red: 0.85, green: 0.90, blue: 0.80, opacity: 0.14),
        selectionFill: CodableColor(red: 1.0, green: 0.88, blue: 0.25, opacity: 0.15),
        selectionStroke: CodableColor(red: 1.0, green: 0.90, blue: 0.30, opacity: 0.85),
        defaultNodeFill: CodableColor(red: 0.95, green: 0.88, blue: 0.35, opacity: 0.85),
        defaultNodeStroke: CodableColor(red: 0.95, green: 0.95, blue: 0.90, opacity: 1),
        defaultEdgeStroke: CodableColor(red: 0.95, green: 0.95, blue: 0.90, opacity: 1),
        accent: CodableColor(red: 1.0, green: 0.88, blue: 0.25, opacity: 1)
    )

    public static let all: [DiagramTheme] = [light, dark, blueprint, sketch, presentation, chalkboard]

    /// `CanvasSettings.theme` resolves through here on every access — including up to 3× per edge
    /// inside the connection-layer draw loops — so a dictionary lookup instead of `all.first {}`
    /// (a linear scan with a `String` compare per candidate) matters at that call frequency.
    private static let byID: [String: DiagramTheme] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func theme(id: String) -> DiagramTheme {
        byID[id] ?? light
    }

    /// Maps the appearance-adaptive `light` / `dark` themes to the matching palette.
    public static func resolvedID(id: String, forDarkAppearance isDark: Bool) -> String {
        switch (id, isDark) {
        case (light.id, true): dark.id
        case (dark.id, false): light.id
        default: id
        }
    }

    public static func resolved(id: String, forDarkAppearance isDark: Bool) -> DiagramTheme {
        theme(id: resolvedID(id: id, forDarkAppearance: isDark))
    }
}
