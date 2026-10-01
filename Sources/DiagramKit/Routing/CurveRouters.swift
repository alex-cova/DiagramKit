import CoreGraphics
import Foundation

/// Cubic Bézier between perimeter anchors; samples to a polyline for hit-testing/drawing.
public nonisolated enum BezierRouter {
    public static func route(
        source: CGRect,
        target: CGRect,
        sourceAnchor: EdgeAnchor = .auto,
        targetAnchor: EdgeAnchor = .auto,
        samples: Int = 20
    ) -> EdgeRoute {
        let start = EdgeRouting.point(on: source, anchor: sourceAnchor, toward: target.center)
        let end = EdgeRouting.point(on: target, anchor: targetAnchor, toward: source.center)
        let c1 = control(from: start, on: source, toward: end)
        let c2 = control(from: end, on: target, toward: start)
        return EdgeRoute(points: sampleCubic(p0: start, p1: c1, p2: c2, p3: end, samples: samples))
    }

    private static func control(from point: CGPoint, on rect: CGRect, toward focus: CGPoint) -> CGPoint {
        let side = OrthogonalRouter.facingSide(of: point, on: rect)
        let pull = max(rect.width, rect.height) * 0.55 + 40
        switch side {
        case .left: return CGPoint(x: point.x - pull, y: point.y)
        case .right: return CGPoint(x: point.x + pull, y: point.y)
        case .top: return CGPoint(x: point.x, y: point.y - pull)
        case .bottom: return CGPoint(x: point.x, y: point.y + pull)
        }
    }

    public static func sampleCubic(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, samples: Int) -> [CGPoint] {
        let n = max(2, samples)
        return (0...n).map { i in
            let t = CGFloat(i) / CGFloat(n)
            let u = 1 - t
            let x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
            let y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
            return CGPoint(x: x, y: y)
        }
    }
}

/// Catmull–Rom spline through orthogonal guide points, sampled to a smooth polyline.
public nonisolated enum SplineRouter {
    public static func route(
        source: CGRect,
        target: CGRect,
        sourceAnchor: EdgeAnchor = .auto,
        targetAnchor: EdgeAnchor = .auto,
        samplesPerSegment: Int = 8
    ) -> EdgeRoute {
        let ortho = OrthogonalRouter.route(
            source: source,
            target: target,
            sourceAnchor: sourceAnchor,
            targetAnchor: targetAnchor
        )
        let guides = ortho.points
        guard guides.count >= 2 else { return ortho }
        if guides.count == 2 {
            return BezierRouter.route(
                source: source,
                target: target,
                sourceAnchor: sourceAnchor,
                targetAnchor: targetAnchor
            )
        }
        var points: [CGPoint] = []
        for i in 0..<(guides.count - 1) {
            let p0 = guides[max(0, i - 1)]
            let p1 = guides[i]
            let p2 = guides[i + 1]
            let p3 = guides[min(guides.count - 1, i + 2)]
            let segmentSamples = sampleCatmullRom(p0: p0, p1: p1, p2: p2, p3: p3, samples: samplesPerSegment)
            if i > 0 { points.removeLast() }
            points.append(contentsOf: segmentSamples)
        }
        return EdgeRoute(points: points)
    }

    private static func sampleCatmullRom(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        samples: Int
    ) -> [CGPoint] {
        let n = max(2, samples)
        return (0...n).map { i in
            let t = CGFloat(i) / CGFloat(n)
            let t2 = t * t
            let t3 = t2 * t
            let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t
                + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
            let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t
                + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
            return CGPoint(x: x, y: y)
        }
    }
}
