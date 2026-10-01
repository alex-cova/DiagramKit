import CoreGraphics
import Foundation

/// Viewport / world-space visibility helpers for virtualized rendering.
public nonisolated enum ViewportCulling {
    /// Extra world-space margin so partially entering nodes still draw.
    public static let defaultPadding: CGFloat = 64

    public static func isVisible(frame: CGRect, in worldRect: CGRect) -> Bool {
        guard !worldRect.isNull, !worldRect.isInfinite else { return true }
        return frame.intersects(worldRect)
    }

    public static func isRouteVisible(_ route: EdgeRoute, in worldRect: CGRect, padding: CGFloat = 8) -> Bool {
        guard !worldRect.isNull, !worldRect.isInfinite else { return true }
        let box = route.boundingBox.insetBy(dx: -padding, dy: -padding)
        return box.intersects(worldRect)
    }

    public static func visibleNodes<Node: DiagramNode>(
        _ nodes: [Node],
        in worldRect: CGRect
    ) -> [Node] {
        guard !worldRect.isNull, !worldRect.isInfinite else { return nodes }
        return nodes.filter { isVisible(frame: $0.frame, in: worldRect) }
    }
}

public extension ViewportState {
    /// World-space rectangle currently visible for a view of `viewSize`.
    nonisolated func visibleWorldRect(viewSize: CGSize, padding: CGFloat = ViewportCulling.defaultPadding) -> CGRect {
        let a = viewToWorld(.zero)
        let b = viewToWorld(CGPoint(x: viewSize.width, y: viewSize.height))
        let rect = CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
        return rect.insetBy(dx: -padding, dy: -padding)
    }
}
