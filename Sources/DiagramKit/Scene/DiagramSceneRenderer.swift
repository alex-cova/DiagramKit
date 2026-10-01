import CoreGraphics
import Foundation
import SwiftUI

/// Draws scene nodes/edges into a SwiftUI `GraphicsContext` (canvas virtualization path).
public nonisolated enum DiagramSceneRenderer {
    /// Visible-node count above which nodes are canvas-drawn instead of per-view.
    public static let canvasNodeThreshold = 200

    public static func drawEdges(
        _ edges: [SceneEdge],
        viewport: ViewportState,
        isDarkAppearance: Bool = DiagramAppearance.isDark,
        in context: inout GraphicsContext
    ) {
        for edge in edges {
            guard edge.route.points.count >= 2 else { continue }
            var path = Path()
            let first = viewport.worldToView(edge.route.points[0])
            path.move(to: first)
            for point in edge.route.points.dropFirst() {
                path.addLine(to: viewport.worldToView(point))
            }
            context.stroke(
                path,
                with: .color(edge.stroke.swiftUIColor),
                style: StrokeStyle(
                    lineWidth: edge.lineWidth,
                    dash: edge.isDashed ? [6, 4] : []
                )
            )
            if !edge.label.isEmpty {
                let labelStroke = edge.stroke.diagramDisplayStroke(isDark: isDarkAppearance)
                context.draw(
                    Text(edge.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(labelStroke.swiftUIColor),
                    at: viewport.worldToView(edge.labelPoint),
                    anchor: .center
                )
            }
        }
    }

    public static func drawNodes(
        _ nodes: [SceneNode],
        viewport: ViewportState,
        isDarkAppearance: Bool = DiagramAppearance.isDark,
        in context: inout GraphicsContext
    ) {
        for node in nodes {
            let viewFrame = viewport.worldToView(node.frame)
            let path = Path(node.shape.path(in: viewFrame))
            context.fill(path, with: .color(node.style.fill.swiftUIColor))
            context.stroke(path, with: .color(node.style.stroke.swiftUIColor), lineWidth: node.style.lineWidth)

            let labelColor = node.style.fill.contrastingLabel.swiftUIColor
            if !node.title.isEmpty {
                context.draw(
                    Text(node.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(labelColor),
                    at: CGPoint(x: viewFrame.midX, y: viewFrame.minY + 14),
                    anchor: .center
                )
            }
            var y = viewFrame.minY + 28
            for line in node.compartments.prefix(8) {
                context.draw(
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(labelColor),
                    at: CGPoint(x: viewFrame.minX + 8, y: y),
                    anchor: .leading
                )
                y += 12
            }
        }
    }
}
