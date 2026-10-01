import CoreGraphics
import Foundation

/// Domain-agnostic geometric primitives for diagram nodes.
public nonisolated enum DiagramShape: Codable, Sendable, Equatable, Hashable {
    case rectangle
    case roundedRectangle(cornerRadius: CGFloat)
    case ellipse
    case diamond
    case polygon(sides: Int)
    case cylinder
    case capsule
    case parallelogram
    case custom

    public func path(in rect: CGRect) -> CGPath {
        switch self {
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .roundedRectangle(let radius):
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .diamond:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case .polygon(let sides):
            return Self.regularPolygon(sides: max(3, sides), in: rect)
        case .cylinder:
            return Self.cylinderPath(in: rect)
        case .capsule:
            let radius = min(rect.width, rect.height) / 2
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .parallelogram:
            return Self.parallelogramPath(in: rect)
        case .custom:
            return CGPath(rect: rect, transform: nil)
        }
    }

    public func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        path(in: rect).contains(point)
    }

    private static func regularPolygon(sides: Int, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<sides {
            let angle = (CGFloat(i) / CGFloat(sides)) * 2 * .pi - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func cylinderPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let ellipseHeight = min(rect.height * 0.2, 24)
        let body = CGRect(x: rect.minX, y: rect.minY + ellipseHeight / 2, width: rect.width, height: rect.height - ellipseHeight)
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: ellipseHeight))
        path.addRect(body)
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.maxY - ellipseHeight, width: rect.width, height: ellipseHeight))
        return path
    }

    /// Standard flowchart I/O skew: top edge shifts right by ~20% of width.
    private static func parallelogramPath(in rect: CGRect) -> CGPath {
        let skew = min(rect.width * 0.2, 28)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + skew, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

public nonisolated struct DiagramShapeStyle: Sendable, Equatable {
    public var fill: CodableColor
    public var stroke: CodableColor
    public var lineWidth: CGFloat

    public init(
        fill: CodableColor = .classFill,
        stroke: CodableColor = .classStroke,
        lineWidth: CGFloat = 1
    ) {
        self.fill = fill
        self.stroke = stroke
        self.lineWidth = lineWidth
    }
}
