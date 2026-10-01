import CoreGraphics
import Foundation

/// Manhattan (orthogonal) routes: L or Z elbows between node perimeter anchors.
public nonisolated enum OrthogonalRouter {
    public static func route(
        source: CGRect,
        target: CGRect,
        sourceAnchor: EdgeAnchor = .auto,
        targetAnchor: EdgeAnchor = .auto
    ) -> EdgeRoute {
        let start = EdgeRouting.point(on: source, anchor: sourceAnchor, toward: target.center)
        let end = EdgeRouting.point(on: target, anchor: targetAnchor, toward: source.center)

        if abs(start.x - end.x) < 0.5 || abs(start.y - end.y) < 0.5 {
            return EdgeRoute(start: start, end: end)
        }

        let startSide = facingSide(of: start, on: source)
        let endSide = facingSide(of: end, on: target)

        let mid: CGPoint
        switch (startSide, endSide) {
        case (.left, .left), (.right, .right):
            let x = (start.x + end.x) / 2
            return EdgeRoute(points: [
                start,
                CGPoint(x: x, y: start.y),
                CGPoint(x: x, y: end.y),
                end,
            ])
        case (.top, .top), (.bottom, .bottom):
            let y = (start.y + end.y) / 2
            return EdgeRoute(points: [
                start,
                CGPoint(x: start.x, y: y),
                CGPoint(x: end.x, y: y),
                end,
            ])
        case (.left, .right), (.right, .left):
            let x = (start.x + end.x) / 2
            return EdgeRoute(points: [
                start,
                CGPoint(x: x, y: start.y),
                CGPoint(x: x, y: end.y),
                end,
            ])
        case (.top, .bottom), (.bottom, .top):
            let y = (start.y + end.y) / 2
            return EdgeRoute(points: [
                start,
                CGPoint(x: start.x, y: y),
                CGPoint(x: end.x, y: y),
                end,
            ])
        default:
            if startSide == .left || startSide == .right {
                mid = CGPoint(x: end.x, y: start.y)
            } else {
                mid = CGPoint(x: start.x, y: end.y)
            }
            return EdgeRoute(points: [start, mid, end])
        }
    }

    public static func facingSide(of point: CGPoint, on rect: CGRect) -> EdgeAnchor.Side {
        let distLeft = abs(point.x - rect.minX)
        let distRight = abs(point.x - rect.maxX)
        let distTop = abs(point.y - rect.minY)
        let distBottom = abs(point.y - rect.maxY)
        let minDist = min(distLeft, distRight, distTop, distBottom)
        if minDist == distLeft { return .left }
        if minDist == distRight { return .right }
        if minDist == distTop { return .top }
        return .bottom
    }
}
