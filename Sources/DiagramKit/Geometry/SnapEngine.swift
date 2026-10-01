import CoreGraphics
import Foundation

public nonisolated enum SnapEngine {
    public static let guideTolerance: CGFloat = 6

    public static func snap(_ value: CGFloat, grid: CGFloat) -> CGFloat {
        guard grid > 0 else { return value }
        return (value / grid).rounded() * grid
    }

    public static func snap(_ point: CGPoint, grid: CGFloat) -> CGPoint {
        CGPoint(x: snap(point.x, grid: grid), y: snap(point.y, grid: grid))
    }

    public static func snap(_ rect: CGRect, grid: CGFloat) -> CGRect {
        let origin = snap(rect.origin, grid: grid)
        return CGRect(origin: origin, size: rect.size)
    }

    public static func snapSize(_ size: CGSize, grid: CGFloat) -> CGSize {
        CGSize(width: max(grid, snap(size.width, grid: grid)), height: max(grid, snap(size.height, grid: grid)))
    }

    /// Snap a moving frame against other frames; returns snapped frame + guide lines.
    ///
    /// Single pass over `others` per candidate check — no intermediate `lefts`/`rights`/
    /// `centersX`/`tops`/`bottoms`/`centersY` arrays or concatenations (~12 array allocations per
    /// moving node per drag event in the old implementation). `nearestCandidate` scans `others`
    /// once per selector, in the same `[minX, maxX, midX]` (or Y) order the old concatenation
    /// used, so ties still resolve to whichever candidate appears first — bit-identical output.
    public static func snapFrame(
        _ frame: CGRect,
        to others: [CGRect],
        tolerance: CGFloat = guideTolerance
    ) -> (frame: CGRect, guides: [GuideLine]) {
        var origin = frame.origin
        var guides: [GuideLine] = []
        let xSelectors: [(CGRect) -> CGFloat] = [\.minX, \.maxX, \.midX]
        let ySelectors: [(CGRect) -> CGFloat] = [\.minY, \.maxY, \.midY]

        if let x = nearestCandidate(to: frame.minX, in: others, tolerance: tolerance, selectors: xSelectors) {
            origin.x = x
            guides.append(GuideLine(axis: .vertical, position: x))
        } else if let x = nearestCandidate(to: frame.midX, in: others, tolerance: tolerance, selectors: xSelectors) {
            origin.x = x - frame.width / 2
            guides.append(GuideLine(axis: .vertical, position: x))
        } else if let x = nearestCandidate(to: frame.maxX, in: others, tolerance: tolerance, selectors: xSelectors) {
            origin.x = x - frame.width
            guides.append(GuideLine(axis: .vertical, position: x))
        }

        if let y = nearestCandidate(to: frame.minY, in: others, tolerance: tolerance, selectors: ySelectors) {
            origin.y = y
            guides.append(GuideLine(axis: .horizontal, position: y))
        } else if let y = nearestCandidate(to: frame.midY, in: others, tolerance: tolerance, selectors: ySelectors) {
            origin.y = y - frame.height / 2
            guides.append(GuideLine(axis: .horizontal, position: y))
        } else if let y = nearestCandidate(to: frame.maxY, in: others, tolerance: tolerance, selectors: ySelectors) {
            origin.y = y - frame.height
            guides.append(GuideLine(axis: .horizontal, position: y))
        }

        return (CGRect(origin: origin, size: frame.size), guides)
    }

    /// Closest value (within `tolerance`) to `target` across `selectors` applied to `others`, in
    /// selector order — matches the tie-break of the old `lefts + rights + centersX` concatenation:
    /// the first-found value at the smallest distance wins (a later exact tie does not replace it).
    private static func nearestCandidate(
        to target: CGFloat,
        in others: [CGRect],
        tolerance: CGFloat,
        selectors: [(CGRect) -> CGFloat]
    ) -> CGFloat? {
        var best: CGFloat?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for selector in selectors {
            for rect in others {
                let value = selector(rect)
                let distance = abs(value - target)
                guard distance <= tolerance, distance < bestDistance else { continue }
                bestDistance = distance
                best = value
            }
        }
        return best
    }
}
