import Foundation

/// Shared 2D canvas vs SceneKit presentation toggle for dual-mode diagram tools.
public nonisolated enum DiagramPresentationMode: String, CaseIterable, Identifiable, Sendable {
    case flat2D
    case scene3D

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .flat2D: "2D"
        case .scene3D: "3D"
        }
    }

    public var systemImage: String {
        switch self {
        case .flat2D: "square.2.layers.3d.top.filled"
        case .scene3D: "cube"
        }
    }

    public var help: String {
        switch self {
        case .flat2D: "Flat canvas with pan and zoom"
        case .scene3D: "Orbitable SceneKit sphere"
        }
    }
}
