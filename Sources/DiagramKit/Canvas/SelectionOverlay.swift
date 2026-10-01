import SwiftUI

public struct SelectionOverlay: View {
    public let marquee: CGRect?
    public let viewport: ViewportState
    public var theme: DiagramTheme = DiagramThemeCatalog.light

    public var body: some View {
        Canvas { context, _ in
            guard let marquee else { return }
            let rect = viewport.worldToView(marquee)
            let path = Path(rect)
            context.fill(path, with: .color(theme.selectionFill.swiftUIColor))
            context.stroke(path, with: .color(theme.selectionStroke.swiftUIColor), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
    public init(
        marquee: CGRect? = nil,
        viewport: ViewportState,
        theme: DiagramTheme = DiagramThemeCatalog.light
    ) {
        self.marquee = marquee
        self.viewport = viewport
        self.theme = theme
    }
}
