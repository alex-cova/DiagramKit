import SwiftUI

public struct GuideOverlay: View {
    public let guides: [GuideLine]
    public let viewport: ViewportState
    public var color: Color = .orange.opacity(0.85)

    public var body: some View {
        Canvas { context, size in
            for guide in guides {
                var path = Path()
                switch guide.axis {
                case .vertical:
                    let x = viewport.worldToView(CGPoint(x: guide.position, y: 0)).x
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                case .horizontal:
                    let y = viewport.worldToView(CGPoint(x: 0, y: guide.position)).y
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
    public init(
        guides: [GuideLine],
        viewport: ViewportState,
        color: Color = .orange.opacity(0.85)
    ) {
        self.guides = guides
        self.viewport = viewport
        self.color = color
    }
}

public struct RulerBars: View {
    public let viewport: ViewportState
    public let viewSize: CGSize
    public var theme: DiagramTheme

    private let thickness: CGFloat = 20

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Corner
            Rectangle()
                .fill(theme.canvasBackground.swiftUIColor.opacity(0.95))
                .frame(width: thickness, height: thickness)

            // Top ruler
            Canvas { context, size in
                drawTicks(axis: .horizontal, in: &context, size: size)
            }
            .frame(width: viewSize.width - thickness, height: thickness)
            .offset(x: thickness)

            // Leading ruler
            Canvas { context, size in
                drawTicks(axis: .vertical, in: &context, size: size)
            }
            .frame(width: thickness, height: viewSize.height - thickness)
            .offset(y: thickness)
        }
        .allowsHitTesting(false)
    }

    private enum Axis { case horizontal, vertical }

    private func drawTicks(axis: Axis, in context: inout GraphicsContext, size: CGSize) {
        let world = viewport.visibleWorldRect(viewSize: viewSize, padding: 0)
        let step = niceStep(for: (axis == .horizontal ? world.width : world.height) / 8)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.canvasBackground.swiftUIColor.opacity(0.92)))

        // One Path/stroke for all tick marks on this axis instead of one per tick; the tick
        // count is already small (~8 per axis via `niceStep`), but labels still resolve their
        // Color once here rather than per `context.draw`.
        let tickColor = theme.gridMajor.swiftUIColor
        let labelColor = theme.canvasBackground.contrastingLabel.swiftUIColor.opacity(0.65)
        var ticks = Path()

        switch axis {
        case .horizontal:
            var x = (world.minX / step).rounded(.down) * step
            while x <= world.maxX {
                let viewX = viewport.worldToView(CGPoint(x: x, y: 0)).x - thickness
                ticks.move(to: CGPoint(x: viewX, y: size.height))
                ticks.addLine(to: CGPoint(x: viewX, y: size.height - 6))
                context.draw(
                    Text("\(Int(x))")
                        .font(.system(size: 8))
                        .foregroundStyle(labelColor),
                    at: CGPoint(x: viewX + 2, y: 4),
                    anchor: .topLeading
                )
                x += step
            }
        case .vertical:
            var y = (world.minY / step).rounded(.down) * step
            while y <= world.maxY {
                let viewY = viewport.worldToView(CGPoint(x: 0, y: y)).y - thickness
                ticks.move(to: CGPoint(x: size.width, y: viewY))
                ticks.addLine(to: CGPoint(x: size.width - 6, y: viewY))
                y += step
            }
        }
        context.stroke(ticks, with: .color(tickColor), lineWidth: 1)
    }

    private func niceStep(for raw: CGFloat) -> CGFloat {
        let magnitude = pow(10, floor(log10(max(raw, 1))))
        let residual = raw / magnitude
        let nice: CGFloat
        if residual < 1.5 { nice = 1 }
        else if residual < 3 { nice = 2 }
        else if residual < 7 { nice = 5 }
        else { nice = 10 }
        return nice * magnitude
    }
    public init(
        viewport: ViewportState,
        viewSize: CGSize,
        theme: DiagramTheme
    ) {
        self.viewport = viewport
        self.viewSize = viewSize
        self.theme = theme
    }
}

public struct MiniMapView: View {
    public let contentBounds: CGRect
    public let nodes: [NodeFrame]
    public let selectedIDs: Set<UUID>
    public let visibleWorldRect: CGRect
    @Binding public var viewport: ViewportState
    public var theme: DiagramTheme

    private let mapSize = CGSize(width: 140, height: 100)

    public var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.canvasBackground.swiftUIColor.opacity(0.9)))
            context.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(theme.gridMajor.swiftUIColor), lineWidth: 1)

            guard contentBounds.width > 0, contentBounds.height > 0 else { return }
            let transform = MiniMapTransform(contentBounds: contentBounds, mapSize: size)

            for node in nodes {
                let mapped = transform.map(node.frame)
                let selected = selectedIDs.contains(node.id)
                context.fill(
                    Path(mapped),
                    with: .color(
                        selected
                            ? theme.accent.swiftUIColor.opacity(0.55)
                            : theme.defaultNodeFill.swiftUIColor
                    )
                )
                context.stroke(
                    Path(mapped),
                    with: .color(
                        selected
                            ? theme.accent.swiftUIColor
                            : theme.defaultNodeStroke.swiftUIColor.opacity(0.85)
                    ),
                    lineWidth: selected ? 1.25 : 0.75
                )
            }

            context.fill(Path(transform.map(visibleWorldRect)), with: .color(theme.accent.swiftUIColor.opacity(0.18)))
            context.stroke(Path(transform.map(visibleWorldRect)), with: .color(theme.accent.swiftUIColor), lineWidth: 1)
        }
        .frame(width: mapSize.width, height: mapSize.height)
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                guard contentBounds.width > 0, contentBounds.height > 0 else { return }
                let transform = MiniMapTransform(contentBounds: contentBounds, mapSize: mapSize)
                let world = transform.worldPoint(for: value.location)
                let half = CGSize(
                    width: visibleWorldRect.width / 2,
                    height: visibleWorldRect.height / 2
                )
                let topLeft = CGPoint(x: world.x - half.width, y: world.y - half.height)
                viewport = ViewportState(
                    offset: CGPoint(x: -topLeft.x * viewport.zoom, y: -topLeft.y * viewport.zoom),
                    zoom: viewport.zoom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 4, y: 2)
    }
    public init(
        contentBounds: CGRect,
        nodes: [NodeFrame],
        selectedIDs: Set<UUID>,
        visibleWorldRect: CGRect,
        viewport: Binding<ViewportState>,
        theme: DiagramTheme
    ) {
        self.contentBounds = contentBounds
        self.nodes = nodes
        self.selectedIDs = selectedIDs
        self.visibleWorldRect = visibleWorldRect
        self._viewport = viewport
        self.theme = theme
    }
}

/// Shared world ↔ minimap projection for drawing and drag navigation.
public nonisolated struct MiniMapTransform: Sendable, Equatable {
    public let scale: CGFloat
    public let offset: CGPoint

    public init(contentBounds: CGRect, mapSize: CGSize) {
        let scale = min(mapSize.width / max(contentBounds.width, 1), mapSize.height / max(contentBounds.height, 1)) * 0.9
        self.scale = scale
        self.offset = CGPoint(
            x: (mapSize.width - contentBounds.width * scale) / 2 - contentBounds.minX * scale,
            y: (mapSize.height - contentBounds.height * scale) / 2 - contentBounds.minY * scale
        )
    }

    public func map(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale + offset.x,
            y: rect.minY * scale + offset.y,
            // Minimum size keeps sub-pixel nodes visible on the minimap.
            width: max(rect.width * scale, 2),
            height: max(rect.height * scale, 2)
        )
    }

    /// Point projection without the rect minimum-size clamp used by `map(_:)`.
    public func mapPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + offset.x,
            y: point.y * scale + offset.y
        )
    }

    public func worldPoint(for mapPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (mapPoint.x - offset.x) / scale,
            y: (mapPoint.y - offset.y) / scale
        )
    }
}
