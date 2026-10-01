import CoreGraphics
import Foundation
import simd

/// Codable 3D position stored on mind-map (and other 3D-capable) diagram nodes.
public nonisolated struct DiagramPosition3D: Codable, Sendable, Equatable, Hashable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float = 0, y: Float = 0, z: Float = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ vector: SIMD3<Float>) {
        self.x = vector.x
        self.y = vector.y
        self.z = vector.z
    }

    public var simd: SIMD3<Float> {
        SIMD3(x, y, z)
    }

    public static let zero = DiagramPosition3D()
}

/// Laid-out node geometry in 3D world space (Y-up, matching SceneKit).
public nonisolated struct NodeFrame3D: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var position: DiagramPosition3D
    /// Billboard / capsule half-extents used for spacing and SceneKit box sizing.
    public var size: CGSize

    public init(id: UUID, position: DiagramPosition3D, size: CGSize = CGSize(width: 120, height: 40)) {
        self.id = id
        self.position = position
        self.size = size
    }

    public init(id: UUID, position: SIMD3<Float>, size: CGSize = CGSize(width: 120, height: 40)) {
        self.id = id
        self.position = DiagramPosition3D(position)
        self.size = size
    }
}
