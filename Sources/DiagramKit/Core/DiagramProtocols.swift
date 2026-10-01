import CoreGraphics
import Foundation

/// Geometry + identity contract for diagram nodes. Domain payloads (UML class boxes, etc.) conform or wrap types that do.
public nonisolated protocol DiagramNode: Identifiable, Sendable, Equatable {
    var id: UUID { get }
    var frame: CGRect { get set }
}

/// Optional parenting contract for nested containers (Diagrams cloud/architecture).
public nonisolated protocol ParentableDiagramNode: DiagramNode {
    var parentID: UUID? { get set }
    var isContainer: Bool { get }
}

/// Endpoint contract for diagram edges. Domain payloads supply routing/styling separately.
public nonisolated protocol DiagramEdge: Identifiable, Sendable, Equatable {
    var id: UUID { get }
    var sourceID: UUID { get }
    var destinationID: UUID { get }
}
