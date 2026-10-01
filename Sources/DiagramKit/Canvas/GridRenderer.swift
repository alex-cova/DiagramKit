import CoreGraphics
import Foundation

public nonisolated enum GridRenderer {
    /// Minimum on-screen spacing (in points) grid lines must keep. Below this, `gridSize` is
    /// doubled repeatedly before laying out lines — at low zoom, the raw grid otherwise draws
    /// hundreds of sub-pixel-spaced lines that render as a grey wash while costing a full segment
    /// per line. Doubling (rather than picking an arbitrary coarser step) always lands back on a
    /// multiple of the original grid, so lines stay aligned as zoom changes continuously.
    public static let minVisibleSpacing: CGFloat = 4

    /// World-space grid lines visible inside `viewBounds`, returned as view-space segments.
    public static func lines(
        viewBounds: CGRect,
        viewport: ViewportState,
        gridSize: CGFloat
    ) -> [(CGPoint, CGPoint)] {
        guard gridSize > 0, viewport.zoom > 0 else { return [] }

        var effectiveGridSize = gridSize
        while effectiveGridSize * viewport.zoom < minVisibleSpacing {
            effectiveGridSize *= 2
        }

        let worldMin = viewport.viewToWorld(viewBounds.origin)
        let worldMax = viewport.viewToWorld(CGPoint(x: viewBounds.maxX, y: viewBounds.maxY))
        let minX = min(worldMin.x, worldMax.x)
        let maxX = max(worldMin.x, worldMax.x)
        let minY = min(worldMin.y, worldMax.y)
        let maxY = max(worldMin.y, worldMax.y)

        let startX = (minX / effectiveGridSize).rounded(.down) * effectiveGridSize
        let startY = (minY / effectiveGridSize).rounded(.down) * effectiveGridSize

        let approxColumns = Int((maxX - minX) / effectiveGridSize) + 2
        let approxRows = Int((maxY - minY) / effectiveGridSize) + 2
        var segments: [(CGPoint, CGPoint)] = []
        segments.reserveCapacity(max(0, approxColumns) + max(0, approxRows))

        var x = startX
        while x <= maxX + effectiveGridSize {
            let a = viewport.worldToView(CGPoint(x: x, y: minY))
            let b = viewport.worldToView(CGPoint(x: x, y: maxY))
            segments.append((a, b))
            x += effectiveGridSize
        }
        var y = startY
        while y <= maxY + effectiveGridSize {
            let a = viewport.worldToView(CGPoint(x: minX, y: y))
            let b = viewport.worldToView(CGPoint(x: maxX, y: y))
            segments.append((a, b))
            y += effectiveGridSize
        }
        return segments
    }
}
