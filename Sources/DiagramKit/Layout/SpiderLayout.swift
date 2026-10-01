import CoreGraphics
import Foundation

/// Mind-map spider: root at centre, each subtree owns an angular wedge sized by the
/// tangential space it actually needs. Wedges nest recursively, so tree edges never cross —
/// unlike `RadialLayout`, which assigns angle by index within a ring globally and lets
/// siblings scatter around the whole circle.
///
/// Runs as six linear passes over array indices (no recursion, no per-node `Set` allocation),
/// so a several-thousand-node graph lays out in well under a millisecond on the main actor.
public nonisolated struct SpiderLayout: LayoutAlgorithm {
    /// Pixel gap between angular neighbours on the same ring.
    public var tangentialPadding: CGFloat = 24
    /// A non-root subtree never sweeps more than a half turn, so a parent→child edge
    /// never chords through the inner disc.
    public var maxSubtreeWedge: CGFloat = .pi

    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let n = graph.nodes.count

        // MARK: Pass 0 — index, sizes, adjacency.

        // First-wins: a duplicate node ID must not trap on `Dictionary(uniqueKeysWithValues:)`
        // (as TreeLayout.swift and RadialLayout.swift do today). The duplicate's own array
        // slot simply becomes its own unconnected singleton below.
        var indexOf: [UUID: Int] = [:]
        indexOf.reserveCapacity(n)
        for (i, node) in graph.nodes.enumerated() where indexOf[node.id] == nil {
            indexOf[node.id] = i
        }

        var sizes = [CGSize](repeating: CGSize(width: 160, height: 100), count: n)
        for (i, node) in graph.nodes.enumerated() {
            let size = node.frame.size
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

        // MARK: Pass 1 — BFS spanning forest, deterministic root order.

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

        // No usable edges at all: every "component" is a lone node. Match GridLayout exactly,
        // the same shortcut TreeLayout effectively takes when everything is an orphan.
        if componentRanges.allSatisfy({ $0.range.count == 1 }) {
            return GridLayout().layout(graph, options: options)
        }

        // MARK: Pass 2 — subtree weights, bottom-up. Measured in points of required arc.

        var weight = [CGFloat](repeating: 0, count: n)
        for v in bfsOrder.reversed() {
            let slot = sizes[v].width + tangentialPadding
            var childSum: CGFloat = 0
            for c in children[v] where parent[c] == v {
                childSum += weight[c]
            }
            weight[v] = max(slot, childSum)
        }

        // MARK: Pass 3 — angles, top-down per component.

        var wedgeStart = [CGFloat](repeating: 0, count: n)
        var wedgeEnd = [CGFloat](repeating: 0, count: n)
        var theta = [CGFloat](repeating: 0, count: n)
        let startAngle: CGFloat = options.direction == .leftToRight ? 0 : .pi / 2

        for (root, range) in componentRanges {
            wedgeStart[root] = startAngle - .pi
            wedgeEnd[root] = startAngle + .pi

            for idx in range {
                let v = bfsOrder[idx]
                var a = wedgeStart[v]
                var b = wedgeEnd[v]
                if parent[v] != -1, b - a > maxSubtreeWedge {
                    let mid = (a + b) / 2
                    a = mid - maxSubtreeWedge / 2
                    b = mid + maxSubtreeWedge / 2
                    wedgeStart[v] = a
                    wedgeEnd[v] = b
                }
                theta[v] = (a + b) / 2

                let kids = children[v].filter { parent[$0] == v }
                guard !kids.isEmpty else { continue }
                let total = kids.reduce(CGFloat(0)) { $0 + weight[$1] }
                let span = b - a
                var cursor = a
                for k in kids {
                    let share = total > 0 ? span * weight[k] / total : span / CGFloat(kids.count)
                    wedgeStart[k] = cursor
                    wedgeEnd[k] = cursor + share
                    cursor += share
                }
            }
        }

        // MARK: Pass 4 + 5 — radius per depth, then Cartesian, per component.
        //
        // Doing this per component (rather than one global radius-per-depth array) is what
        // makes each disconnected piece its own self-contained spider: SwiftMap's View
        // Builders mode genuinely produces several disconnected `.renders` trees, and each
        // gets a full 2π sweep of its own instead of sharing rings with unrelated trees.

        struct ComponentResult {
            let root: Int
            let nodeCount: Int
            var localFrames: [Int: CGRect]
            var bounds: CGRect
        }
        var componentResults: [ComponentResult] = []
        componentResults.reserveCapacity(componentRanges.count)

        for (root, range) in componentRanges {
            var maxDepthLocal = 0
            for idx in range { maxDepthLocal = max(maxDepthLocal, depth[bfsOrder[idx]]) }

            var levels: [[Int]] = Array(repeating: [], count: maxDepthLocal + 1)
            for idx in range {
                let v = bfsOrder[idx]
                levels[depth[v]].append(v)
            }

            // `levels[d]` is already sorted by angle: parents are visited in increasing-angle
            // order (an invariant of Pass 3), and each parent's children are appended as a
            // contiguous, increasing-angle block, so the concatenation stays sorted.
            var radius = [CGFloat](repeating: 0, count: maxDepthLocal + 1)
            if maxDepthLocal >= 1 {
                for d in 1...maxDepthLocal {
                    let ring = levels[d]
                    var r = radius[d - 1]

                    // (a) radial: clear the parent ring, pairwise parent -> child.
                    for v in ring {
                        let p = parent[v]
                        guard p != -1 else { continue }
                        let rExtV = abs(sizes[v].width * cos(theta[v])) + abs(sizes[v].height * sin(theta[v]))
                        let rExtP = abs(sizes[p].width * cos(theta[v])) + abs(sizes[p].height * sin(theta[v]))
                        r = max(r, radius[d - 1] + rExtP / 2 + rExtV / 2 + options.horizontalSpacing)
                    }

                    // (b) tangential: adjacent neighbours around the ring (circular, so the
                    // wrap-around pair is checked too) must not touch, in chord form.
                    if ring.count > 1 {
                        for i in ring.indices {
                            let j = (i + 1) % ring.count
                            var dTheta = theta[ring[j]] - theta[ring[i]]
                            if j == 0 { dTheta += 2 * .pi }
                            dTheta = max(dTheta, 1e-6)
                            let tExtI = abs(sizes[ring[i]].width * sin(theta[ring[i]])) + abs(sizes[ring[i]].height * cos(theta[ring[i]]))
                            let tExtJ = abs(sizes[ring[j]].width * sin(theta[ring[j]])) + abs(sizes[ring[j]].height * cos(theta[ring[j]]))
                            let need = ((tExtI + tExtJ) / 2 + tangentialPadding) / (2 * sin(dTheta / 2))
                            r = max(r, need)
                        }
                    }
                    radius[d] = r
                }
            }

            var localFrames: [Int: CGRect] = [:]
            var bounds = CGRect.null
            for idx in range {
                let v = bfsOrder[idx]
                let r = radius[depth[v]]
                let size = sizes[v]
                let cx = r * cos(theta[v])
                let cy = r * sin(theta[v])
                let frame = CGRect(x: cx - size.width / 2, y: cy - size.height / 2, width: size.width, height: size.height)
                localFrames[v] = frame
                bounds = bounds.union(frame)
            }
            componentResults.append(ComponentResult(root: root, nodeCount: range.count, localFrames: localFrames, bounds: bounds))
        }

        // Largest (most-connected) component anchors the diagram at `options.origin`;
        // the rest pack alongside it, each still laid out as its own full spider, following
        // the same beside-the-tree convention TreeLayout uses for its orphans.
        componentResults.sort { a, b in
            if a.nodeCount != b.nodeCount { return a.nodeCount > b.nodeCount }
            let idA = graph.nodes[a.root].id
            let idB = graph.nodes[b.root].id
            if idA != idB { return uuidIsOrderedBefore(idA, idB) }
            return a.root < b.root
        }

        guard let primary = componentResults.first else { return [] }
        var placedFrame: [Int: CGRect] = [:]
        let primaryOrigin = primary.bounds.isNull ? CGPoint.zero : primary.bounds.origin
        let primaryTranslation = CGPoint(x: options.origin.x - primaryOrigin.x, y: options.origin.y - primaryOrigin.y)
        for (v, frame) in primary.localFrames {
            placedFrame[v] = frame.offsetBy(dx: primaryTranslation.x, dy: primaryTranslation.y)
        }
        let overallBounds = primary.bounds.isNull ? CGRect.null : primary.bounds.offsetBy(dx: primaryTranslation.x, dy: primaryTranslation.y)

        let rest = Array(componentResults.dropFirst())
        if !rest.isEmpty {
            // GridLayout preserves input order and never builds an id-keyed dictionary
            // internally, so pairing its output back up positionally (not by UUID) is safe
            // even if two components happen to share a root id.
            let macroNodes = rest.map { component in
                NodeFrame(
                    id: graph.nodes[component.root].id,
                    frame: CGRect(origin: .zero, size: component.bounds.isNull ? .zero : component.bounds.size)
                )
            }
            let macroOrigin: CGPoint
            switch options.direction {
            case .leftToRight:
                macroOrigin = CGPoint(
                    x: (overallBounds.isNull ? options.origin.x : overallBounds.maxX) + options.horizontalSpacing,
                    y: overallBounds.isNull ? options.origin.y : overallBounds.minY
                )
            case .topToBottom:
                macroOrigin = CGPoint(
                    x: overallBounds.isNull ? options.origin.x : overallBounds.minX,
                    y: (overallBounds.isNull ? options.origin.y : overallBounds.maxY) + options.verticalSpacing
                )
            }
            let macroGraph = LayoutGraph(nodes: macroNodes)
            let macroFrames = GridLayout().layout(
                macroGraph,
                options: LayoutOptions(
                    origin: macroOrigin,
                    horizontalSpacing: options.horizontalSpacing,
                    verticalSpacing: options.verticalSpacing,
                    direction: options.direction
                )
            )
            for (component, macroFrame) in zip(rest, macroFrames) {
                let localOrigin = component.bounds.isNull ? CGPoint.zero : component.bounds.origin
                let translation = CGPoint(x: macroFrame.frame.origin.x - localOrigin.x, y: macroFrame.frame.origin.y - localOrigin.y)
                for (v, frame) in component.localFrames {
                    placedFrame[v] = frame.offsetBy(dx: translation.x, dy: translation.y)
                }
            }
        }

        return graph.nodes.indices.compactMap { i in
            guard let frame = placedFrame[i] else { return nil }
            return NodeFrame(id: graph.nodes[i].id, frame: frame)
        }
    }
    public init(
        tangentialPadding: CGFloat = 24,
        maxSubtreeWedge: CGFloat = .pi
    ) {
        self.tangentialPadding = tangentialPadding
        self.maxSubtreeWedge = maxSubtreeWedge
    }
}
