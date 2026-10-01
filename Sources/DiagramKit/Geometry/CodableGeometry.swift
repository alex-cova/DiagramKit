import CoreGraphics
import Foundation

/// Codable stand-in for `CGPoint` so document models stay `Sendable` and JSON-friendly.
public nonisolated struct CodablePoint: Codable, Sendable, Equatable, Hashable {
    public var x: CGFloat
    public var y: CGFloat

    public init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public nonisolated struct CodableSize: Codable, Sendable, Equatable, Hashable {
    public var width: CGFloat
    public var height: CGFloat

    public init(_ size: CGSize) {
        width = size.width
        height = size.height
    }

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
}

public nonisolated struct CodableRect: Codable, Sendable, Equatable, Hashable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat

    public init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
