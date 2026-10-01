import CoreGraphics
import Foundation

/// Simple force-directed layout (Fruchterman–Reingold style, fixed iterations).
public nonisolated struct ForceDirectedLayout: LayoutAlgorithm {
    public var iterations: Int
    public var idealEdgeLength: CGFloat
    public var temperature: CGFloat

    public init(iterations: Int = 80, idealEdgeLength: CGFloat = 180, temperature: CGFloat = 120) {
        self.iterations = iterations
        self.idealEdgeLength = idealEdgeLength
        self.temperature = temperature
    }

    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let count = graph.nodes.count

        // Dense index arrays instead of `[UUID: CGPoint]` dictionaries — at n=1000 the original's
        // per-iteration dictionary allocation plus ~6 UUID-hashed lookups per repulsion pair added
        // up to hundreds of millions of hash operations. `indexOf` is a first-wins map (mirrors
        // `SpiderLayout`), so a duplicate node ID can't trap a `Dictionary(uniqueKeysWithValues:)`.
        var indexOf: [UUID: Int] = [:]
        indexOf.reserveCapacity(count)
        for (i, node) in graph.nodes.enumerated() where indexOf[node.id] == nil {
            indexOf[node.id] = i
        }

        let n = CGFloat(count)
        let areaSide = max(400, sqrt(n) * idealEdgeLength)
        var positions = [CGPoint](repeating: .zero, count: count)
        for i in 0..<count {
            let angle = CGFloat(i) / n * 2 * .pi
            let radius = areaSide * 0.25
            positions[i] = CGPoint(
                x: options.origin.x + areaSide / 2 + cos(angle) * radius,
                y: options.origin.y + areaSide / 2 + sin(angle) * radius
            )
        }
        let sizes = graph.nodes.map(\.frame.size)

        // Same edges as the original (including any duplicates or self-loops — those already
        // become no-ops below via the `dist < 0.01` guards), just resolved to array indices once
        // instead of a dictionary-presence check per edge on every access.
        var adjacency: [(Int, Int)] = []
        adjacency.reserveCapacity(graph.edges.count)
        for edge in graph.edges {
            guard let a = indexOf[edge.source], let b = indexOf[edge.destination] else { continue }
            adjacency.append((a, b))
        }

        var temp = temperature
        let k = idealEdgeLength
        var disp = [CGPoint](repeating: .zero, count: count)

        for _ in 0..<iterations {
            for i in 0..<count { disp[i] = .zero }

            // Repulsive forces
            for i in 0..<count {
                for j in (i + 1)..<count {
                    let pa = positions[i]
                    let pb = positions[j]
                    var delta = CGPoint(x: pa.x - pb.x, y: pa.y - pb.y)
                    var dist = hypot(delta.x, delta.y)
                    if dist < 0.01 {
                        delta = CGPoint(x: 1, y: CGFloat(i - j))
                        dist = hypot(delta.x, delta.y)
                    }
                    let force = (k * k) / dist
                    let ux = delta.x / dist
                    let uy = delta.y / dist
                    disp[i].x += ux * force
                    disp[i].y += uy * force
                    disp[j].x -= ux * force
                    disp[j].y -= uy * force
                }
            }

            // Attractive forces along edges
            for (a, b) in adjacency {
                let pa = positions[a]
                let pb = positions[b]
                let delta = CGPoint(x: pa.x - pb.x, y: pa.y - pb.y)
                let dist = hypot(delta.x, delta.y)
                if dist < 0.01 { continue }
                let force = (dist * dist) / k
                let ux = delta.x / dist
                let uy = delta.y / dist
                disp[a].x -= ux * force
                disp[a].y -= uy * force
                disp[b].x += ux * force
                disp[b].y += uy * force
            }

            for i in 0..<count {
                let d = disp[i]
                let len = hypot(d.x, d.y)
                if len > 0.01 {
                    let limited = min(len, temp)
                    positions[i].x += d.x / len * limited
                    positions[i].y += d.y / len * limited
                }
            }
            temp *= 0.95
        }

        // Normalize to origin
        let minX = positions.map(\.x).min() ?? 0
        let minY = positions.map(\.y).min() ?? 0
        return graph.nodes.indices.map { i in
            let node = graph.nodes[i]
            let size = sizes[i]
            let center = positions[i]
            let origin = CGPoint(
                x: center.x - minX + options.origin.x - size.width / 2,
                y: center.y - minY + options.origin.y - size.height / 2
            )
            return NodeFrame(id: node.id, frame: CGRect(origin: origin, size: size))
        }
    }
}
