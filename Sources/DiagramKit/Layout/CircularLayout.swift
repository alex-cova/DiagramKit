import CoreGraphics
import Foundation

/// Place nodes on a circle centered near `options.origin`.
public nonisolated struct CircularLayout: LayoutAlgorithm {
    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let maxSize = graph.nodes.map { max($0.frame.width, $0.frame.height) }.max() ?? 120
        let count = graph.nodes.count
        let radius: CGFloat
        if count == 1 {
            radius = 0
        } else {
            let chord = maxSize + options.horizontalSpacing
            radius = max(chord / (2 * sin(.pi / CGFloat(count))), maxSize)
        }
        let center = CGPoint(
            x: options.origin.x + radius + maxSize,
            y: options.origin.y + radius + maxSize
        )
        return graph.nodes.enumerated().map { index, node in
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi - .pi / 2
            let cx = center.x + cos(angle) * radius
            let cy = center.y + sin(angle) * radius
            return NodeFrame(
                id: node.id,
                frame: CGRect(
                    x: cx - node.frame.width / 2,
                    y: cy - node.frame.height / 2,
                    width: node.frame.width,
                    height: node.frame.height
                )
            )
        }
    }
    public init() {}
}
