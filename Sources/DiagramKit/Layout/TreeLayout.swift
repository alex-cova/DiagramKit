import CoreGraphics
import Foundation

/// Top-down (or LTR) tidy tree from the lowest in-degree root; orphans packed with GridLayout beside the tree.
public nonisolated struct TreeLayout: LayoutAlgorithm {
    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let sizes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.frame.size) })
        let ids = Set(graph.nodes.map(\.id))

        var children: [UUID: [UUID]] = Dictionary(uniqueKeysWithValues: ids.map { ($0, []) })
        var inDegree: [UUID: Int] = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        for edge in graph.edges {
            guard ids.contains(edge.source), ids.contains(edge.destination) else { continue }
            if !children[edge.source, default: []].contains(edge.destination) {
                children[edge.source, default: []].append(edge.destination)
                inDegree[edge.destination, default: 0] += 1
            }
        }

        let root = ids.min { a, b in
            let da = inDegree[a, default: 0]
            let db = inDegree[b, default: 0]
            if da != db { return da < db }
            return uuidIsOrderedBefore(a, b)
        }!

        var placed: [UUID: CGRect] = [:]
        var nextLeafX = options.origin.x
        // Ids on the current root-to-here recursion path. A `Set<UUID>` copied (`.union([id])`)
        // at every node was O(n²) time and memory on a deep chain; mutating one shared set on the
        // way down and removing on the way back out (a manual "on-path" stack) is O(1) amortized
        // per node and identical in effect — at any point it holds exactly the current ancestry.
        var onPath: Set<UUID> = []

        func place(_ id: UUID, depth: Int) -> CGFloat {
            let size = sizes[id] ?? CGSize(width: 160, height: 100)
            // Matches the original ordering exactly: `kids` is filtered against ancestry
            // *excluding* `id` itself (only inserted afterward, for the recursive calls below) —
            // preserving the original's one-extra-level allowance for a direct self-loop.
            let kids = children[id, default: []].filter { !onPath.contains($0) && placed[$0] == nil }
            onPath.insert(id)
            defer { onPath.remove(id) }
            let y: CGFloat
            let xCenter: CGFloat
            switch options.direction {
            case .topToBottom:
                y = options.origin.y + CGFloat(depth) * (size.height + options.verticalSpacing)
                if kids.isEmpty {
                    xCenter = nextLeafX + size.width / 2
                    nextLeafX += size.width + options.horizontalSpacing
                } else {
                    let centers = kids.map { place($0, depth: depth + 1) }
                    xCenter = (centers.first! + centers.last!) / 2
                }
                placed[id] = CGRect(
                    x: xCenter - size.width / 2,
                    y: y,
                    width: size.width,
                    height: size.height
                )
                return xCenter
            case .leftToRight:
                let x = options.origin.x + CGFloat(depth) * (size.width + options.horizontalSpacing)
                if kids.isEmpty {
                    xCenter = nextLeafX + size.height / 2
                    nextLeafX += size.height + options.verticalSpacing
                } else {
                    let centers = kids.map { place($0, depth: depth + 1) }
                    xCenter = (centers.first! + centers.last!) / 2
                }
                placed[id] = CGRect(
                    x: x,
                    y: xCenter - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                return xCenter
            }
        }

        _ = place(root, depth: 0)

        let visited = Set(placed.keys)
        let orphans = graph.nodes.filter { !visited.contains($0.id) }
        if !orphans.isEmpty {
            let treeBounds = placed.values.reduce(CGRect.null) { $0.union($1) }
            let orphanOrigin: CGPoint
            switch options.direction {
            case .topToBottom:
                orphanOrigin = CGPoint(
                    x: options.origin.x,
                    y: (treeBounds.isNull ? options.origin.y : treeBounds.maxY) + options.verticalSpacing
                )
            case .leftToRight:
                orphanOrigin = CGPoint(
                    x: (treeBounds.isNull ? options.origin.x : treeBounds.maxX) + options.horizontalSpacing,
                    y: options.origin.y
                )
            }
            let orphanGraph = LayoutGraph(nodes: orphans, edges: [])
            let orphanFrames = GridLayout().layout(
                orphanGraph,
                options: LayoutOptions(
                    origin: orphanOrigin,
                    horizontalSpacing: options.horizontalSpacing,
                    verticalSpacing: options.verticalSpacing,
                    direction: options.direction
                )
            )
            for frame in orphanFrames {
                placed[frame.id] = frame.frame
            }
        }

        return graph.nodes.compactMap { node in
            guard let frame = placed[node.id] else { return nil }
            return NodeFrame(id: node.id, frame: frame)
        }
    }
    public init() {}
}
