import CoreGraphics
import Foundation

/// Parent/child helpers for diagram nodes that expose `parentID`.
public nonisolated enum ContainerHierarchy {
    /// All descendant IDs of `rootID` (not including root), walking `parentID` links.
    public static func descendantIDs<Node: DiagramNode>(
        of rootID: UUID,
        in nodes: [Node],
        parentID: (Node) -> UUID?
    ) -> Set<UUID> {
        var childrenByParent: [UUID: [UUID]] = [:]
        for node in nodes {
            if let parent = parentID(node) {
                childrenByParent[parent, default: []].append(node.id)
            }
        }
        var result: Set<UUID> = []
        var stack = childrenByParent[rootID] ?? []
        while let next = stack.popLast() {
            guard result.insert(next).inserted else { continue }
            stack.append(contentsOf: childrenByParent[next] ?? [])
        }
        return result
    }

    /// Expand a selection of IDs so moving a container also moves its descendants.
    public static func expandMoveIDs<Node: DiagramNode>(
        _ ids: Set<UUID>,
        in nodes: [Node],
        parentID: (Node) -> UUID?,
        isContainer: (Node) -> Bool
    ) -> Set<UUID> {
        var expanded = ids
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for id in ids {
            guard let node = byID[id], isContainer(node) else { continue }
            expanded.formUnion(descendantIDs(of: id, in: nodes, parentID: parentID))
        }
        return expanded
    }

    /// Deepest container whose frame contains `point` (prefer nested containers).
    public static func containerIDContaining<Node: DiagramNode>(
        _ point: CGPoint,
        in nodes: [Node],
        isContainer: (Node) -> Bool
    ) -> UUID? {
        let containers = nodes.filter(isContainer)
        let hits = containers.filter { $0.frame.contains(point) }
        return hits.min(by: { area($0.frame) < area($1.frame) })?.id
    }

    /// Hit-test preferring non-containers (front) then smaller containers.
    public static func hitTestPreferringContent<Node: DiagramNode>(
        at point: CGPoint,
        nodes: [Node],
        isContainer: (Node) -> Bool
    ) -> UUID? {
        let contentHits = nodes.filter { !isContainer($0) && $0.frame.contains(point) }
        if let top = contentHits.last {
            return top.id
        }
        return containerIDContaining(point, in: nodes, isContainer: isContainer)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.width * rect.height
    }
}
