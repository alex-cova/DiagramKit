import CoreGraphics
import Foundation

/// Cached render descriptor for a node in a 3D scene graph (SceneKit Y-up).
public nonisolated struct SceneNode3D: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var position: DiagramPosition3D
    public var size: CGSize
    public var fill: CodableColor
    public var stroke: CodableColor
    public var title: String
    public var selected: Bool
    public init(
        id: UUID,
        position: DiagramPosition3D,
        size: CGSize,
        fill: CodableColor,
        stroke: CodableColor,
        title: String,
        selected: Bool
    ) {
        self.id = id
        self.position = position
        self.size = size
        self.fill = fill
        self.stroke = stroke
        self.title = title
        self.selected = selected
    }
}

/// How a 3D edge is drawn between its endpoints.
public nonisolated enum SceneEdgeRouting3D: Sendable, Equatable {
    case straight
    /// Quadratic arc; `bulge` is height as a fraction of chord length.
    case arc(bulge: Float = 0.4)
}

/// Cached render descriptor for an edge in a 3D scene graph.
public nonisolated struct SceneEdge3D: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var sourceID: UUID
    public var destinationID: UUID
    public var start: DiagramPosition3D
    public var end: DiagramPosition3D
    public var stroke: CodableColor
    public var lineWidth: CGFloat
    public var selected: Bool
    public var routing: SceneEdgeRouting3D = .straight
    public init(
        id: UUID,
        sourceID: UUID,
        destinationID: UUID,
        start: DiagramPosition3D,
        end: DiagramPosition3D,
        stroke: CodableColor,
        lineWidth: CGFloat,
        selected: Bool,
        routing: SceneEdgeRouting3D = .straight
    ) {
        self.id = id
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.start = start
        self.end = end
        self.stroke = stroke
        self.lineWidth = lineWidth
        self.selected = selected
        self.routing = routing
    }
}

/// Built 3D scene for one document fingerprint.
public nonisolated struct DiagramScene3D: Sendable, Equatable {
    public var fingerprint: UInt64
    public var nodes: [SceneNode3D]
    public var edges: [SceneEdge3D]

    public static let empty = DiagramScene3D(fingerprint: 0, nodes: [], edges: [])
    public init(
        fingerprint: UInt64,
        nodes: [SceneNode3D],
        edges: [SceneEdge3D]
    ) {
        self.fingerprint = fingerprint
        self.nodes = nodes
        self.edges = edges
    }
}

public extension EdgeHighlightResolver {
    nonisolated static func applyHighlight(
        to edge: inout SceneEdge3D,
        selection: Set<UUID>,
        theme: DiagramTheme,
        nodeIDs: Set<UUID> = []
    ) {
        let highlight = level(
            edgeID: edge.id,
            sourceID: edge.sourceID,
            destinationID: edge.destinationID,
            selection: selection,
            nodeIDs: nodeIDs
        )
        let style = appearance(level: highlight, theme: theme)
        edge.selected = isDirectlySelected(edgeID: edge.id, selection: selection)
        edge.stroke = style.stroke
        edge.lineWidth = style.lineWidth
    }
}
