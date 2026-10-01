import CoreGraphics
import Foundation

public nonisolated enum LayoutDirection: String, Sendable, Codable {
    case topToBottom
    case leftToRight
}

public nonisolated struct LayoutGraph: Sendable {
    public var nodes: [NodeFrame]
    public var edges: [(source: UUID, destination: UUID)]

    public init(nodes: [NodeFrame], edges: [(source: UUID, destination: UUID)] = []) {
        self.nodes = nodes
        self.edges = edges
    }
}

public nonisolated struct LayoutOptions: Sendable {
    public var origin: CGPoint
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat
    public var direction: LayoutDirection

    public init(
        origin: CGPoint = CGPoint(x: 40, y: 40),
        horizontalSpacing: CGFloat = 80,
        verticalSpacing: CGFloat = 60,
        direction: LayoutDirection = .topToBottom
    ) {
        self.origin = origin
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.direction = direction
    }
}

public nonisolated protocol LayoutAlgorithm: Sendable {
    func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame]
}

public extension LayoutAlgorithm {
    /// Incremental hook — default recomputes a full layout (Phase D overrides for large graphs).
    func layout(
        _ graph: LayoutGraph,
        changedIDs: Set<UUID>,
        prior: [NodeFrame],
        options: LayoutOptions
    ) -> [NodeFrame] {
        _ = changedIDs
        _ = prior
        return layout(graph, options: options)
    }
}
