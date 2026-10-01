import CoreGraphics
import Foundation

/// Node that can be duplicated onto the canvas with a fresh identity and frame.
public nonisolated protocol ClipboardPasteableNode: DiagramNode, Codable {
    func pasting(newID: UUID, frame: CGRect) -> Self
    var clipboardParentID: UUID? { get }
    func pasting(newID: UUID, frame: CGRect, parentID: UUID?) -> Self
}

public nonisolated extension ClipboardPasteableNode {
    var clipboardParentID: UUID? { nil }

    func pasting(newID: UUID, frame: CGRect, parentID: UUID?) -> Self {
        pasting(newID: newID, frame: frame)
    }
}

/// Edge that can be duplicated with remapped identity and endpoints.
public nonisolated protocol ClipboardPasteableEdge: DiagramEdge, Codable {
    func pasting(newID: UUID, sourceID: UUID, destinationID: UUID) -> Self
}

public nonisolated struct DiagramClipboardPayload<
    Node: ClipboardPasteableNode,
    Edge: ClipboardPasteableEdge
>: Codable, Sendable, Equatable where Node: Sendable, Edge: Sendable {
    public var nodes: [Node]
    public var edges: [Edge]
    public init(
        nodes: [Node],
        edges: [Edge]
    ) {
        self.nodes = nodes
        self.edges = edges
    }
}

public nonisolated enum DiagramClipboard {
    /// Slice selected nodes plus edges whose both endpoints are in the selection.
    public static func slice<Node: ClipboardPasteableNode, Edge: ClipboardPasteableEdge>(
        nodes: [Node],
        edges: [Edge],
        selectedIDs: Set<UUID>
    ) -> DiagramClipboardPayload<Node, Edge>? {
        let selectedNodes = nodes.filter { selectedIDs.contains($0.id) }
        guard !selectedNodes.isEmpty else { return nil }
        let nodeIDs = Set(selectedNodes.map(\.id))
        let selectedEdges = edges.filter {
            nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.destinationID)
        }
        return DiagramClipboardPayload(nodes: selectedNodes, edges: selectedEdges)
    }

    /// Duplicate payload with new UUIDs and a positional offset. Returns pasted elements and selection set.
    public static func paste<Node: ClipboardPasteableNode, Edge: ClipboardPasteableEdge>(
        payload: DiagramClipboardPayload<Node, Edge>,
        offset: CGSize
    ) -> (nodes: [Node], edges: [Edge], newSelection: Set<UUID>) {
        var idMap: [UUID: UUID] = [:]
        var newNodes: [Node] = []
        for node in payload.nodes {
            let newID = UUID()
            idMap[node.id] = newID
        }
        for node in payload.nodes {
            guard let newID = idMap[node.id] else { continue }
            let frame = node.frame.offsetBy(dx: offset.width, dy: offset.height)
            let parentID = node.clipboardParentID.flatMap { idMap[$0] }
            newNodes.append(node.pasting(newID: newID, frame: frame, parentID: parentID))
        }

        var newEdges: [Edge] = []
        var selection = Set(newNodes.map(\.id))
        for edge in payload.edges {
            guard let source = idMap[edge.sourceID], let destination = idMap[edge.destinationID] else {
                continue
            }
            let newID = UUID()
            newEdges.append(edge.pasting(newID: newID, sourceID: source, destinationID: destination))
            selection.insert(newID)
        }
        return (newNodes, newEdges, selection)
    }
}
