import CoreGraphics
import Foundation

public nonisolated struct CanvasSettings: Codable, Sendable, Equatable {
    public var gridSize: CGFloat
    public var snapEnabled: Bool
    public var showGrid: Bool
    public var edgeRouting: EdgeRoutingStyle
    public var avoidObstacles: Bool
    public var animateLayout: Bool
    public var themeID: String
    public var showGuides: Bool
    public var showRulers: Bool
    public var showMiniMap: Bool

    public init(
        gridSize: CGFloat = 16,
        snapEnabled: Bool = true,
        showGrid: Bool = true,
        edgeRouting: EdgeRoutingStyle = .orthogonal,
        avoidObstacles: Bool = true,
        animateLayout: Bool = true,
        themeID: String = DiagramThemeCatalog.light.id,
        showGuides: Bool = true,
        showRulers: Bool = false,
        showMiniMap: Bool = false
    ) {
        self.gridSize = gridSize
        self.snapEnabled = snapEnabled
        self.showGrid = showGrid
        self.edgeRouting = edgeRouting
        self.avoidObstacles = avoidObstacles
        self.animateLayout = animateLayout
        self.themeID = themeID
        self.showGuides = showGuides
        self.showRulers = showRulers
        self.showMiniMap = showMiniMap
    }

    public var theme: DiagramTheme {
        resolvedTheme(forDarkAppearance: DiagramAppearance.isDark)
    }

    public func resolvedThemeID(forDarkAppearance isDark: Bool) -> String {
        DiagramThemeCatalog.resolvedID(id: themeID, forDarkAppearance: isDark)
    }

    public func resolvedTheme(forDarkAppearance isDark: Bool) -> DiagramTheme {
        DiagramThemeCatalog.resolved(id: themeID, forDarkAppearance: isDark)
    }

    public enum CodingKeys: String, CodingKey {
        case gridSize, snapEnabled, showGrid, edgeRouting, avoidObstacles, animateLayout, themeID
        case showGuides, showRulers, showMiniMap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gridSize = try container.decodeIfPresent(CGFloat.self, forKey: .gridSize) ?? 16
        snapEnabled = try container.decodeIfPresent(Bool.self, forKey: .snapEnabled) ?? true
        showGrid = try container.decodeIfPresent(Bool.self, forKey: .showGrid) ?? true
        edgeRouting = try container.decodeIfPresent(EdgeRoutingStyle.self, forKey: .edgeRouting) ?? .orthogonal
        avoidObstacles = try container.decodeIfPresent(Bool.self, forKey: .avoidObstacles) ?? true
        animateLayout = try container.decodeIfPresent(Bool.self, forKey: .animateLayout) ?? true
        themeID = try container.decodeIfPresent(String.self, forKey: .themeID) ?? DiagramThemeCatalog.light.id
        showGuides = try container.decodeIfPresent(Bool.self, forKey: .showGuides) ?? true
        showRulers = try container.decodeIfPresent(Bool.self, forKey: .showRulers) ?? false
        showMiniMap = try container.decodeIfPresent(Bool.self, forKey: .showMiniMap) ?? false
    }
}
