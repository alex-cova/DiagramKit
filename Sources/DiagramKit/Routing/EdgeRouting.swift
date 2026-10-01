import CoreGraphics
import Foundation

public nonisolated enum EdgeAnchor: Codable, Sendable, Equatable {
    case auto
    case side(Side, t: CGFloat)

    public enum Side: String, Codable, Sendable {
        case top, bottom, left, right
    }
}

public nonisolated enum EdgeRoutingStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case straight
    case orthogonal
    case bezier
    case spline

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .straight: "Straight"
        case .orthogonal: "Orthogonal"
        case .bezier: "Bézier"
        case .spline: "Spline"
        }
    }
}

/// Polyline route in world space (≥2 points). Curves are sampled into polylines.
public nonisolated struct EdgeRoute: Equatable, Sendable {
    public var points: [CGPoint]

    public var start: CGPoint { points.first ?? .zero }
    public var end: CGPoint { points.last ?? .zero }

    public init(points: [CGPoint]) {
        if points.count >= 2 {
            self.points = points
        } else if let only = points.first {
            self.points = [only, only]
        } else {
            self.points = [.zero, .zero]
        }
    }

    public init(start: CGPoint, end: CGPoint) {
        self.points = [start, end]
    }
}

public nonisolated struct EdgeRoutingContext: Sendable {
    public var style: EdgeRoutingStyle
    public var obstacles: [CGRect]
    public var avoidObstacles: Bool

    public init(
        style: EdgeRoutingStyle = .orthogonal,
        obstacles: [CGRect] = [],
        avoidObstacles: Bool = true
    ) {
        self.style = style
        self.obstacles = obstacles
        self.avoidObstacles = avoidObstacles
    }
}

public nonisolated enum EdgeRouting {
    /// Straight line between perimeter anchors (auto = nearest side midpoints along connecting vector).
    public static func route(
        source: CGRect,
        target: CGRect,
        sourceAnchor: EdgeAnchor = .auto,
        targetAnchor: EdgeAnchor = .auto
    ) -> EdgeRoute {
        let start = point(on: source, anchor: sourceAnchor, toward: target.center)
        let end = point(on: target, anchor: targetAnchor, toward: source.center)
        return EdgeRoute(start: start, end: end)
    }

    public static func route(
        source: CGRect,
        target: CGRect,
        sourceAnchor: EdgeAnchor = .auto,
        targetAnchor: EdgeAnchor = .auto,
        style: EdgeRoutingStyle
    ) -> EdgeRoute {
        route(
            source: source,
            target: target,
            sourceAnchor: sourceAnchor,
            targetAnchor: targetAnchor,
            context: EdgeRoutingContext(style: style, obstacles: [], avoidObstacles: false)
        )
    }

    public static func route(
        source: CGRect,
        target: CGRect,
        sourceAnchor: EdgeAnchor = .auto,
        targetAnchor: EdgeAnchor = .auto,
        context: EdgeRoutingContext
    ) -> EdgeRoute {
        let base: EdgeRoute
        switch context.style {
        case .straight:
            base = route(source: source, target: target, sourceAnchor: sourceAnchor, targetAnchor: targetAnchor)
        case .orthogonal:
            base = OrthogonalRouter.route(
                source: source,
                target: target,
                sourceAnchor: sourceAnchor,
                targetAnchor: targetAnchor
            )
        case .bezier:
            base = BezierRouter.route(
                source: source,
                target: target,
                sourceAnchor: sourceAnchor,
                targetAnchor: targetAnchor
            )
        case .spline:
            base = SplineRouter.route(
                source: source,
                target: target,
                sourceAnchor: sourceAnchor,
                targetAnchor: targetAnchor
            )
        }

        guard context.avoidObstacles, !context.obstacles.isEmpty else { return base }
        let filtered = ObstacleAvoider.obstacles(
            from: context.obstacles,
            excluding: source,
            target: target
        )
        return ObstacleAvoider.apply(base, obstacles: filtered)
    }

    public static func point(on rect: CGRect, anchor: EdgeAnchor, toward focus: CGPoint) -> CGPoint {
        switch anchor {
        case .auto:
            return autoAnchor(on: rect, toward: focus)
        case .side(let side, let t):
            let clamped = max(0, min(1, t))
            switch side {
            case .top:
                return CGPoint(x: rect.minX + rect.width * clamped, y: rect.minY)
            case .bottom:
                return CGPoint(x: rect.minX + rect.width * clamped, y: rect.maxY)
            case .left:
                return CGPoint(x: rect.minX, y: rect.minY + rect.height * clamped)
            case .right:
                return CGPoint(x: rect.maxX, y: rect.minY + rect.height * clamped)
            }
        }
    }

    public static func autoAnchor(on rect: CGRect, toward focus: CGPoint) -> CGPoint {
        let center = rect.center
        let dx = focus.x - center.x
        let dy = focus.y - center.y
        if abs(dx) > abs(dy) {
            return dx >= 0
                ? CGPoint(x: rect.maxX, y: center.y)
                : CGPoint(x: rect.minX, y: center.y)
        }
        return dy >= 0
            ? CGPoint(x: center.x, y: rect.maxY)
            : CGPoint(x: center.x, y: rect.minY)
    }
}

public extension CGRect {
    nonisolated var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
