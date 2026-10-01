import CoreGraphics
import Foundation

/// Uniform-grid spatial index for O(1)-ish point queries and AABB queries over node frames.
/// Cell size should be on the order of typical node size (default 256).
public nonisolated struct SpatialIndex: Sendable {
    public struct Entry: Sendable, Equatable {
        public var id: UUID
        public var frame: CGRect
        /// Higher values draw / pick above lower values (matches document order).
        public var zIndex: Int
        public init(
            id: UUID,
            frame: CGRect,
            zIndex: Int
        ) {
            self.id = id
            self.frame = frame
            self.zIndex = zIndex
        }
    }

    public var cellSize: CGFloat
    private var cells: [CellKey: [UUID]] = [:]
    private var entries: [UUID: Entry] = [:]

    public init(cellSize: CGFloat = 256) {
        self.cellSize = max(16, cellSize)
    }

    public var count: Int { entries.count }

    public mutating func removeAll() {
        cells.removeAll(keepingCapacity: true)
        entries.removeAll(keepingCapacity: true)
    }

    public mutating func rebuild<Node: DiagramNode>(_ nodes: [Node]) {
        removeAll()
        for (z, node) in nodes.enumerated() {
            insert(id: node.id, frame: node.frame, zIndex: z)
        }
    }

    public mutating func rebuild(frames: [NodeFrame]) {
        removeAll()
        for (z, item) in frames.enumerated() {
            insert(id: item.id, frame: item.frame, zIndex: z)
        }
    }

    public mutating func insert(id: UUID, frame: CGRect, zIndex: Int) {
        if entries[id] != nil {
            remove(id: id)
        }
        entries[id] = Entry(id: id, frame: frame, zIndex: zIndex)
        for key in cellKeys(covering: frame) {
            cells[key, default: []].append(id)
        }
    }

    public mutating func remove(id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        for key in cellKeys(covering: entry.frame) {
            cells[key]?.removeAll { $0 == id }
            if cells[key]?.isEmpty == true {
                cells.removeValue(forKey: key)
            }
        }
    }

    /// Top-most node whose frame contains `point`, or nil.
    public func hitTest(at point: CGPoint) -> UUID? {
        var best: Entry?
        for id in candidateIDs(covering: CGRect(origin: point, size: .zero)) {
            guard let entry = entries[id], entry.frame.contains(point) else { continue }
            if best == nil || entry.zIndex >= best!.zIndex {
                best = entry
            }
        }
        return best?.id
    }

    public func intersecting(_ rect: CGRect) -> Set<UUID> {
        var result: Set<UUID> = []
        for id in candidateIDs(covering: rect) {
            guard let entry = entries[id], entry.frame.intersects(rect) else { continue }
            result.insert(id)
        }
        return result
    }

    public func frame(for id: UUID) -> CGRect? {
        entries[id]?.frame
    }

    // MARK: - Grid helpers

    private struct CellKey: Hashable, Sendable {
        var x: Int
        var y: Int
    }

    private func cellKeys(covering rect: CGRect) -> [CellKey] {
        let minX = Int(floor(rect.minX / cellSize))
        let maxX = Int(floor((rect.maxX - 0.0001) / cellSize))
        let minY = Int(floor(rect.minY / cellSize))
        let maxY = Int(floor((rect.maxY - 0.0001) / cellSize))
        var keys: [CellKey] = []
        keys.reserveCapacity((maxX - minX + 1) * (maxY - minY + 1))
        for x in minX...max(minX, maxX) {
            for y in minY...max(minY, maxY) {
                keys.append(CellKey(x: x, y: y))
            }
        }
        return keys
    }

    private func candidateIDs(covering rect: CGRect) -> Set<UUID> {
        var ids: Set<UUID> = []
        for key in cellKeys(covering: rect) {
            if let bucket = cells[key] {
                ids.formUnion(bucket)
            }
        }
        return ids
    }
}
