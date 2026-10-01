import CoreGraphics
import Foundation

public nonisolated struct NodeFrame: Sendable, Equatable {
    public var id: UUID
    public var frame: CGRect
    public init(
        id: UUID,
        frame: CGRect
    ) {
        self.id = id
        self.frame = frame
    }
}

/// Domain-agnostic geometry/document shell mutations. Domain commands (class text, relationship kind) live in features.
public nonisolated enum EditCommand<Document: MutableDiagramDocument>: Sendable, Equatable
where Document: Sendable & Equatable, Document.Node: Sendable, Document.Edge: Sendable {
    case addNode(Document.Node)
    case addEdge(Document.Edge)
    case deleteElements(nodeIDs: Set<UUID>, edgeIDs: Set<UUID>)
    case bringNodesToFront(nodeIDs: Set<UUID>)
    case sendNodesToBack(nodeIDs: Set<UUID>)
    /// Expand container IDs with `ContainerHierarchy.expandMoveIDs` before applying when parenting is used.
    case moveNodes(ids: Set<UUID>, delta: CGSize)
    case setNodeFrames([NodeFrame])
    case resizeNode(id: UUID, frame: CGRect)
    case setCanvasSettings(CanvasSettings)
    case setMetaTitle(String)
    case replaceDocument(Document)

    /// Node IDs whose geometry changed (for dirty scene rebuilds).
    public var affectedNodeIDs: Set<UUID> {
        switch self {
        case .addNode(let node):
            return [node.id]
        case .addEdge:
            return []
        case .deleteElements(let nodeIDs, _):
            return nodeIDs
        case .bringNodesToFront, .sendNodesToBack:
            return []
        case .moveNodes(let ids, _):
            return ids
        case .setNodeFrames(let frames):
            return Set(frames.map(\.id))
        case .resizeNode(let id, _):
            return [id]
        case .setCanvasSettings, .setMetaTitle:
            return []
        case .replaceDocument:
            return [] // signal full rebuild via empty + flag
        }
    }

    public var requiresFullGeometryRebuild: Bool {
        switch self {
        case .replaceDocument, .setCanvasSettings, .deleteElements, .addEdge, .addNode:
            return true
        default:
            return false
        }
    }

    /// Whether this command can leave `selection` referencing a node/edge that no longer exists.
    /// Frame/style edits never remove elements, so `pruneSelection()` — two full `Set` builds plus
    /// an `@Observable` write — is dead work on every drag/resize event; only gate it on for the
    /// two commands that actually remove or replace document content.
    public var canOrphanSelection: Bool {
        switch self {
        case .deleteElements, .replaceDocument:
            return true
        default:
            return false
        }
    }

    public func apply(to document: inout Document) {
        switch self {
        case .addNode(let node):
            document.nodes.append(node)
        case .addEdge(let edge):
            document.edges.append(edge)
        case .deleteElements(let nodeIDs, let edgeIDs):
            document.nodes.removeAll { nodeIDs.contains($0.id) }
            document.edges.removeAll { edge in
                edgeIDs.contains(edge.id)
                    || nodeIDs.contains(edge.sourceID)
                    || nodeIDs.contains(edge.destinationID)
            }
        case .bringNodesToFront(let nodeIDs):
            reorderNodes(&document.nodes, ids: nodeIDs, toFront: true)
        case .sendNodesToBack(let nodeIDs):
            reorderNodes(&document.nodes, ids: nodeIDs, toFront: false)
        case .moveNodes(let ids, let delta):
            for index in document.nodes.indices where ids.contains(document.nodes[index].id) {
                var frame = document.nodes[index].frame
                frame.origin.x += delta.width
                frame.origin.y += delta.height
                document.nodes[index].frame = frame
            }
        case .setNodeFrames(let frames):
            let map = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.frame) })
            for index in document.nodes.indices {
                if let frame = map[document.nodes[index].id] {
                    document.nodes[index].frame = frame
                }
            }
        case .resizeNode(let id, let frame):
            guard let index = document.nodes.firstIndex(where: { $0.id == id }) else { return }
            let size = CanvasEngine.clampMinSize(frame.size)
            document.nodes[index].frame = CGRect(origin: frame.origin, size: size)
        case .setCanvasSettings(let settings):
            document.canvas = settings
        case .setMetaTitle(let title):
            document.meta.title = title
        case .replaceDocument(let next):
            document = next
        }
        document.touchModified()
    }

    public func inverse(before document: Document) -> EditCommand<Document>? {
        switch self {
        case .addNode(let node):
            return .deleteElements(nodeIDs: [node.id], edgeIDs: [])
        case .addEdge(let edge):
            return .deleteElements(nodeIDs: [], edgeIDs: [edge.id])
        case .deleteElements:
            return .replaceDocument(document)
        case .bringNodesToFront, .sendNodesToBack:
            return .replaceDocument(document)
        case .moveNodes(let ids, let delta):
            return .moveNodes(ids: ids, delta: CGSize(width: -delta.width, height: -delta.height))
        case .setNodeFrames(let frames):
            let previous = frames.compactMap { item -> NodeFrame? in
                guard let node = document.nodes.first(where: { $0.id == item.id }) else { return nil }
                return NodeFrame(id: item.id, frame: node.frame)
            }
            return .setNodeFrames(previous)
        case .resizeNode(let id, _):
            guard let node = document.nodes.first(where: { $0.id == id }) else { return nil }
            return .resizeNode(id: id, frame: node.frame)
        case .setCanvasSettings:
            return .setCanvasSettings(document.canvas)
        case .setMetaTitle:
            return .setMetaTitle(document.meta.title)
        case .replaceDocument:
            return .replaceDocument(document)
        }
    }

    private func reorderNodes(_ nodes: inout [Document.Node], ids: Set<UUID>, toFront: Bool) {
        let moving = nodes.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        let staying = nodes.filter { !ids.contains($0.id) }
        nodes = toFront ? staying + moving : moving + staying
    }
}
