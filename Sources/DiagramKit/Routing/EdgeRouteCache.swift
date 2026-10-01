import CoreGraphics
import Foundation

/// Cached edge polylines keyed by a document geometry fingerprint.
/// Rebuilds all routes when the fingerprint changes (node frames, edges, routing settings).
public nonisolated struct EdgeRouteCache: Sendable {
    private var fingerprint: UInt64 = 0
    private var routesByID: [UUID: EdgeRoute] = [:]
    private var ordered: [(id: UUID, route: EdgeRoute)] = []

    public var isEmpty: Bool { ordered.isEmpty }

    public mutating func invalidate() {
        fingerprint = 0
        routesByID.removeAll(keepingCapacity: true)
        ordered.removeAll(keepingCapacity: true)
    }

    /// Returns cached routes or rebuilds via `builder` when `fingerprint` changes.
    public mutating func routes(
        fingerprint: UInt64,
        builder: () -> [(id: UUID, route: EdgeRoute)]
    ) -> [(id: UUID, route: EdgeRoute)] {
        if fingerprint == self.fingerprint {
            return ordered
        }
        let built = builder()
        self.fingerprint = fingerprint
        ordered = built
        routesByID = Dictionary(uniqueKeysWithValues: built.map { ($0.id, $0.route) })
        return ordered
    }

    public func route(id: UUID) -> EdgeRoute? {
        routesByID[id]
    }

    /// Drop cached routes for specific edges without touching the rest — the counterpart to
    /// `invalidate()`, which drops everything. Used when only some node frames moved, so only the
    /// routes that could plausibly have changed need to be recomputed.
    public mutating func evict(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            routesByID.removeValue(forKey: id)
        }
    }

    /// Rebuild only the routes missing after `evict(_:)` (or entirely, on first use / after a full
    /// `invalidate()`), preserving `order`. `rebuild` is handed exactly the missing ids so the
    /// caller can recompute just those edges instead of the whole document.
    public mutating func patch(
        fingerprint: UInt64,
        order: [UUID],
        rebuild: (Set<UUID>) -> [(id: UUID, route: EdgeRoute)]
    ) -> [(id: UUID, route: EdgeRoute)] {
        if fingerprint == self.fingerprint {
            return ordered
        }
        let missing = order.filter { routesByID[$0] == nil }
        if !missing.isEmpty {
            for (id, route) in rebuild(Set(missing)) {
                routesByID[id] = route
            }
        }
        self.fingerprint = fingerprint
        ordered = order.compactMap { id in
            routesByID[id].map { (id: id, route: $0) }
        }
        return ordered
    }

    /// Edge ids whose cached route may be stale after nodes in `movedNodeIDs` moved from
    /// `beforeFrames` to `afterFrames`. Always includes edges incident to a moved node.
    /// When `avoidObstacles` is true, also includes any edge whose *cached* route bounding box
    /// intersects the moved nodes' swept path (their before ∪ after frames, padded) — those are
    /// exactly the routes `ObstacleAvoider` could have detoured around, or freed a detour from,
    /// even though neither endpoint moved.
    public static func edgesNeedingReroute(
        movedNodeIDs: Set<UUID>,
        beforeFrames: [UUID: CGRect],
        afterFrames: [UUID: CGRect],
        edges: [(id: UUID, source: UUID, destination: UUID)],
        routeBoxes: (UUID) -> CGRect?,
        avoidObstacles: Bool,
        padding: CGFloat = 12
    ) -> Set<UUID> {
        guard !movedNodeIDs.isEmpty else { return [] }
        var affected: Set<UUID> = []
        for edge in edges where movedNodeIDs.contains(edge.source) || movedNodeIDs.contains(edge.destination) {
            affected.insert(edge.id)
        }
        guard avoidObstacles else { return affected }

        var swept = CGRect.null
        for id in movedNodeIDs {
            if let before = beforeFrames[id] { swept = swept.union(before) }
            if let after = afterFrames[id] { swept = swept.union(after) }
        }
        guard !swept.isNull else { return affected }
        let expanded = swept.insetBy(dx: -padding, dy: -padding)

        for edge in edges where !affected.contains(edge.id) {
            if let box = routeBoxes(edge.id), box.intersects(expanded) {
                affected.insert(edge.id)
            }
        }
        return affected
    }

    /// Stable fingerprint over frames, edge endpoints/anchors, and routing settings.
    ///
    /// Order-independent by construction (nodes/edges are mixed with `&+`, not sorted), so this
    /// costs O(n) with zero heap allocation instead of the O(n log n) sort over `UUID.uuidString`
    /// (two 36-byte String allocations per comparison) this used to do. Node and edge contributions
    /// are accumulated into *separate* running sums before being combined, so a change that only
    /// swaps which node owns which frame (id↔geometry pairing) still changes the node accumulator —
    /// it can't be masked by an edge-side cancellation.
    public static func fingerprint(
        nodeFrames: [(UUID, CGRect)],
        edges: [(id: UUID, source: UUID, destination: UUID, sourceAnchor: EdgeAnchor, targetAnchor: EdgeAnchor)],
        style: EdgeRoutingStyle,
        avoidObstacles: Bool
    ) -> UInt64 {
        var nodeAcc: UInt64 = 0
        for (id, frame) in nodeFrames {
            var h = Hasher()
            h.combine(id)
            h.combine(frame.origin.x)
            h.combine(frame.origin.y)
            h.combine(frame.size.width)
            h.combine(frame.size.height)
            nodeAcc = nodeAcc &+ UInt64(bitPattern: Int64(h.finalize()))
        }

        var edgeAcc: UInt64 = 0
        for edge in edges {
            var h = Hasher()
            h.combine(edge.id)
            h.combine(edge.source)
            h.combine(edge.destination)
            hashAnchor(edge.sourceAnchor, into: &h)
            hashAnchor(edge.targetAnchor, into: &h)
            edgeAcc = edgeAcc &+ UInt64(bitPattern: Int64(h.finalize()))
        }

        var hasher = Hasher()
        hasher.combine(style)
        hasher.combine(avoidObstacles)
        hasher.combine(nodeAcc)
        hasher.combine(edgeAcc)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private static func hashAnchor(_ anchor: EdgeAnchor, into hasher: inout Hasher) {
        switch anchor {
        case .auto:
            hasher.combine(0)
        case .side(let side, let t):
            hasher.combine(1)
            hasher.combine(side)
            hasher.combine(t)
        }
    }
    public init() {}
}

public extension EdgeRoute {
    nonisolated var boundingBox: CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
