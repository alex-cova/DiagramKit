import CoreGraphics
import Foundation

/// Sqrt-column packing; preserves each node's size.
public nonisolated struct GridLayout: LayoutAlgorithm {
    public func layout(_ graph: LayoutGraph, options: LayoutOptions) -> [NodeFrame] {
        guard !graph.nodes.isEmpty else { return [] }
        let columns = max(1, Int(ceil(sqrt(Double(graph.nodes.count)))))
        var columnWidths = Array(repeating: CGFloat(0), count: columns)
        var rowHeights: [CGFloat] = []

        for (index, node) in graph.nodes.enumerated() {
            let col = index % columns
            let row = index / columns
            while rowHeights.count <= row { rowHeights.append(0) }
            columnWidths[col] = max(columnWidths[col], node.frame.width)
            rowHeights[row] = max(rowHeights[row], node.frame.height)
        }

        var colOrigins: [CGFloat] = []
        var x = options.origin.x
        for width in columnWidths {
            colOrigins.append(x)
            x += width + options.horizontalSpacing
        }
        var rowOrigins: [CGFloat] = []
        var y = options.origin.y
        for height in rowHeights {
            rowOrigins.append(y)
            y += height + options.verticalSpacing
        }

        return graph.nodes.enumerated().map { index, node in
            let col = index % columns
            let row = index / columns
            let frame = CGRect(
                x: colOrigins[col],
                y: rowOrigins[row],
                width: node.frame.width,
                height: node.frame.height
            )
            return NodeFrame(id: node.id, frame: frame)
        }
    }
    public init() {}
}
