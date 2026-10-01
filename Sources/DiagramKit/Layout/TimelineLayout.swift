import CoreGraphics
import Foundation

/// Places nodes left-to-right by topological / discovery order (timeline / sequence axis).
public nonisolated struct TimelineLayout: LayoutAlgorithm {
    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let sizes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.frame.size) })
        let ids = graph.nodes.map(\.id)

        var outgoing: [UUID: [UUID]] = Dictionary(uniqueKeysWithValues: ids.map { ($0, []) })
        var indegree: [UUID: Int] = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        for edge in graph.edges {
            guard sizes[edge.source] != nil, sizes[edge.destination] != nil else { continue }
            outgoing[edge.source, default: []].append(edge.destination)
            indegree[edge.destination, default: 0] += 1
        }

        var queue = ids.filter { indegree[$0, default: 0] == 0 }
        if queue.isEmpty { queue = [ids[0]] }
        var order: [UUID] = []
        var seen: Set<UUID> = []
        while let next = queue.first {
            queue.removeFirst()
            guard seen.insert(next).inserted else { continue }
            order.append(next)
            for dest in outgoing[next, default: []] {
                indegree[dest, default: 0] -= 1
                if indegree[dest, default: 0] <= 0 {
                    queue.append(dest)
                }
            }
        }
        for id in ids where !seen.contains(id) {
            order.append(id)
        }

        var x = options.origin.x
        let y = options.origin.y
        return order.map { id in
            let size = sizes[id] ?? CGSize(width: 160, height: 80)
            let frame = NodeFrame(id: id, frame: CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + options.horizontalSpacing
            return frame
        }
    }
    public init() {}
}
