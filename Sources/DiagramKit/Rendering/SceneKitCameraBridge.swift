import AppKit
import Observation
import SceneKit
import simd

/// Toolbar-driven camera framing for `SceneKitDiagramView` (zoom / center / fit / 1:1).
///
/// The representable attaches the live `SCNView` after each scene build. Zoom percent is
/// relative to the default framing distance (`100%` ≈ the initial “1:1” pose).
@MainActor
@Observable
public final class SceneKitCameraBridge {
    private weak var view: SCNView?
    private var contentMin = SIMD3<Float>.zero
    private var contentMax = SIMD3<Float>.zero
    private var hasContent = false
    /// Camera↔target distance that corresponds to 100% (default framing).
    private var referenceDistance: Float = 640

    public private(set) var zoomPercent: Int = 100

    public var canFrameContent: Bool { hasContent && view != nil }

    public func attach(view: SCNView, minBound: SIMD3<Float>, maxBound: SIMD3<Float>) {
        self.view = view
        contentMin = minBound
        contentMax = maxBound
        hasContent = minBound.x.isFinite && maxBound.x.isFinite
            && minBound.x != .greatestFiniteMagnitude
        if hasContent {
            let pose = SceneKitDiagramHost.defaultCameraPose(minBound: minBound, maxBound: maxBound)
            referenceDistance = max(length(pose.position - pose.target), 1)
        }
        refreshZoomPercent()
    }

    public func detach() {
        view = nil
        hasContent = false
        zoomPercent = 100
    }

    public func zoomIn() {
        zoom(by: 1 / ViewportState.zoomStep)
    }

    public func zoomOut() {
        zoom(by: ViewportState.zoomStep)
    }

    /// Scroll-wheel / trackpad zoom while pan mode has camera control disabled.
    public func scrollZoom(by factor: CGFloat) {
        zoom(by: factor)
    }

    /// Restore the default framing distance and look-at (diagram “actual size”).
    public func resetOneToOne() {
        applyDefaultPose()
    }

    /// Keep distance/orbit, but look at the content centroid.
    public func center() {
        guard let view, let pov = view.pointOfView, hasContent else { return }
        let center = contentCenter
        let controller = view.defaultCameraController
        let oldTarget = simdTarget(controller.target)
        let offset = simdPosition(pov.worldPosition) - oldTarget
        let newPosition = center + offset
        controller.target = scn(center)
        pov.simdWorldPosition = newPosition
        pov.look(at: scn(center))
        refreshZoomPercent()
    }

    /// Frame all content into the current viewport.
    public func fit() {
        guard let view, hasContent else { return }
        if let scene = view.scene {
            let nodes = SceneKitDiagramHost.frameableNodes(in: scene)
            if !nodes.isEmpty {
                view.defaultCameraController.frameNodes(nodes)
                refreshZoomPercent()
                return
            }
        }
        applyDefaultPose()
    }

    // MARK: - Internals

    private var contentCenter: SIMD3<Float> {
        (contentMin + contentMax) * 0.5
    }

    private func zoom(by factor: CGFloat) {
        guard let view else { return }
        let applied = SceneKitCameraZoom.apply(
            factor: factor,
            in: view,
            referenceDistance: hasContent ? referenceDistance : nil
        )
        guard applied else { return }
        refreshZoomPercent()
    }

    private func applyDefaultPose() {
        guard let view, let pov = view.pointOfView, hasContent else { return }
        let pose = SceneKitDiagramHost.defaultCameraPose(minBound: contentMin, maxBound: contentMax)
        view.defaultCameraController.target = scn(pose.target)
        pov.simdWorldPosition = pose.position
        pov.look(at: scn(pose.target))
        refreshZoomPercent()
    }

    /// Re-read zoom from the live camera after SceneKit camera-control gestures (orbit scroll / pinch).
    public func syncZoomPercent() {
        refreshZoomPercent()
    }

    private func refreshZoomPercent() {
        guard let view, let pov = view.pointOfView, hasContent else {
            zoomPercent = 100
            return
        }
        let target = simdTarget(view.defaultCameraController.target)
        let distance = length(simdPosition(pov.worldPosition) - target)
        let ratio = referenceDistance / max(distance, 1)
        zoomPercent = max(5, min(Int((ratio * 100).rounded()), 4000))
    }

    private func simdPosition(_ v: SCNVector3) -> SIMD3<Float> {
        SIMD3(Float(v.x), Float(v.y), Float(v.z))
    }

    private func simdTarget(_ v: SCNVector3) -> SIMD3<Float> {
        SIMD3(Float(v.x), Float(v.y), Float(v.z))
    }

    private func scn(_ v: SIMD3<Float>) -> SCNVector3 {
        SCNVector3(Double(v.x), Double(v.y), Double(v.z))
    }
    public init() {}
}

/// Shared camera dolly used by toolbar zoom and pan-mode scroll wheel.
@MainActor public enum SceneKitCameraZoom {
    @discardableResult
    public static func apply(factor: CGFloat, in view: SCNView, referenceDistance: Float?) -> Bool {
        guard let pov = view.pointOfView else { return false }
        let controller = view.defaultCameraController
        let target = simdTarget(controller.target)
        let position = simdPosition(pov.worldPosition)
        var offset = position - target
        let distance = length(offset)
        guard distance > 1e-3 else { return false }

        let reference = referenceDistance ?? distance
        let nextDistance = max(40, min(distance * Float(factor), reference * 40))
        offset = normalize(offset) * nextDistance
        pov.simdWorldPosition = target + offset
        pov.look(at: scn(target))
        return true
    }

    public static func factor(for event: NSEvent) -> CGFloat {
        if event.hasPreciseScrollingDeltas {
            return CGFloat(exp(-event.scrollingDeltaY * 0.01))
        }
        return event.scrollingDeltaY > 0 ? 1.1 : 0.9
    }

    public static func factor(forMagnify event: NSEvent) -> CGFloat {
        CGFloat(exp(-event.magnification * 6))
    }

    private static func simdPosition(_ v: SCNVector3) -> SIMD3<Float> {
        SIMD3(Float(v.x), Float(v.y), Float(v.z))
    }

    private static func simdTarget(_ v: SCNVector3) -> SIMD3<Float> {
        SIMD3(Float(v.x), Float(v.y), Float(v.z))
    }

    private static func scn(_ v: SIMD3<Float>) -> SCNVector3 {
        SCNVector3(Double(v.x), Double(v.y), Double(v.z))
    }
}
