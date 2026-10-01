import CoreGraphics
import Foundation

/// Cached render descriptor for a node in the scene graph.
public nonisolated struct SceneNode: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var frame: CGRect
    public var shape: DiagramShape
    public var style: DiagramShapeStyle
    public var zIndex: Int
    public var title: String
    public var compartments: [String]
    /// When true, prefer interactive SwiftUI chrome (selection handles).
    public var interactive: Bool
    public init(
        id: UUID,
        frame: CGRect,
        shape: DiagramShape,
        style: DiagramShapeStyle,
        zIndex: Int,
        title: String,
        compartments: [String],
        interactive: Bool
    ) {
        self.id = id
        self.frame = frame
        self.shape = shape
        self.style = style
        self.zIndex = zIndex
        self.title = title
        self.compartments = compartments
        self.interactive = interactive
    }
}

/// Cached render descriptor for an edge in the scene graph.
public nonisolated struct SceneEdge: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var sourceID: UUID
    public var destinationID: UUID
    public var route: EdgeRoute
    public var isDashed: Bool
    public var stroke: CodableColor
    public var lineWidth: CGFloat
    public var label: String
    public var labelPoint: CGPoint
    /// True only when the edge ID itself is selected, not when an endpoint node is.
    public var selected: Bool
    public init(
        id: UUID,
        sourceID: UUID,
        destinationID: UUID,
        route: EdgeRoute,
        isDashed: Bool,
        stroke: CodableColor,
        lineWidth: CGFloat,
        label: String,
        labelPoint: CGPoint,
        selected: Bool
    ) {
        self.id = id
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.route = route
        self.isDashed = isDashed
        self.stroke = stroke
        self.lineWidth = lineWidth
        self.label = label
        self.labelPoint = labelPoint
        self.selected = selected
    }
}

/// Built scene for one document fingerprint; supports dirty partial rebuilds.
public nonisolated struct DiagramScene: Sendable, Equatable {
    public var fingerprint: UInt64
    public var nodes: [SceneNode]
    public var edges: [SceneEdge]
    public var dirtyNodeIDs: Set<UUID>

    public static let empty = DiagramScene(fingerprint: 0, nodes: [], edges: [], dirtyNodeIDs: [])

    public func visibleNodes(in worldRect: CGRect) -> [SceneNode] {
        nodes.filter { ViewportCulling.isVisible(frame: $0.frame, in: worldRect) }
    }

    public func visibleEdges(in worldRect: CGRect) -> [SceneEdge] {
        edges.filter { ViewportCulling.isRouteVisible($0.route, in: worldRect) }
    }
    public init(
        fingerprint: UInt64,
        nodes: [SceneNode],
        edges: [SceneEdge],
        dirtyNodeIDs: Set<UUID>
    ) {
        self.fingerprint = fingerprint
        self.nodes = nodes
        self.edges = edges
        self.dirtyNodeIDs = dirtyNodeIDs
    }
}
