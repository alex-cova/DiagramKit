import CoreGraphics
import Foundation

/// Reroutes polylines that intersect obstacle rectangles (excluding endpoints' nodes).
public nonisolated enum ObstacleAvoider {
    public static func apply(
        _ route: EdgeRoute,
        obstacles: [CGRect],
        padding: CGFloat = 12
    ) -> EdgeRoute {
        let padded = obstacles.map { $0.insetBy(dx: -padding, dy: -padding) }
        guard !padded.isEmpty else { return route }
        var points = route.points
        guard points.count >= 2 else { return route }

        // Multiple passes so cascading fixes settle.
        for _ in 0..<3 {
            var changed = false
            var next: [CGPoint] = [points[0]]
            for index in 0..<(points.count - 1) {
                let a = points[index]
                let b = points[index + 1]
                if let obstacle = padded.first(where: { segment($0, intersects: a, b) && !$0.contains(a) && !$0.contains(b) }) {
                    let detour = detourPoints(from: a, to: b, around: obstacle)
                    next.append(contentsOf: detour)
                    changed = true
                }
                next.append(b)
            }
            points = simplify(next)
            if !changed { break }
        }
        return EdgeRoute(points: points)
    }

    /// Obstacles that are neither the source nor target node frames.
    public static func obstacles(
        from frames: [CGRect],
        excluding source: CGRect,
        target: CGRect
    ) -> [CGRect] {
        frames.filter { frame in
            !frame.equalTo(source) && !frame.equalTo(target)
        }
    }

    private static func segment(_ rect: CGRect, intersects a: CGPoint, _ b: CGPoint) -> Bool {
        if rect.contains(a) || rect.contains(b) { return true }
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
        for i in 0..<4 {
            if segmentsIntersect(a, b, corners[i], corners[(i + 1) % 4]) {
                return true
            }
        }
        return false
    }

    private static func detourPoints(from a: CGPoint, to b: CGPoint, around rect: CGRect) -> [CGPoint] {
        // Prefer the shorter of two U-shaped orthographic detours around the rect.
        let candidates: [[CGPoint]] = [
            [CGPoint(x: a.x, y: rect.minY), CGPoint(x: b.x, y: rect.minY)],
            [CGPoint(x: a.x, y: rect.maxY), CGPoint(x: b.x, y: rect.maxY)],
            [CGPoint(x: rect.minX, y: a.y), CGPoint(x: rect.minX, y: b.y)],
            [CGPoint(x: rect.maxX, y: a.y), CGPoint(x: rect.maxX, y: b.y)],
        ]
        let best = candidates.min { lhs, rhs in
            pathLength([a] + lhs + [b]) < pathLength([a] + rhs + [b])
        } ?? []
        return best
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for i in 0..<(points.count - 1) {
            total += hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
        }
        return total
    }

    private static func simplify(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var result: [CGPoint] = [points[0]]
        for point in points.dropFirst() {
            if hypot(point.x - result.last!.x, point.y - result.last!.y) > 0.5 {
                result.append(point)
            }
        }
        if result.count == 1, let last = points.last {
            result.append(last)
        }
        return result
    }

    private static func segmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        let d1 = cross(p3, p4, p1)
        let d2 = cross(p3, p4, p2)
        let d3 = cross(p1, p2, p3)
        let d4 = cross(p1, p2, p4)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        return false
    }
}
