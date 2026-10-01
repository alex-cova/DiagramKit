import CoreGraphics
import Foundation

public nonisolated enum AlignmentEdge: String, Sendable, CaseIterable {
    case left, centerX, right, top, centerY, bottom
}

public nonisolated enum DistributionAxis: String, Sendable, CaseIterable {
    case horizontal, vertical
}

public nonisolated enum AlignmentEngine {
    /// Align frames to the union bounds along `edge`. No-op with fewer than 2 frames. Size unchanged.
    public static func align(_ frames: [NodeFrame], edge: AlignmentEdge) -> [NodeFrame] {
        guard frames.count >= 2 else { return frames }
        let bounds = unionBounds(frames)
        return frames.map { item in
            var frame = item.frame
            switch edge {
            case .left:
                frame.origin.x = bounds.minX
            case .centerX:
                frame.origin.x = bounds.midX - frame.width / 2
            case .right:
                frame.origin.x = bounds.maxX - frame.width
            case .top:
                frame.origin.y = bounds.minY
            case .centerY:
                frame.origin.y = bounds.midY - frame.height / 2
            case .bottom:
                frame.origin.y = bounds.maxY - frame.height
            }
            return NodeFrame(id: item.id, frame: frame)
        }
    }

    /// Evenly distribute gaps between frames along `axis`. Keeps first/last fixed. No-op with fewer than 3.
    public static func distribute(_ frames: [NodeFrame], axis: DistributionAxis) -> [NodeFrame] {
        guard frames.count >= 3 else { return frames }

        switch axis {
        case .horizontal:
            let sorted = frames.sorted { $0.frame.minX < $1.frame.minX }
            let first = sorted[0]
            let last = sorted[sorted.count - 1]
            let middle = Array(sorted.dropFirst().dropLast())
            let middleWidthSum = middle.reduce(CGFloat(0)) { $0 + $1.frame.width }
            let free = last.frame.minX - first.frame.maxX - middleWidthSum
            let gap = free / CGFloat(sorted.count - 1)

            var placed: [NodeFrame] = [first]
            var cursor = first.frame.maxX + gap
            for item in middle {
                var frame = item.frame
                frame.origin.x = cursor
                placed.append(NodeFrame(id: item.id, frame: frame))
                cursor = frame.maxX + gap
            }
            placed.append(last)
            let byID = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0) })
            return frames.compactMap { byID[$0.id] }

        case .vertical:
            let sorted = frames.sorted { $0.frame.minY < $1.frame.minY }
            let first = sorted[0]
            let last = sorted[sorted.count - 1]
            let middle = Array(sorted.dropFirst().dropLast())
            let middleHeightSum = middle.reduce(CGFloat(0)) { $0 + $1.frame.height }
            let free = last.frame.minY - first.frame.maxY - middleHeightSum
            let gap = free / CGFloat(sorted.count - 1)

            var placed: [NodeFrame] = [first]
            var cursor = first.frame.maxY + gap
            for item in middle {
                var frame = item.frame
                frame.origin.y = cursor
                placed.append(NodeFrame(id: item.id, frame: frame))
                cursor = frame.maxY + gap
            }
            placed.append(last)
            let byID = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0) })
            return frames.compactMap { byID[$0.id] }
        }
    }

    public static func nudge(_ frames: [NodeFrame], offset: CGSize) -> [NodeFrame] {
        frames.map { item in
            NodeFrame(
                id: item.id,
                frame: item.frame.offsetBy(dx: offset.width, dy: offset.height)
            )
        }
    }

    public static func nudgeStep(canvas: CanvasSettings, shift: Bool) -> CGFloat {
        let base: CGFloat = canvas.snapEnabled ? max(1, canvas.gridSize) : 1
        return shift ? base * 10 : base
    }

    private static func unionBounds(_ frames: [NodeFrame]) -> CGRect {
        guard let first = frames.first else { return .zero }
        return frames.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }
}
