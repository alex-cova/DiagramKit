import Foundation

/// Hand-maintained plugin catalog (same spirit as `ToolRegistry`).
public nonisolated enum DiagramPluginRegistry {
    public static let umlIdentifier = "hextech.diagram.uml"
    public static let cfgIdentifier = "hextech.diagram.cfg"
    public static let flowIdentifier = "hextech.diagram.flow"
    public static let diagramsIdentifier = "hextech.diagram.diagrams"
    public static let swiftMapIdentifier = "hextech.diagram.swiftmap"
    public static let mindMapIdentifier = "hextech.diagram.mindmap"

    public static var allIdentifiers: [String] {
        [diagramsIdentifier, umlIdentifier, cfgIdentifier, flowIdentifier, swiftMapIdentifier, mindMapIdentifier]
    }
}
