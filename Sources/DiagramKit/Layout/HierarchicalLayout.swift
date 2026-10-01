import CoreGraphics
import Foundation

/// Sugiyama-style layered layout: cycle break → longest-path layers → barycenter
/// crossing reduction → Brandes–Köpf-lite coordinate assignment.
public nonisolated struct HierarchicalLayout: LayoutAlgorithm {
    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let sizes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.frame.size) })
        let ids = graph.nodes.map(\.id)

        var outgoing: [UUID: [UUID]] = Dictionary(uniqueKeysWithValues: ids.map { ($0, []) })
        var incoming: [UUID: [UUID]] = Dictionary(uniqueKeysWithValues: ids.map { ($0, []) })
        for edge in graph.edges {
            guard sizes[edge.source] != nil, sizes[edge.destination] != nil else { continue }
            outgoing[edge.source, default: []].append(edge.destination)
            incoming[edge.destination, default: []].append(edge.source)
        }

        // 1. Cycle breaking via DFS back-edge reversal.
        reverseBackEdges(ids: ids, outgoing: &outgoing, incoming: &incoming)

        // 2. Longest-path layer assignment on the now-acyclic graph.
        var layerOf: [UUID: Int] = [:]
        var queue = ids.filter { incoming[$0, default: []].isEmpty }
        if queue.isEmpty { queue = [ids[0]] }
        for id in queue { layerOf[id] = 0 }

        var progress = true
        while progress {
            progress = false
            for id in ids where layerOf[id] == nil {
                let preds = incoming[id, default: []]
                let known = preds.compactMap { layerOf[$0] }
                if !preds.isEmpty, known.count == preds.count {
                    layerOf[id] = (known.max() ?? 0) + 1
                    progress = true
                } else if preds.isEmpty {
                    layerOf[id] = 0
                    progress = true
                }
            }
            if !progress, let stuck = ids.first(where: { layerOf[$0] == nil }) {
                let predLayers = incoming[stuck, default: []].compactMap { layerOf[$0] }
                layerOf[stuck] = (predLayers.max() ?? (layerOf.values.max() ?? 0)) + (predLayers.isEmpty ? 0 : 1)
                progress = true
            }
        }

        let maxLayer = layerOf.values.max() ?? 0
        var layers: [[UUID]] = Array(repeating: [], count: maxLayer + 1)
        for id in ids {
            layers[layerOf[id] ?? 0].append(id)
        }

        // 3. Crossing reduction: barycenter + crossing-count tie-break; early exit.
        var bestCrossings = countCrossings(layers: layers, outgoing: outgoing)
        for _ in 0..<8 {
            var next = layers
            for layerIndex in 1..<next.count {
                let previous = next[layerIndex - 1]
                next[layerIndex] = sortedByBarycenter(next[layerIndex], neighbors: incoming, order: previous)
            }
            for layerIndex in stride(from: next.count - 2, through: 0, by: -1) {
                let following = next[layerIndex + 1]
                next[layerIndex] = sortedByBarycenter(next[layerIndex], neighbors: outgoing, order: following)
            }
            let crossings = countCrossings(layers: next, outgoing: outgoing)
            if crossings >= bestCrossings {
                break
            }
            bestCrossings = crossings
            layers = next
        }

        // 4. Brandes–Köpf-lite / priority coordinate assignment.
        let positions = assignCoordinates(
            layers: layers,
            sizes: sizes,
            incoming: incoming,
            outgoing: outgoing,
            options: options
        )

        let byID = Dictionary(uniqueKeysWithValues: positions.map { ($0.id, $0) })
        return graph.nodes.compactMap { byID[$0.id] }
    }

    // MARK: - Cycle break

    private func reverseBackEdges(
        ids: [UUID],
        outgoing: inout [UUID: [UUID]],
        incoming: inout [UUID: [UUID]]
    ) {
        var color: [UUID: Int] = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) }) // 0 white, 1 gray, 2 black

        // Explicit-stack DFS (the recursive version risked overflow on a deep chain). Each frame
        // holds its own *snapshot* of `outgoing[node]`, taken when the frame is pushed — mirroring
        // `for v in outgoing[u, default: []]` in the recursive version, which iterates a value,
        // not a live reference, so an edge reversed elsewhere mid-traversal can't retroactively
        // alter a frame already partway through its own snapshot.
        for start in ids where color[start] == 0 {
            var frameNode: [UUID] = [start]
            var frameEdges: [[UUID]] = [outgoing[start, default: []]]
            var frameCursor: [Int] = [0]
            color[start] = 1

            while let u = frameNode.last {
                let cursor = frameCursor[frameCursor.count - 1]
                let edges = frameEdges[frameEdges.count - 1]

                guard cursor < edges.count else {
                    color[u] = 2
                    frameNode.removeLast()
                    frameEdges.removeLast()
                    frameCursor.removeLast()
                    continue
                }

                let v = edges[cursor]
                frameCursor[frameCursor.count - 1] += 1

                if color[v] == 1 {
                    // Back edge u → v: reverse to v → u.
                    outgoing[u]?.removeAll { $0 == v }
                    incoming[v]?.removeAll { $0 == u }
                    if outgoing[v]?.contains(u) != true {
                        outgoing[v, default: []].append(u)
                    }
                    if incoming[u]?.contains(v) != true {
                        incoming[u, default: []].append(v)
                    }
                } else if color[v] == 0 {
                    color[v] = 1
                    frameNode.append(v)
                    frameEdges.append(outgoing[v, default: []])
                    frameCursor.append(0)
                }
            }
        }
    }

    // MARK: - Crossing helpers

    /// Sorts `layer` by barycenter position among `order`, computing each id's barycenter exactly
    /// once via a precomputed `order` index (rather than the old `order.firstIndex(of:)` linear
    /// scan called from *inside* the sort comparator — O(n² log n) since it reran for both
    /// operands on every comparison). Comparator semantics (including the `abs < 0.0001` tie
    /// tolerance) are unchanged, so output is identical to the previous implementation.
    private func sortedByBarycenter(_ layer: [UUID], neighbors: [UUID: [UUID]], order: [UUID]) -> [UUID] {
        let orderIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let mid = CGFloat(order.count) / 2
        var value: [UUID: CGFloat] = [:]
        value.reserveCapacity(layer.count)
        for id in layer {
            let idxs = neighbors[id, default: []].compactMap { orderIndex[$0] }
            value[id] = idxs.isEmpty ? mid : idxs.reduce(CGFloat(0)) { $0 + CGFloat($1) } / CGFloat(idxs.count)
        }
        return layer.sorted { a, b in
            let ba = value[a] ?? mid
            let bb = value[b] ?? mid
            if abs(ba - bb) < 0.0001 {
                return ba <= bb
            }
            return ba < bb
        }
    }

    private func countCrossings(layers: [[UUID]], outgoing: [UUID: [UUID]]) -> Int {
        var total = 0
        for layerIndex in 0..<(layers.count - 1) {
            let upper = layers[layerIndex]
            let lower = layers[layerIndex + 1]
            let lowerIndex = Dictionary(uniqueKeysWithValues: lower.enumerated().map { ($1, $0) })

            // `flat` concatenates each upper node's lower-index targets, grouped in upper order —
            // exactly the sequence the old O(pairs²) double loop walked. A pair only counts as a
            // crossing when the two edges come from *different* upper nodes, so total inversions
            // of the flat sequence minus each group's own (necessarily same-upper-node) inversions
            // gives exactly the old count, via merge-sort in O(p log p) instead of O(p²).
            var flat: [Int] = []
            flat.reserveCapacity(upper.count)
            var withinGroup = 0
            for u in upper {
                let group = outgoing[u, default: []].compactMap { lowerIndex[$0] }
                withinGroup += countInversions(group)
                flat.append(contentsOf: group)
            }
            total += countInversions(flat) - withinGroup
        }
        return total
    }

    /// Count of pairs (i, j), i < j, with values[i] > values[j] — computed via merge-sort passes
    /// instead of the equivalent O(n²) double loop.
    private func countInversions(_ values: [Int]) -> Int {
        guard values.count > 1 else { return 0 }
        var work = values
        var buffer = values
        var inversions = 0

        func mergeSort(_ lo: Int, _ hi: Int) {
            guard hi - lo > 1 else { return }
            let mid = (lo + hi) / 2
            mergeSort(lo, mid)
            mergeSort(mid, hi)
            var i = lo, j = mid, k = lo
            while i < mid, j < hi {
                if work[i] <= work[j] {
                    buffer[k] = work[i]
                    i += 1
                } else {
                    buffer[k] = work[j]
                    j += 1
                    inversions += mid - i
                }
                k += 1
            }
            while i < mid {
                buffer[k] = work[i]
                i += 1
                k += 1
            }
            while j < hi {
                buffer[k] = work[j]
                j += 1
                k += 1
            }
            for idx in lo..<hi { work[idx] = buffer[idx] }
        }

        mergeSort(0, work.count)
        return inversions
    }

    // MARK: - Coordinate assignment

    private func assignCoordinates(
        layers: [[UUID]],
        sizes: [UUID: CGSize],
        incoming: [UUID: [UUID]],
        outgoing: [UUID: [UUID]],
        options: LayoutOptions
    ) -> [NodeFrame] {
        switch options.direction {
        case .topToBottom:
            return assignTB(layers: layers, sizes: sizes, incoming: incoming, outgoing: outgoing, options: options)
        case .leftToRight:
            return assignLR(layers: layers, sizes: sizes, incoming: incoming, outgoing: outgoing, options: options)
        }
    }

    private func assignTB(
        layers: [[UUID]],
        sizes: [UUID: CGSize],
        incoming: [UUID: [UUID]],
        outgoing: [UUID: [UUID]],
        options: LayoutOptions
    ) -> [NodeFrame] {
        var xOf: [UUID: CGFloat] = [:]
        // Downward pass: place by median of parents, then resolve overlaps left→right.
        for (layerIndex, layer) in layers.enumerated() {
            if layerIndex == 0 {
                var x = options.origin.x
                for id in layer {
                    xOf[id] = x
                    x += (sizes[id]?.width ?? 160) + options.horizontalSpacing
                }
                continue
            }
            var desired: [(UUID, CGFloat)] = layer.map { id in
                let parents = incoming[id, default: []].compactMap { pid -> CGFloat? in
                    guard let px = xOf[pid], let pw = sizes[pid]?.width else { return nil }
                    return px + pw / 2
                }
                let mid: CGFloat
                if parents.isEmpty {
                    mid = options.origin.x
                } else {
                    let sorted = parents.sorted()
                    mid = sorted[sorted.count / 2]
                }
                let w = sizes[id]?.width ?? 160
                return (id, mid - w / 2)
            }
            desired.sort { $0.1 < $1.1 }
            var cursor = options.origin.x
            for (id, want) in desired {
                let w = sizes[id]?.width ?? 160
                let x = max(want, cursor)
                xOf[id] = x
                cursor = x + w + options.horizontalSpacing
            }
            // Restore layer order for packing while keeping relative priority.
            let order = Dictionary(uniqueKeysWithValues: layer.enumerated().map { ($1, $0) })
            let ordered = desired.map(\.0).sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
            cursor = options.origin.x
            for id in ordered {
                let w = sizes[id]?.width ?? 160
                let want = xOf[id] ?? cursor
                let x = max(want, cursor)
                xOf[id] = x
                cursor = x + w + options.horizontalSpacing
            }
            _ = outgoing // used for symmetry with LR; TB downward pass is primary
        }

        // Upward pass: pull toward children medians without breaking order.
        for layerIndex in stride(from: layers.count - 2, through: 0, by: -1) {
            let layer = layers[layerIndex]
            let next = layers[layerIndex + 1]
            _ = next
            var adjusted = layer.map { id -> (UUID, CGFloat) in
                let children = outgoing[id, default: []].compactMap { cid -> CGFloat? in
                    guard let cx = xOf[cid], let cw = sizes[cid]?.width else { return nil }
                    return cx + cw / 2
                }
                let w = sizes[id]?.width ?? 160
                guard !children.isEmpty else { return (id, xOf[id] ?? options.origin.x) }
                let sorted = children.sorted()
                let mid = sorted[sorted.count / 2]
                let current = xOf[id] ?? options.origin.x
                return (id, (current + (mid - w / 2)) / 2)
            }
            adjusted.sort { $0.1 < $1.1 }
            var cursor = options.origin.x
            let order = Dictionary(uniqueKeysWithValues: layer.enumerated().map { ($1, $0) })
            adjusted.sort { (order[$0.0] ?? 0) < (order[$1.0] ?? 0) }
            for (id, want) in adjusted {
                let w = sizes[id]?.width ?? 160
                let x = max(want, cursor)
                xOf[id] = x
                cursor = x + w + options.horizontalSpacing
            }
        }

        var result: [NodeFrame] = []
        var y = options.origin.y
        for layer in layers {
            let layerHeight = layer.map { sizes[$0]?.height ?? 0 }.max() ?? 0
            for id in layer {
                let size = sizes[id] ?? CGSize(width: 160, height: 100)
                let x = xOf[id] ?? options.origin.x
                result.append(NodeFrame(id: id, frame: CGRect(origin: CGPoint(x: x, y: y), size: size)))
            }
            y += layerHeight + options.verticalSpacing
        }
        return result
    }

    private func assignLR(
        layers: [[UUID]],
        sizes: [UUID: CGSize],
        incoming: [UUID: [UUID]],
        outgoing: [UUID: [UUID]],
        options: LayoutOptions
    ) -> [NodeFrame] {
        var yOf: [UUID: CGFloat] = [:]
        for (layerIndex, layer) in layers.enumerated() {
            if layerIndex == 0 {
                var y = options.origin.y
                for id in layer {
                    yOf[id] = y
                    y += (sizes[id]?.height ?? 100) + options.verticalSpacing
                }
                continue
            }
            var desired: [(UUID, CGFloat)] = layer.map { id in
                let parents = incoming[id, default: []].compactMap { pid -> CGFloat? in
                    guard let py = yOf[pid], let ph = sizes[pid]?.height else { return nil }
                    return py + ph / 2
                }
                let mid: CGFloat
                if parents.isEmpty {
                    mid = options.origin.y
                } else {
                    let sorted = parents.sorted()
                    mid = sorted[sorted.count / 2]
                }
                let h = sizes[id]?.height ?? 100
                return (id, mid - h / 2)
            }
            let order = Dictionary(uniqueKeysWithValues: layer.enumerated().map { ($1, $0) })
            desired.sort { (order[$0.0] ?? 0) < (order[$1.0] ?? 0) }
            var cursor = options.origin.y
            for (id, want) in desired {
                let h = sizes[id]?.height ?? 100
                let y = max(want, cursor)
                yOf[id] = y
                cursor = y + h + options.verticalSpacing
            }
            _ = outgoing
        }

        for layerIndex in stride(from: layers.count - 2, through: 0, by: -1) {
            let layer = layers[layerIndex]
            var adjusted = layer.map { id -> (UUID, CGFloat) in
                let children = outgoing[id, default: []].compactMap { cid -> CGFloat? in
                    guard let cy = yOf[cid], let ch = sizes[cid]?.height else { return nil }
                    return cy + ch / 2
                }
                let h = sizes[id]?.height ?? 100
                guard !children.isEmpty else { return (id, yOf[id] ?? options.origin.y) }
                let sorted = children.sorted()
                let mid = sorted[sorted.count / 2]
                let current = yOf[id] ?? options.origin.y
                return (id, (current + (mid - h / 2)) / 2)
            }
            let order = Dictionary(uniqueKeysWithValues: layer.enumerated().map { ($1, $0) })
            adjusted.sort { (order[$0.0] ?? 0) < (order[$1.0] ?? 0) }
            var cursor = options.origin.y
            for (id, want) in adjusted {
                let h = sizes[id]?.height ?? 100
                let y = max(want, cursor)
                yOf[id] = y
                cursor = y + h + options.verticalSpacing
            }
        }

        var result: [NodeFrame] = []
        var x = options.origin.x
        for layer in layers {
            let layerWidth = layer.map { sizes[$0]?.width ?? 0 }.max() ?? 0
            for id in layer {
                let size = sizes[id] ?? CGSize(width: 160, height: 100)
                let y = yOf[id] ?? options.origin.y
                result.append(NodeFrame(id: id, frame: CGRect(origin: CGPoint(x: x, y: y), size: size)))
            }
            x += layerWidth + options.horizontalSpacing
        }
        return result
    }
    public init() {}
}
