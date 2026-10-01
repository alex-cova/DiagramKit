import CoreGraphics
import Foundation
import simd

/// 3D Fruchterman–Reingold force-directed layout (fixed iterations).
///
/// Same energy model as `ForceDirectedLayout`, but displacements live in SceneKit Y-up
/// world space so the graph fills a volume rather than a flat plane.
public nonisolated struct ForceDirectedLayout3D: LayoutAlgorithm3D {
    public var iterations: Int
    public var idealEdgeLength: Float
    public var temperature: Float

    public init(iterations: Int = 80, idealEdgeLength: Float = 180, temperature: Float = 120) {
        self.iterations = iterations
        self.idealEdgeLength = idealEdgeLength
        self.temperature = temperature
    }

    public func layout(_ graph: LayoutGraph3D, options: LayoutOptions3D) -> [NodeFrame3D] {
        guard !graph.nodes.isEmpty else { return [] }
        let count = graph.nodes.count

        var indexOf: [UUID: Int] = [:]
        indexOf.reserveCapacity(count)
        for (i, node) in graph.nodes.enumerated() where indexOf[node.id] == nil {
            indexOf[node.id] = i
        }

        let n = Float(count)
        let volumeSide = max(400, cbrt(n) * idealEdgeLength)
        let radius = volumeSide * 0.35

        // Deterministic spherical seed (Fibonacci lattice) — avoids a planar start that
        // would keep the simulation stuck near y = 0.
        var positions = [SIMD3<Float>](repeating: .zero, count: count)
        let golden = Float.pi * (3 - sqrt(5))
        for i in 0..<count {
            let y = 1 - (Float(i) / max(n - 1, 1)) * 2
            let rAtY = sqrt(max(0, 1 - y * y))
            let theta = golden * Float(i)
            positions[i] = SIMD3(
                cos(theta) * rAtY * radius,
                y * radius,
                sin(theta) * rAtY * radius
            ) + options.origin.simd
        }

        let sizes = graph.nodes.map { node -> CGSize in
            node.size.width > 0 && node.size.height > 0
                ? node.size
                : CGSize(width: 120, height: 40)
        }

        var adjacency: [(Int, Int)] = []
        adjacency.reserveCapacity(graph.edges.count)
        for edge in graph.edges {
            guard let a = indexOf[edge.source], let b = indexOf[edge.destination] else { continue }
            adjacency.append((a, b))
        }

        var temp = temperature
        let k = idealEdgeLength
        var disp = [SIMD3<Float>](repeating: .zero, count: count)

        for _ in 0..<iterations {
            for i in 0..<count { disp[i] = .zero }

            // Repulsive forces
            for i in 0..<count {
                for j in (i + 1)..<count {
                    var delta = positions[i] - positions[j]
                    var dist = length(delta)
                    if dist < 0.01 {
                        // Deterministic nudge so coincident seeds still separate in 3D.
                        delta = SIMD3(1, Float(i - j), Float((i + j) % 3) - 1)
                        dist = length(delta)
                    }
                    let force = (k * k) / dist
                    let unit = delta / dist
                    disp[i] += unit * force
                    disp[j] -= unit * force
                }
            }

            // Attractive forces along edges
            for (a, b) in adjacency {
                let delta = positions[a] - positions[b]
                let dist = length(delta)
                if dist < 0.01 { continue }
                let force = (dist * dist) / k
                let unit = delta / dist
                disp[a] -= unit * force
                disp[b] += unit * force
            }

            for i in 0..<count {
                let d = disp[i]
                let len = length(d)
                if len > 0.01 {
                    let limited = min(len, temp)
                    positions[i] += (d / len) * limited
                }
            }
            temp *= 0.95
        }

        // Center the cloud on options.origin so the SceneKit orbit stays near the graph.
        var centroid = SIMD3<Float>.zero
        for p in positions { centroid += p }
        centroid /= n
        let shift = options.origin.simd - centroid

        return graph.nodes.indices.map { i in
            NodeFrame3D(
                id: graph.nodes[i].id,
                position: DiagramPosition3D(positions[i] + shift),
                size: sizes[i]
            )
        }
    }
}
