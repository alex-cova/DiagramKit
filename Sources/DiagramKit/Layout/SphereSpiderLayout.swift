import CoreGraphics
import Foundation
import simd

/// 3D mind-map spider: root at the origin, each subtree owns a spherical solid angle
/// (azimuth θ × polar φ) sized by the space it needs. Shells nest by depth so tree edges
/// never cross — the spherical analogue of `SpiderLayout`.
///
/// Coordinates are SceneKit Y-up:
/// `x = r * sin(φ) * cos(θ)`, `y = r * cos(φ)`, `z = r * sin(φ) * sin(θ)`.
public nonisolated struct SphereSpiderLayout: LayoutAlgorithm3D {
    /// Extra tangential padding (world units) between angular neighbours on a shell.
    public var tangentialPadding: Float = 28
    /// Non-root subtrees never claim more than this azimuth span.
    public var maxSubtreeAzimuth: Float = .pi
    /// Non-root subtrees never claim more than this polar span.
    public var maxSubtreePolar: Float = .pi / 2
    /// Default node size when the input frame is empty.
    public var defaultSize: CGSize = CGSize(width: 120, height: 40)

    public func layout(_ graph: LayoutGraph3D, options: LayoutOptions3D) -> [NodeFrame3D] {
        guard !graph.nodes.isEmpty else { return [] }
        let n = graph.nodes.count

        // MARK: Pass 0 — index, sizes, adjacency.

        var indexOf: [UUID: Int] = [:]
        indexOf.reserveCapacity(n)
        for (i, node) in graph.nodes.enumerated() where indexOf[node.id] == nil {
            indexOf[node.id] = i
        }

        var sizes = [CGSize](repeating: defaultSize, count: n)
        for (i, node) in graph.nodes.enumerated() {
            let size = node.size
            if size.width > 0, size.height > 0 {
                sizes[i] = size
            }
        }

        var children: [[Int]] = Array(repeating: [], count: n)
        var inDegree = [Int](repeating: 0, count: n)
        var seenEdges = Set<Int64>()
        for edge in graph.edges {
            guard let s = indexOf[edge.source], let d = indexOf[edge.destination], s != d else { continue }
            let key = Int64(s) << 32 | Int64(d)
            guard seenEdges.insert(key).inserted else { continue }
            children[s].append(d)
            inDegree[d] += 1
        }

        // MARK: Pass 1 — BFS spanning forest.

        let candidateOrder = Array(0..<n).sorted { a, b in
            if inDegree[a] != inDegree[b] { return inDegree[a] < inDegree[b] }
            let idA = graph.nodes[a].id
            let idB = graph.nodes[b].id
            if idA != idB { return uuidIsOrderedBefore(idA, idB) }
            return a < b
        }

        var depth = [Int](repeating: -1, count: n)
        var parent = [Int](repeating: -1, count: n)
        var bfsOrder: [Int] = []
        bfsOrder.reserveCapacity(n)
        var componentRanges: [(root: Int, range: Range<Int>)] = []

        for c in candidateOrder where depth[c] == -1 {
            let start = bfsOrder.count
            depth[c] = 0
            bfsOrder.append(c)
            var head = start
            while head < bfsOrder.count {
                let v = bfsOrder[head]
                head += 1
                for w in children[v] where depth[w] == -1 {
                    depth[w] = depth[v] + 1
                    parent[w] = v
                    bfsOrder.append(w)
                }
            }
            componentRanges.append((root: c, range: start..<bfsOrder.count))
        }

        // Isolated nodes only — pack on a flat ring in the XZ plane.
        if componentRanges.allSatisfy({ $0.range.count == 1 }) {
            return packIsolates(graph: graph, sizes: sizes, options: options)
        }

        // MARK: Pass 2 — subtree weights (arc demand).

        var weight = [Float](repeating: 0, count: n)
        for v in bfsOrder.reversed() {
            let slot = Float(sizes[v].width) + tangentialPadding
            var childSum: Float = 0
            for c in children[v] where parent[c] == v {
                childSum += weight[c]
            }
            weight[v] = max(slot, childSum)
        }

        // MARK: Pass 3 — azimuth (θ) and polar (φ) wedges, top-down.

        var thetaStart = [Float](repeating: 0, count: n)
        var thetaEnd = [Float](repeating: 0, count: n)
        var phiStart = [Float](repeating: 0, count: n)
        var phiEnd = [Float](repeating: 0, count: n)
        var theta = [Float](repeating: 0, count: n)
        var phi = [Float](repeating: 0, count: n)

        for (root, range) in componentRanges {
            thetaStart[root] = -.pi
            thetaEnd[root] = .pi
            // Hemisphere facing the default camera (φ from 0 at +Y toward the equator).
            phiStart[root] = 0.15
            phiEnd[root] = .pi / 2 + 0.35

            for idx in range {
                let v = bfsOrder[idx]
                var t0 = thetaStart[v]
                var t1 = thetaEnd[v]
                var p0 = phiStart[v]
                var p1 = phiEnd[v]

                if parent[v] != -1 {
                    if t1 - t0 > maxSubtreeAzimuth {
                        let mid = (t0 + t1) / 2
                        t0 = mid - maxSubtreeAzimuth / 2
                        t1 = mid + maxSubtreeAzimuth / 2
                        thetaStart[v] = t0
                        thetaEnd[v] = t1
                    }
                    if p1 - p0 > maxSubtreePolar {
                        let mid = (p0 + p1) / 2
                        p0 = mid - maxSubtreePolar / 2
                        p1 = mid + maxSubtreePolar / 2
                        phiStart[v] = p0
                        phiEnd[v] = p1
                    }
                }

                theta[v] = (t0 + t1) / 2
                phi[v] = (p0 + p1) / 2

                let kids = children[v].filter { parent[$0] == v }
                guard !kids.isEmpty else { continue }
                let total = kids.reduce(Float(0)) { $0 + weight[$1] }
                let tSpan = t1 - t0
                let pSpan = p1 - p0
                var tCursor = t0
                // Nested rows of polar bands keep siblings from stacking on one latitude.
                let rowCount = max(1, Int(ceil(sqrt(Double(kids.count)))))
                let colCount = max(1, Int(ceil(Double(kids.count) / Double(rowCount))))
                let rowHeight = pSpan / Float(rowCount)
                let colWidth = tSpan / Float(colCount)

                for (i, k) in kids.enumerated() {
                    let row = i / colCount
                    let col = i % colCount
                    let share = total > 0 ? tSpan * weight[k] / total : colWidth
                    // Prefer weight-proportional azimuth within the parent's θ span,
                    // falling back to a grid cell when many siblings share one parent.
                    if kids.count <= 6 {
                        thetaStart[k] = tCursor
                        thetaEnd[k] = tCursor + share
                        tCursor += share
                        phiStart[k] = p0
                        phiEnd[k] = p1
                    } else {
                        thetaStart[k] = t0 + Float(col) * colWidth
                        thetaEnd[k] = thetaStart[k] + colWidth
                        phiStart[k] = p0 + Float(row) * rowHeight
                        phiEnd[k] = phiStart[k] + rowHeight
                    }
                }
            }
        }

        // MARK: Pass 4 — radius per depth, per component.

        struct ComponentResult {
            let root: Int
            let nodeCount: Int
            var localPositions: [Int: SIMD3<Float>]
            var minX: Float
            var maxX: Float
        }
        var componentResults: [ComponentResult] = []
        componentResults.reserveCapacity(componentRanges.count)

        for (root, range) in componentRanges {
            var maxDepthLocal = 0
            for idx in range { maxDepthLocal = max(maxDepthLocal, depth[bfsOrder[idx]]) }

            var radius = [Float](repeating: 0, count: maxDepthLocal + 1)
            if maxDepthLocal >= 1 {
                for d in 1...maxDepthLocal {
                    var r = radius[d - 1] + options.radialSpacing
                    // Clear parent shell by half-extents of nodes on this ring.
                    for idx in range where depth[bfsOrder[idx]] == d {
                        let v = bfsOrder[idx]
                        let extent = Float(max(sizes[v].width, sizes[v].height)) / 2 + tangentialPadding
                        r = max(r, radius[d - 1] + extent + options.radialSpacing * 0.5)
                    }
                    radius[d] = r
                }
            }

            var localPositions: [Int: SIMD3<Float>] = [:]
            var minX: Float = .greatestFiniteMagnitude
            var maxX: Float = -.greatestFiniteMagnitude
            for idx in range {
                let v = bfsOrder[idx]
                let r = radius[depth[v]]
                let position: SIMD3<Float>
                if depth[v] == 0 {
                    position = .zero
                } else {
                    let sφ = sin(phi[v])
                    let cφ = cos(phi[v])
                    position = SIMD3(
                        r * sφ * cos(theta[v]),
                        r * cφ,
                        r * sφ * sin(theta[v])
                    )
                }
                localPositions[v] = position
                minX = min(minX, position.x)
                maxX = max(maxX, position.x)
            }
            componentResults.append(
                ComponentResult(root: root, nodeCount: range.count, localPositions: localPositions, minX: minX, maxX: maxX)
            )
        }

        componentResults.sort { a, b in
            if a.nodeCount != b.nodeCount { return a.nodeCount > b.nodeCount }
            let idA = graph.nodes[a.root].id
            let idB = graph.nodes[b.root].id
            if idA != idB { return uuidIsOrderedBefore(idA, idB) }
            return a.root < b.root
        }

        // MARK: Pass 5 — place components; primary at options.origin.

        var placed: [Int: SIMD3<Float>] = [:]
        let origin = options.origin.simd
        guard let primary = componentResults.first else { return [] }
        for (v, pos) in primary.localPositions {
            placed[v] = pos + origin
        }

        var cursorX = (primary.maxX.isFinite ? primary.maxX : 0) + options.componentSpacing
        for component in componentResults.dropFirst() {
            let shift = SIMD3<Float>(cursorX - (component.minX.isFinite ? component.minX : 0), 0, 0) + origin
            for (v, pos) in component.localPositions {
                placed[v] = pos + shift
            }
            let width = (component.maxX.isFinite && component.minX.isFinite)
                ? component.maxX - component.minX
                : 0
            cursorX += width + options.componentSpacing
        }

        return graph.nodes.indices.compactMap { i in
            guard let position = placed[i] else { return nil }
            return NodeFrame3D(id: graph.nodes[i].id, position: position, size: sizes[i])
        }
    }

    private func packIsolates(
        graph: LayoutGraph3D,
        sizes: [CGSize],
        options: LayoutOptions3D
    ) -> [NodeFrame3D] {
        let n = graph.nodes.count
        let cols = max(1, Int(ceil(sqrt(Double(n)))))
        let origin = options.origin.simd
        return graph.nodes.enumerated().map { i, node in
            let col = i % cols
            let row = i / cols
            let position = origin + SIMD3(
                Float(col) * options.componentSpacing * 0.55,
                0,
                Float(row) * options.componentSpacing * 0.55
            )
            let size = sizes[i].width > 0 ? sizes[i] : defaultSize
            return NodeFrame3D(id: node.id, position: position, size: size)
        }
    }
    public init(
        tangentialPadding: Float = 28,
        maxSubtreeAzimuth: Float = .pi,
        maxSubtreePolar: Float = .pi / 2,
        defaultSize: CGSize = CGSize(width: 120, height: 40)
    ) {
        self.tangentialPadding = tangentialPadding
        self.maxSubtreeAzimuth = maxSubtreeAzimuth
        self.maxSubtreePolar = maxSubtreePolar
        self.defaultSize = defaultSize
    }
}
