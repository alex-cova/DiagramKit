import Foundation

/// Drag interaction mode for `SceneKitDiagramView`.
public nonisolated enum SceneKitNavigationMode: String, CaseIterable, Identifiable, Sendable {
    case orbit
    case pan

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .orbit: "Orbit"
        case .pan: "Pan"
        }
    }

    public var systemImage: String {
        switch self {
        case .orbit: "arrow.triangle.2.circlepath"
        case .pan: "hand.draw"
        }
    }

    public var dragHint: String {
        switch self {
        case .orbit: "Drag to orbit"
        case .pan: "Drag to move, scroll or pinch to zoom"
        }
    }

    public var help: String {
        switch self {
        case .orbit: "Drag to orbit the 3D view"
        case .pan: "Drag to move the 3D view; scroll or pinch to zoom"
        }
    }
}
