import CoreGraphics
import Foundation

/// Bridges 2D `NodeFrame` layouts and 3D `NodeFrame3D` layouts for dual-mode canvases.
///
/// SceneKit uses Y-up. 2D diagrams live in an X/Y plane on screen. Projection maps:
/// - **Flatten**: 3D `(x, y, z)` → 2D frame centered at `(x, z)` (drop world Y).
/// - **Lift**: 2D frame center `(cx, cy)` → 3D `(cx, 0, cy)` (place on the XZ plane).
public nonisolated enum LayoutProjection {
    /// Orthographic drop of world Y; preserves `size` as the 2D frame size.
    public static func flatten(_ nodes: [NodeFrame3D]) -> [NodeFrame] {
        nodes.map { node in
            let w = node.size.width
            let h = node.size.height
            let cx = CGFloat(node.position.x)
            let cy = CGFloat(node.position.z)
            return NodeFrame(
                id: node.id,
                frame: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
            )
        }
    }

    /// Places each 2D frame on the SceneKit XZ plane at y = 0.
    public static func lift(_ frames: [NodeFrame]) -> [NodeFrame3D] {
        frames.map { frame in
            NodeFrame3D(
                id: frame.id,
                position: DiagramPosition3D(
                    x: Float(frame.frame.midX),
                    y: 0,
                    z: Float(frame.frame.midY)
                ),
                size: frame.frame.size
            )
        }
    }

    /// Identity check helper: lift then flatten should recover centers (within epsilon).
    public static func centersMatch2D(_ a: [NodeFrame], _ b: [NodeFrame], epsilon: CGFloat = 0.5) -> Bool {
        guard a.count == b.count else { return false }
        let byID = Dictionary(uniqueKeysWithValues: b.map { ($0.id, $0) })
        for left in a {
            guard let right = byID[left.id] else { return false }
            if abs(left.frame.midX - right.frame.midX) > epsilon { return false }
            if abs(left.frame.midY - right.frame.midY) > epsilon { return false }
            if abs(left.frame.width - right.frame.width) > epsilon { return false }
            if abs(left.frame.height - right.frame.height) > epsilon { return false }
        }
        return true
    }
}
