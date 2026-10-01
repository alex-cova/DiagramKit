import CoreGraphics
import Foundation

public nonisolated enum CanvasEngine {
    public static let resizeHandleSize: CGFloat = 8
    public static let edgeHitTolerance: CGFloat = 8

    public static func contentBounds<Node: DiagramNode>(nodes: [Node], padding: CGFloat = 40) -> CGRect {
        guard let first = nodes.first else {
            return CGRect(x: 0, y: 0, width: 400, height: 300)
        }
        var bounds = first.frame
        for node in nodes.dropFirst() {
            bounds = bounds.union(node.frame)
        }
        return bounds.insetBy(dx: -padding, dy: -padding)
    }

    public static func hitTestNode<Node: DiagramNode>(at worldPoint: CGPoint, nodes: [Node]) -> UUID? {
        // Top-most last wins (later nodes drawn above).
        for node in nodes.reversed() {
            if node.frame.contains(worldPoint) {
                return node.id
            }
        }
        return nil
    }

    public static func hitTestNode(at worldPoint: CGPoint, index: SpatialIndex) -> UUID? {
        index.hitTest(at: worldPoint)
    }

    public static func hitTestResizeHandle(at worldPoint: CGPoint, frame: CGRect, zoom: CGFloat) -> Bool {
        let handle = resizeHandleRect(for: frame, zoom: zoom)
        return handle.contains(worldPoint)
    }

    public static func resizeHandleRect(for frame: CGRect, zoom: CGFloat) -> CGRect {
        let size = resizeHandleSize / max(zoom, 0.01)
        return CGRect(
            x: frame.maxX - size / 2,
            y: frame.maxY - size / 2,
            width: size,
            height: size
        )
    }

    public static func nodesIntersecting<Node: DiagramNode>(marquee: CGRect, nodes: [Node]) -> Set<UUID> {
        Set(nodes.filter { $0.frame.intersects(marquee) }.map(\.id))
    }

    public static func nodesIntersecting(marquee: CGRect, index: SpatialIndex) -> Set<UUID> {
        index.intersecting(marquee)
    }

    public static func distanceToSegment(_ point: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: point.x - a.x, y: point.y - a.y)
        let abLen2 = ab.x * ab.x + ab.y * ab.y
        guard abLen2 > 0 else {
            return hypot(ap.x, ap.y)
        }
        let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / abLen2))
        let proj = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
        return hypot(point.x - proj.x, point.y - proj.y)
    }

    /// Hit-test edges given precomputed polyline routes (domain owns routing/anchors).
    public static func hitTestEdge(
        at worldPoint: CGPoint,
        routes: [(id: UUID, route: EdgeRoute)],
        zoom: CGFloat
    ) -> UUID? {
        let tolerance = edgeHitTolerance / max(zoom, 0.01)
        for item in routes.reversed() {
            let points = item.route.points
            guard points.count >= 2 else { continue }
            for index in 0..<(points.count - 1) {
                if distanceToSegment(worldPoint, from: points[index], to: points[index + 1]) <= tolerance {
                    return item.id
                }
            }
        }
        return nil
    }

    public static func clampMinSize(_ size: CGSize, minimum: CGSize = CGSize(width: 140, height: 100)) -> CGSize {
        CGSize(width: max(minimum.width, size.width), height: max(minimum.height, size.height))
    }
}
