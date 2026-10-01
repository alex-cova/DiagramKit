import CoreGraphics
import Foundation

/// Visual emphasis tier for a diagram edge given the current selection.
public nonisolated enum EdgeHighlightLevel: Sendable, Equatable {
    case normal
    /// An endpoint node is selected, but the edge itself is not.
    case connected
    /// The edge ID is in the selection set.
    case selected
    /// Node focus is active and this edge is not part of the focused subgraph.
    case dimmed
}

/// Visual emphasis tier for a diagram node when one or more nodes are selected.
public nonisolated enum NodeHighlightLevel: Sendable, Equatable {
    case normal
    case dimmed
    case connected
    case selected
}

/// Focus helpers for dimming unrelated nodes and edges when a node is selected.
public nonisolated enum DiagramFocusResolver {
    public static let dimmedNodeOpacity = 0.28
    public static let dimmedEdgeOpacity = 0.18

    public static func hasNodeFocus(selection: Set<UUID>, nodeIDs: Set<UUID>) -> Bool {
        !selection.intersection(nodeIDs).isEmpty
    }

    public static func nodeLevel(
        nodeID: UUID,
        selection: Set<UUID>,
        edges: [(UUID, UUID)],
        nodeIDs: Set<UUID>
    ) -> NodeHighlightLevel {
        guard hasNodeFocus(selection: selection, nodeIDs: nodeIDs) else { return .normal }
        if selection.contains(nodeID) { return .selected }
        let selectedNodes = selection.intersection(nodeIDs)
        for (sourceID, destinationID) in edges {
            if sourceID == nodeID, selectedNodes.contains(destinationID) { return .connected }
            if destinationID == nodeID, selectedNodes.contains(sourceID) { return .connected }
        }
        return .dimmed
    }

    public static func nodeOpacity(level: NodeHighlightLevel) -> Double {
        switch level {
        case .dimmed: dimmedNodeOpacity
        case .normal, .connected, .selected: 1
        }
    }

    public static func adjustedColor(
        _ color: CodableColor,
        level: NodeHighlightLevel,
        isDark: Bool = DiagramAppearance.isDark
    ) -> CodableColor {
        let base = isDark ? color.diagramDisplayFill(isDark: true) : color
        let factor = nodeOpacity(level: level)
        guard factor < 1 else { return base }
        let dimmed = CodableColor(
            red: base.red,
            green: base.green,
            blue: base.blue,
            opacity: base.opacity * factor
        )
        return isDark ? dimmed.diagramDisplayFill(isDark: true) : dimmed
    }

    public static func adjustedStroke(
        _ color: CodableColor,
        level: NodeHighlightLevel,
        isDark: Bool = DiagramAppearance.isDark
    ) -> CodableColor {
        let base = isDark ? color.diagramDisplayStroke(isDark: true) : color
        let factor = nodeOpacity(level: level)
        guard factor < 1 else { return base }
        let dimmed = CodableColor(
            red: base.red,
            green: base.green,
            blue: base.blue,
            opacity: base.opacity * factor
        )
        return isDark ? dimmed.diagramDisplayStroke(isDark: true) : dimmed
    }

    public static func adjustedLabelColor(
        fill: CodableColor,
        level: NodeHighlightLevel,
        isDark: Bool = DiagramAppearance.isDark
    ) -> CodableColor {
        let displayFill = adjustedColor(fill, level: level, isDark: isDark)
        var label = displayFill.contrastingLabel
        let factor = nodeOpacity(level: level)
        guard factor < 1 else { return label }
        label.opacity *= factor
        return label
    }
}

/// Classifies edges and resolves stroke appearance from the active diagram theme.
public nonisolated enum EdgeHighlightResolver {
    public static let connectedOpacity = 0.65
    public static let dimmedOpacity = DiagramFocusResolver.dimmedEdgeOpacity
    public static let normalLineWidth: CGFloat = 1.5
    public static let connectedLineWidth: CGFloat = 2.0
    public static let selectedLineWidth: CGFloat = 2.5

    public static func level(
        edgeID: UUID,
        sourceID: UUID,
        destinationID: UUID,
        selection: Set<UUID>,
        nodeIDs: Set<UUID> = []
    ) -> EdgeHighlightLevel {
        let base: EdgeHighlightLevel
        if selection.contains(edgeID) {
            base = .selected
        } else if selection.contains(sourceID) || selection.contains(destinationID) {
            base = .connected
        } else {
            base = .normal
        }
        guard DiagramFocusResolver.hasNodeFocus(selection: selection, nodeIDs: nodeIDs) else {
            return base
        }
        return base == .normal ? .dimmed : base
    }

    public static func appearance(
        level: EdgeHighlightLevel,
        theme: DiagramTheme
    ) -> (stroke: CodableColor, lineWidth: CGFloat) {
        switch level {
        case .normal:
            return (theme.defaultEdgeStroke, normalLineWidth)
        case .connected:
            let accent = theme.accent
            return (
                CodableColor(
                    red: accent.red,
                    green: accent.green,
                    blue: accent.blue,
                    opacity: accent.opacity * connectedOpacity
                ),
                connectedLineWidth
            )
        case .selected:
            return (theme.accent, selectedLineWidth)
        case .dimmed:
            let stroke = theme.defaultEdgeStroke
            return (
                CodableColor(
                    red: stroke.red,
                    green: stroke.green,
                    blue: stroke.blue,
                    opacity: stroke.opacity * dimmedOpacity
                ),
                normalLineWidth
            )
        }
    }

    public static func isDirectlySelected(
        edgeID: UUID,
        selection: Set<UUID>
    ) -> Bool {
        selection.contains(edgeID)
    }

    public static func applyHighlight(
        to edge: inout SceneEdge,
        selection: Set<UUID>,
        theme: DiagramTheme,
        nodeIDs: Set<UUID> = []
    ) {
        let highlight = level(
            edgeID: edge.id,
            sourceID: edge.sourceID,
            destinationID: edge.destinationID,
            selection: selection,
            nodeIDs: nodeIDs
        )
        let style = appearance(level: highlight, theme: theme)
        edge.selected = isDirectlySelected(edgeID: edge.id, selection: selection)
        edge.stroke = style.stroke
        edge.lineWidth = style.lineWidth
    }

    public static func sceneEdgeStyle(
        edgeID: UUID,
        sourceID: UUID,
        destinationID: UUID,
        selection: Set<UUID>,
        theme: DiagramTheme,
        nodeIDs: Set<UUID> = []
    ) -> (stroke: CodableColor, lineWidth: CGFloat, selected: Bool) {
        let highlight = level(
            edgeID: edgeID,
            sourceID: sourceID,
            destinationID: destinationID,
            selection: selection,
            nodeIDs: nodeIDs
        )
        let style = appearance(level: highlight, theme: theme)
        return (style.stroke, style.lineWidth, isDirectlySelected(edgeID: edgeID, selection: selection))
    }
}
