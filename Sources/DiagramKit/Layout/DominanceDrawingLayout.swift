import CoreGraphics
import Foundation

/// Dominance drawing for DAGs: if there is a directed path `u →* v`, then both coordinates
/// of `u` are weakly less than those of `v` (upward-rightward).
///
/// - `y` = longest-path distance from sources (layer)
/// - `x` = number of ancestors reachable into the node (including itself)
///
/// Cycles are broken by preferring a BFS spanning forest (back/cross edges ignored for ranking).
public nonisolated struct DominanceDrawingLayout: LayoutAlgorithm {
    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let n = graph.nodes.count

        var indexOf: [UUID: Int] = [:]
        indexOf.reserveCapacity(n)
        for (i, node) in graph.nodes.enumerated() where indexOf[node.id] == nil {
            indexOf[node.id] = i
        }

        var children: [[Int]] = Array(repeating: [], count: n)
        var parents: [[Int]] = Array(repeating: [], count: n)
        var inDegree = [Int](repeating: 0, count: n)
        var seenEdges = Set<Int64>()
        for edge in graph.edges {
            guard let s = indexOf[edge.source], let d = indexOf[edge.destination], s != d else { continue }
            let key = Int64(s) << 32 | Int64(d)
            guard seenEdges.insert(key).inserted else { continue }
            children[s].append(d)
            parents[d].append(s)
            inDegree[d] += 1
        }

        // Spanning forest: BFS from low in-degree candidates; only tree edges contribute to ranks.
        let candidates = Array(0..<n).sorted { a, b in
            if inDegree[a] != inDegree[b] { return inDegree[a] < inDegree[b] }
            return uuidIsOrderedBefore(graph.nodes[a].id, graph.nodes[b].id)
        }

        var depth = [Int](repeating: -1, count: n)
        var treeChildren: [[Int]] = Array(repeating: [], count: n)
        var treeParents = [Int](repeating: -1, count: n)
        var bfsOrder: [Int] = []
        bfsOrder.reserveCapacity(n)

        for c in candidates where depth[c] == -1 {
            depth[c] = 0
            bfsOrder.append(c)
            var head = bfsOrder.count - 1
            while head < bfsOrder.count {
                let v = bfsOrder[head]
                head += 1
                let kids = children[v].sorted { a, b in
                    uuidIsOrderedBefore(graph.nodes[a].id, graph.nodes[b].id)
                }
                for w in kids where depth[w] == -1 {
                    depth[w] = depth[v] + 1
                    treeParents[w] = v
                    treeChildren[v].append(w)
                    bfsOrder.append(w)
                }
            }
        }
        for i in 0..<n where depth[i] == -1 {
            depth[i] = 0
            bfsOrder.append(i)
        }

        // Longest-path rank along the spanning forest (dominance y).
        var rank = depth
        for v in bfsOrder {
            let p = treeParents[v]
            if p >= 0 {
                rank[v] = max(rank[v], rank[p] + 1)
            }
        }
        // Respect non-tree forward edges; cap growth so cycles cannot inflate ranks unboundedly.
        var changed = true
        var guardRails = 0
        while changed, guardRails < n {
            changed = false
            guardRails += 1
            for edge in graph.edges {
                guard let s = indexOf[edge.source], let d = indexOf[edge.destination] else { continue }
                let next = rank[s] + 1
                if next < n, rank[d] < next {
                    rank[d] = next
                    changed = true
                }
            }
        }

        // Ancestor counts on the spanning forest (dominance x): subtree-upward inclusive size.
        var ancestorCount = [Int](repeating: 1, count: n)
        for v in bfsOrder {
            let p = treeParents[v]
            if p >= 0 {
                ancestorCount[v] = ancestorCount[p] + 1
            }
        }
        // Fold in additional parents from the original DAG so shared deps get larger x.
        for v in bfsOrder {
            for p in parents[v] where p != treeParents[v] {
                ancestorCount[v] = max(ancestorCount[v], ancestorCount[p] + 1)
            }
        }

        // Stable secondary key so equal (x,y) don't stack: topological slot in bfsOrder.
        var slot = [Int](repeating: 0, count: n)
        for (i, v) in bfsOrder.enumerated() {
            slot[v] = i
        }

        return graph.nodes.enumerated().map { i, node in
            let size = node.frame.size.width > 0
                ? node.frame.size
                : CGSize(width: 160, height: 40)
            // Spread ancestor ranks across a readable band; slot epsilon separates ties.
            let xUnit = options.horizontalSpacing + size.width
            let yUnit = options.verticalSpacing + size.height
            let anc = ancestorCount[i]
            let r = rank[i]
            let epsilon = CGFloat(slot[i]) * 0.15

            let frame: CGRect
            switch options.direction {
            case .topToBottom:
                let cx = options.origin.x + CGFloat(anc - 1) * xUnit + epsilon + size.width / 2
                let cy = options.origin.y + CGFloat(r) * yUnit + size.height / 2
                frame = CGRect(
                    x: cx - size.width / 2,
                    y: cy - size.height / 2,
                    width: size.width,
                    height: size.height
                )
            case .leftToRight:
                let cx = options.origin.x + CGFloat(r) * xUnit + size.width / 2
                let cy = options.origin.y + CGFloat(anc - 1) * yUnit + epsilon + size.height / 2
                frame = CGRect(
                    x: cx - size.width / 2,
                    y: cy - size.height / 2,
                    width: size.width,
                    height: size.height
                )
            }
            return NodeFrame(id: node.id, frame: frame)
        }
    }
    public init() {}
}
