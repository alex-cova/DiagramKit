import CoreGraphics
import Foundation

/// Concentric rings by BFS depth from the lowest in-degree root.
public nonisolated struct RadialLayout: LayoutAlgorithm {
    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let ids = Set(graph.nodes.map(\.id))
        let sizes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.frame.size) })

        var undirected: [UUID: [UUID]] = Dictionary(uniqueKeysWithValues: ids.map { ($0, []) })
        var inDegree: [UUID: Int] = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        for edge in graph.edges {
            guard ids.contains(edge.source), ids.contains(edge.destination) else { continue }
            undirected[edge.source, default: []].append(edge.destination)
            undirected[edge.destination, default: []].append(edge.source)
            inDegree[edge.destination, default: 0] += 1
        }

        let root = ids.min { a, b in
            let da = inDegree[a, default: 0]
            let db = inDegree[b, default: 0]
            if da != db { return da < db }
            return uuidIsOrderedBefore(a, b)
        }!

        var depth: [UUID: Int] = [root: 0]
        var queue = [root]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            let d = depth[current]!
            for neighbor in undirected[current, default: []] where depth[neighbor] == nil {
                depth[neighbor] = d + 1
                queue.append(neighbor)
            }
        }
        // Hoisted out of the loop: `depth.values.max()` was O(n) and ran once per disconnected
        // node, so an all-orphan graph paid O(n²). Each orphan still lands one ring further out
        // than the last (matching the old behavior exactly: assigning a depth used to raise the
        // max, so the *next* orphan's `.max() + 1` was implicitly one more than this one's).
        var runningMaxDepth = depth.values.max() ?? 0
        for id in ids where depth[id] == nil {
            runningMaxDepth += 1
            depth[id] = runningMaxDepth
        }

        let maxDepth = depth.values.max() ?? 0
        var rings: [[UUID]] = Array(repeating: [], count: maxDepth + 1)
        for id in ids {
            rings[depth[id] ?? 0].append(id)
        }

        let maxSize = graph.nodes.map { max($0.frame.width, $0.frame.height) }.max() ?? 120
        let ringGap = max(maxSize + options.horizontalSpacing, 140)
        let center = CGPoint(
            x: options.origin.x + CGFloat(maxDepth) * ringGap + maxSize,
            y: options.origin.y + CGFloat(maxDepth) * ringGap + maxSize
        )

        var result: [NodeFrame] = []
        for (ringIndex, ring) in rings.enumerated() {
            let radius = CGFloat(ringIndex) * ringGap
            if ring.isEmpty { continue }
            if ringIndex == 0, ring.count == 1, let id = ring.first {
                let size = sizes[id]!
                result.append(NodeFrame(
                    id: id,
                    frame: CGRect(
                        x: center.x - size.width / 2,
                        y: center.y - size.height / 2,
                        width: size.width,
                        height: size.height
                    )
                ))
                continue
            }
            for (index, id) in ring.enumerated() {
                let angle = CGFloat(index) / CGFloat(ring.count) * 2 * .pi - .pi / 2
                let size = sizes[id]!
                let cx = center.x + cos(angle) * radius
                let cy = center.y + sin(angle) * radius
                result.append(NodeFrame(
                    id: id,
                    frame: CGRect(
                        x: cx - size.width / 2,
                        y: cy - size.height / 2,
                        width: size.width,
                        height: size.height
                    )
                ))
            }
        }

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        return graph.nodes.compactMap { byID[$0.id] }
    }
    public init() {}
}
