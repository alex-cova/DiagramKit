import CoreGraphics
import Foundation

/// Minimal SVG document builder for diagram vector export.
public nonisolated final class SVGGraphics: @unchecked Sendable {
    public let bounds: CGRect
    private var elements: [String] = []

    public init(bounds: CGRect) {
        self.bounds = bounds
    }

    public func fillBackground(_ color: CodableColor) {
        // Pass world bounds so `toLocal` maps to the SVG viewport origin.
        rect(bounds, fill: color, stroke: nil, lineWidth: 0)
    }

    public func rect(
        _ rect: CGRect,
        fill: CodableColor?,
        stroke: CodableColor?,
        lineWidth: CGFloat
    ) {
        let local = toLocal(rect)
        var attrs = [
            "x=\"\(fmt(local.minX))\"",
            "y=\"\(fmt(local.minY))\"",
            "width=\"\(fmt(local.width))\"",
            "height=\"\(fmt(local.height))\""
        ]
        attrs.append(contentsOf: paintAttrs(fill: fill, stroke: stroke, lineWidth: lineWidth))
        elements.append("<rect \(attrs.joined(separator: " ")) />")
    }

    public func polyline(
        _ points: [CGPoint],
        stroke: CodableColor,
        lineWidth: CGFloat,
        dashed: Bool = false
    ) {
        guard points.count >= 2 else { return }
        let pts = points.map { point in
            let local = toLocal(point)
            return "\(fmt(local.x)),\(fmt(local.y))"
        }.joined(separator: " ")
        var attrs = [
            "points=\"\(pts)\"",
            "fill=\"none\"",
            "stroke=\"\(stroke.svgHex)\"",
            "stroke-opacity=\"\(stroke.svgOpacity)\"",
            "stroke-width=\"\(fmt(lineWidth))\""
        ]
        if dashed {
            attrs.append("stroke-dasharray=\"6 4\"")
        }
        elements.append("<polyline \(attrs.joined(separator: " ")) />")
    }

    public func path(
        _ points: [CGPoint],
        closed: Bool,
        fill: CodableColor?,
        stroke: CodableColor?,
        lineWidth: CGFloat
    ) {
        guard let first = points.first else { return }
        let start = toLocal(first)
        var d = "M \(fmt(start.x)) \(fmt(start.y))"
        for point in points.dropFirst() {
            let local = toLocal(point)
            d += " L \(fmt(local.x)) \(fmt(local.y))"
        }
        if closed {
            d += " Z"
        }
        var attrs = ["d=\"\(d)\""]
        attrs.append(contentsOf: paintAttrs(fill: fill, stroke: stroke, lineWidth: lineWidth))
        elements.append("<path \(attrs.joined(separator: " ")) />")
    }

    public func ellipse(
        in rect: CGRect,
        fill: CodableColor?,
        stroke: CodableColor?,
        lineWidth: CGFloat
    ) {
        let local = toLocal(rect)
        var attrs = [
            "cx=\"\(fmt(local.midX))\"",
            "cy=\"\(fmt(local.midY))\"",
            "rx=\"\(fmt(local.width / 2))\"",
            "ry=\"\(fmt(local.height / 2))\""
        ]
        attrs.append(contentsOf: paintAttrs(fill: fill, stroke: stroke, lineWidth: lineWidth))
        elements.append("<ellipse \(attrs.joined(separator: " ")) />")
    }

    public func text(
        _ string: String,
        at point: CGPoint,
        fontSize: CGFloat,
        fontFamily: String = "system-ui, sans-serif",
        weight: String = "normal",
        anchor: String = "start",
        fill: CodableColor
    ) {
        let local = toLocal(point)
        let escaped = escapeXML(string)
        elements.append(
            "<text x=\"\(fmt(local.x))\" y=\"\(fmt(local.y))\" font-size=\"\(fmt(fontSize))\" "
                + "font-family=\"\(fontFamily)\" font-weight=\"\(weight)\" text-anchor=\"\(anchor)\" "
                + "fill=\"\(fill.svgHex)\" fill-opacity=\"\(fill.svgOpacity)\">\(escaped)</text>"
        )
    }

    /// Embed a raster image as a `data:` URI (PNG preferred).
    public func image(_ data: Data, in rect: CGRect, mimeType: String = "image/png") {
        let local = toLocal(rect)
        let base64 = data.base64EncodedString()
        elements.append(
            "<image x=\"\(fmt(local.minX))\" y=\"\(fmt(local.minY))\" "
                + "width=\"\(fmt(local.width))\" height=\"\(fmt(local.height))\" "
                + "href=\"data:\(mimeType);base64,\(base64)\" preserveAspectRatio=\"xMidYMid meet\" />"
        )
    }

    public func line(
        from: CGPoint,
        to: CGPoint,
        stroke: CodableColor,
        lineWidth: CGFloat
    ) {
        polyline([from, to], stroke: stroke, lineWidth: lineWidth)
    }

    public func makeData() -> Data {
        let body = elements.joined(separator: "\n  ")
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(fmt(bounds.width))" height="\(fmt(bounds.height))" viewBox="0 0 \(fmt(bounds.width)) \(fmt(bounds.height))">
          \(body)
        </svg>
        """
        return Data(svg.utf8)
    }

    private func toLocal(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
    }

    private func toLocal(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - bounds.minX,
            y: rect.minY - bounds.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private func paintAttrs(fill: CodableColor?, stroke: CodableColor?, lineWidth: CGFloat) -> [String] {
        var attrs: [String] = []
        if let fill {
            attrs.append("fill=\"\(fill.svgHex)\"")
            attrs.append("fill-opacity=\"\(fill.svgOpacity)\"")
        } else {
            attrs.append("fill=\"none\"")
        }
        if let stroke {
            attrs.append("stroke=\"\(stroke.svgHex)\"")
            attrs.append("stroke-opacity=\"\(stroke.svgOpacity)\"")
            attrs.append("stroke-width=\"\(fmt(lineWidth))\"")
        } else {
            attrs.append("stroke=\"none\"")
        }
        return attrs
    }

    private func fmt(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(2)))
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
            .replacing("\"", with: "&quot;")
            .replacing("'", with: "&apos;")
    }
}
