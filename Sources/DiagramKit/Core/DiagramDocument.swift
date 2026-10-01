import Foundation

/// Mutation surface shared by `EditCommand` and concrete documents like `HexDiagramDocument`.
public nonisolated protocol MutableDiagramDocument {
    associatedtype Node: DiagramNode
    associatedtype Edge: DiagramEdge

    var meta: DiagramMeta { get set }
    var canvas: CanvasSettings { get set }
    var nodes: [Node] { get set }
    var edges: [Edge] { get set }

    mutating func touchModified()
}

/// Generic in-memory diagram shell. Domain documents (e.g. `HexDiagramDocument`) may mirror these fields
/// or conform to `MutableDiagramDocument` for shared edit commands.
public nonisolated struct DiagramDocument<Node: DiagramNode, Edge: DiagramEdge>: Sendable, Equatable, MutableDiagramDocument {
    public var meta: DiagramMeta
    public var canvas: CanvasSettings
    public var nodes: [Node]
    public var edges: [Edge]

    public init(
        meta: DiagramMeta = DiagramMeta(),
        canvas: CanvasSettings = CanvasSettings(),
        nodes: [Node] = [],
        edges: [Edge] = []
    ) {
        self.meta = meta
        self.canvas = canvas
        self.nodes = nodes
        self.edges = edges
    }

    public func node(id: UUID) -> Node? {
        nodes.first { $0.id == id }
    }

    public func edge(id: UUID) -> Edge? {
        edges.first { $0.id == id }
    }

    public mutating func touchModified() {
        meta.modifiedAt = .now
    }
}

