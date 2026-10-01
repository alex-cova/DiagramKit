import CoreGraphics
import Foundation

/// Input graph for 3D layout algorithms. Sizes come from each node's 2D frame when lifting
/// from a flat document; pure-3D callers can supply `NodeFrame3D` directly.
public nonisolated struct LayoutGraph3D: Sendable {
    public var nodes: [NodeFrame3D]
    public var edges: [(source: UUID, destination: UUID)]

    public init(nodes: [NodeFrame3D], edges: [(source: UUID, destination: UUID)] = []) {
        self.nodes = nodes
        self.edges = edges
    }

    /// Build from 2D frames (z = 0) — typical path when a document only stores `CGRect`s yet.
    public init(frames: [NodeFrame], edges: [(source: UUID, destination: UUID)] = []) {
        self.nodes = frames.map { frame in
            let center = CGPoint(x: frame.frame.midX, y: frame.frame.midY)
            return NodeFrame3D(
                id: frame.id,
                position: DiagramPosition3D(x: Float(center.x), y: 0, z: Float(center.y)),
                size: frame.frame.size
            )
        }
        self.edges = edges
    }
}

public nonisolated struct LayoutOptions3D: Sendable {
    public var origin: DiagramPosition3D
    /// Radial gap between successive depth shells.
    public var radialSpacing: Float
    /// Extra gap when packing disconnected components along +X.
    public var componentSpacing: Float

    public init(
        origin: DiagramPosition3D = .zero,
        radialSpacing: Float = 180,
        componentSpacing: Float = 320
    ) {
        self.origin = origin
        self.radialSpacing = radialSpacing
        self.componentSpacing = componentSpacing
    }
}

public nonisolated protocol LayoutAlgorithm3D: Sendable {
    func layout(_ graph: LayoutGraph3D, options: LayoutOptions3D) -> [NodeFrame3D]
}
