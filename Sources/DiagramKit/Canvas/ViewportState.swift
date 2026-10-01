import CoreGraphics
import Foundation

public nonisolated struct ViewportState: Equatable, Sendable {
    public var offset: CGPoint
    public var zoom: CGFloat

    public static let minZoom: CGFloat = 0.25
    public static let maxZoom: CGFloat = 4.0
    public static let `default` = ViewportState(offset: CGPoint(x: 40, y: 40), zoom: 1)

    public init(offset: CGPoint = .zero, zoom: CGFloat = 1) {
        self.offset = offset
        self.zoom = min(Self.maxZoom, max(Self.minZoom, zoom))
    }

    public func viewToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - offset.x) / zoom,
            y: (point.y - offset.y) / zoom
        )
    }

    public func worldToView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * zoom + offset.x,
            y: point.y * zoom + offset.y
        )
    }

    public func worldToView(_ rect: CGRect) -> CGRect {
        let origin = worldToView(rect.origin)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * zoom, height: rect.height * zoom)
    }

    public func pan(by delta: CGSize) -> ViewportState {
        ViewportState(
            offset: CGPoint(x: offset.x + delta.width, y: offset.y + delta.height),
            zoom: zoom
        )
    }

    /// Zoom while keeping the world point under `viewPoint` fixed on screen.
    public func zoom(by factor: CGFloat, toward viewPoint: CGPoint) -> ViewportState {
        let world = viewToWorld(viewPoint)
        let nextZoom = min(Self.maxZoom, max(Self.minZoom, zoom * factor))
        let nextOffset = CGPoint(
            x: viewPoint.x - world.x * nextZoom,
            y: viewPoint.y - world.y * nextZoom
        )
        return ViewportState(offset: nextOffset, zoom: nextZoom)
    }

    /// Default step for toolbar zoom in / out.
    public static let zoomStep: CGFloat = 1.25

    /// Pan so `bounds` center sits in the middle of `viewSize`, keeping current zoom.
    public func centered(on bounds: CGRect, in viewSize: CGSize) -> ViewportState {
        guard viewSize.width > 0, viewSize.height > 0 else { return self }
        let offset = CGPoint(
            x: viewSize.width / 2 - bounds.midX * zoom,
            y: viewSize.height / 2 - bounds.midY * zoom
        )
        return ViewportState(offset: offset, zoom: zoom)
    }

    /// Zoom 100% and center `bounds` in the view.
    public static func oneToOne(centering bounds: CGRect, in viewSize: CGSize) -> ViewportState {
        ViewportState(offset: .zero, zoom: 1).centered(on: bounds, in: viewSize)
    }

    /// Scale and pan so `bounds` fits inside `viewSize` with a small margin.
    public static func fitting(
        bounds: CGRect,
        in viewSize: CGSize,
        margin: CGFloat = 0.9
    ) -> ViewportState? {
        guard bounds.width > 0, bounds.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return nil }
        let zoom = min(viewSize.width / bounds.width, viewSize.height / bounds.height, maxZoom)
        let clampedZoom = max(minZoom, zoom * margin)
        let offset = CGPoint(
            x: (viewSize.width - bounds.width * clampedZoom) / 2 - bounds.minX * clampedZoom,
            y: (viewSize.height - bounds.height * clampedZoom) / 2 - bounds.minY * clampedZoom
        )
        return ViewportState(offset: offset, zoom: clampedZoom)
    }

    public func zoomedIn(toward viewPoint: CGPoint, step: CGFloat = zoomStep) -> ViewportState {
        zoom(by: step, toward: viewPoint)
    }

    public func zoomedOut(toward viewPoint: CGPoint, step: CGFloat = zoomStep) -> ViewportState {
        zoom(by: 1 / step, toward: viewPoint)
    }
}
