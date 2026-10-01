import CoreGraphics
import Foundation

/// Arc diagram: nodes ordered along a baseline; good for scanning adjacency as arcs/chords.
///
/// Ordering is a BFS spanning order from lowest in-degree roots, then a few barycenter
/// sweeps to reduce edge length (proxy for arc crossings). Nodes sit on one row
/// (or one column when `direction == .leftToRight` treats the baseline as vertical).
public nonisolated struct ArcDiagramLayout: LayoutAlgorithm {
    /// Extra barycenter sweeps after the initial BFS order (0…4 is typical).
    public var refinementPasses: Int = 3

    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let n = graph.nodes.count

        var indexOf: [UUID: Int] = [:]
        indexOf.reserveCapacity(n)
        for (i, node) in graph.nodes.enumerated() where indexOf[node.id] == nil {
            indexOf[node.id] = i
        }

        var neighbors: [[Int]] = Array(repeating: [], count: n)
        var inDegree = [Int](repeating: 0, count: n)
        var seenEdges = Set<Int64>()
        for edge in graph.edges {
            guard let s = indexOf[edge.source], let d = indexOf[edge.destination], s != d else { continue }
            let key = Int64(s) << 32 | Int64(d)
            guard seenEdges.insert(key).inserted else { continue }
            neighbors[s].append(d)
            neighbors[d].append(s)
            inDegree[d] += 1
        }

        // Deterministic root order: low in-degree first, then UUID.
        let roots = Array(0..<n).sorted { a, b in
            if inDegree[a] != inDegree[b] { return inDegree[a] < inDegree[b] }
            return uuidIsOrderedBefore(graph.nodes[a].id, graph.nodes[b].id)
        }

        // BFS forest order becomes the initial linear arrangement.
        var order: [Int] = []
        order.reserveCapacity(n)
        var visited = [Bool](repeating: false, count: n)
        for root in roots where !visited[root] {
            visited[root] = true
            order.append(root)
            var head = order.count - 1
            while head < order.count {
                let v = order[head]
                head += 1
                let sortedNeighbors = neighbors[v].sorted { a, b in
                    uuidIsOrderedBefore(graph.nodes[a].id, graph.nodes[b].id)
                }
                for w in sortedNeighbors where !visited[w] {
                    visited[w] = true
                    order.append(w)
                }
            }
        }
        for i in 0..<n where !visited[i] {
            order.append(i)
        }

        // Barycenter refinement: place each node at the median of its neighbors' positions.
        if refinementPasses > 0, n > 2 {
            for pass in 0..<refinementPasses {
                var position = [Int](repeating: 0, count: n)
                for (slot, nodeIndex) in order.enumerated() {
                    position[nodeIndex] = slot
                }
                var scores = [(index: Int, score: Double)]()
                scores.reserveCapacity(n)
                for i in 0..<n {
                    let nbrs = neighbors[i]
                    if nbrs.isEmpty {
                        scores.append((i, Double(position[i])))
                    } else {
                        let mean = Double(nbrs.reduce(0) { $0 + position[$1] }) / Double(nbrs.count)
                        // Tiny UUID bias keeps ties deterministic across passes.
                        let bias = Double(pass) * 1e-9 + Double(i) * 1e-12
                        scores.append((i, mean + bias))
                    }
                }
                scores.sort { a, b in
                    if a.score != b.score { return a.score < b.score }
                    return uuidIsOrderedBefore(graph.nodes[a.index].id, graph.nodes[b.index].id)
                }
                order = scores.map(\.index)
            }
        }

        return placeOnBaseline(order: order, graph: graph, options: options)
    }

    private func placeOnBaseline(
        order: [Int],
        graph: LayoutGraph,
        options: LayoutOptions
    ) -> [NodeFrame] {
        var cursor = options.origin
        var frames = [NodeFrame](repeating: NodeFrame(id: graph.nodes[0].id, frame: .zero), count: order.count)

        for (slot, nodeIndex) in order.enumerated() {
            let node = graph.nodes[nodeIndex]
            let size = node.frame.size.width > 0
                ? node.frame.size
                : CGSize(width: 160, height: 40)

            let frame: CGRect
            switch options.direction {
            case .topToBottom:
                // Horizontal baseline (classic arc diagram); nodes share one row.
                frame = CGRect(
                    x: cursor.x,
                    y: options.origin.y,
                    width: size.width,
                    height: size.height
                )
                cursor.x += size.width + options.horizontalSpacing
            case .leftToRight:
                // Vertical baseline.
                frame = CGRect(
                    x: options.origin.x,
                    y: cursor.y,
                    width: size.width,
                    height: size.height
                )
                cursor.y += size.height + options.verticalSpacing
            }
            frames[slot] = NodeFrame(id: node.id, frame: frame)
        }

        // Preserve input-id pairing for callers that zip by original order.
        let byID = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })
        return graph.nodes.map { byID[$0.id] ?? NodeFrame(id: $0.id, frame: $0.frame) }
    }
    public init(refinementPasses: Int = 3) {
        self.refinementPasses = refinementPasses
    }
}
