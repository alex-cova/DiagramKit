import Foundation

/// Visual tokens for canvas chrome and default node/edge appearance.
public nonisolated struct DiagramTheme: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var displayName: String
    public var canvasBackground: CodableColor
    public var gridMinor: CodableColor
    public var gridMajor: CodableColor
    public var selectionFill: CodableColor
    public var selectionStroke: CodableColor
    public var defaultNodeFill: CodableColor
    public var defaultNodeStroke: CodableColor
    public var defaultEdgeStroke: CodableColor
    public var accent: CodableColor
    public init(
        id: String,
        displayName: String,
        canvasBackground: CodableColor,
        gridMinor: CodableColor,
        gridMajor: CodableColor,
        selectionFill: CodableColor,
        selectionStroke: CodableColor,
        defaultNodeFill: CodableColor,
        defaultNodeStroke: CodableColor,
        defaultEdgeStroke: CodableColor,
        accent: CodableColor
    ) {
        self.id = id
        self.displayName = displayName
        self.canvasBackground = canvasBackground
        self.gridMinor = gridMinor
        self.gridMajor = gridMajor
        self.selectionFill = selectionFill
        self.selectionStroke = selectionStroke
        self.defaultNodeFill = defaultNodeFill
        self.defaultNodeStroke = defaultNodeStroke
        self.defaultEdgeStroke = defaultEdgeStroke
        self.accent = accent
    }
}
