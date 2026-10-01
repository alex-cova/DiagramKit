import AppKit
import SceneKit
import simd

/// Builds and mutates SceneKit content from a `DiagramScene3D`.
/// Positions use diagram world units directly (SceneKit Y-up).
@MainActor
public enum SceneKitDiagramHost {
    private static let nodesContainerName = "diagram.nodes"
    private static let edgesContainerName = "diagram.edges"
    private static let cameraName = "diagram.camera"
    private static let selectionGlowName = "diagram.selectionGlow"

    public struct BuiltScene {
        public let scene: SCNScene
        public let cameraNode: SCNNode?
        public init(
            scene: SCNScene,
            cameraNode: SCNNode? = nil
        ) {
            self.scene = scene
            self.cameraNode = cameraNode
        }
    }

    public static func buildScene(
        from diagram: DiagramScene3D,
        selection: Set<UUID>,
        isDarkAppearance: Bool,
        accent: CodableColor
    ) -> BuiltScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let nodesRoot = SCNNode()
        nodesRoot.name = nodesContainerName
        scene.rootNode.addChildNode(nodesRoot)

        let edgesRoot = SCNNode()
        edgesRoot.name = edgesContainerName
        scene.rootNode.addChildNode(edgesRoot)

        var minP = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for node in diagram.nodes {
            let level = nodeLevel(nodeID: node.id, diagram: diagram, selection: selection)
            nodesRoot.addChildNode(makeNodeBox(node, level: level, isDarkAppearance: isDarkAppearance, accent: accent))
            let p = node.position.simd
            minP = simd_min(minP, p)
            maxP = simd_max(maxP, p)
        }

        for edge in diagram.edges {
            edgesRoot.addChildNode(makeEdge(edge))
        }

        let camera = SCNNode()
        camera.name = cameraName
        camera.camera = SCNCamera()
        camera.camera?.zFar = 50_000
        camera.camera?.zNear = 1
        if diagram.nodes.isEmpty {
            camera.position = SCNVector3(0, 280, 640)
            camera.look(at: SCNVector3Zero)
        } else {
            let pose = defaultCameraPose(minBound: minP, maxBound: maxP)
            camera.position = SCNVector3(Double(pose.position.x), Double(pose.position.y), Double(pose.position.z))
            camera.look(at: SCNVector3(Double(pose.target.x), Double(pose.target.y), Double(pose.target.z)))
        }
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 850
        key.eulerAngles = SCNVector3(-0.55, 0.35, 0)
        scene.rootNode.addChildNode(key)

        return BuiltScene(scene: scene, cameraNode: camera)
    }

    /// Default orbit pose used on first build and for “1:1” reset.
    public static func defaultCameraPose(
        minBound: SIMD3<Float>,
        maxBound: SIMD3<Float>
    ) -> (position: SIMD3<Float>, target: SIMD3<Float>) {
        let center = (minBound + maxBound) * 0.5
        let extent = max(length(maxBound - minBound), 240)
        let position = SIMD3(
            center.x,
            center.y + extent * 0.55,
            center.z + extent * 1.25
        )
        return (position, center)
    }

    /// Axis-aligned bounds of diagram node centers (empty → nil).
    public static func contentBounds(of diagram: DiagramScene3D) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard !diagram.nodes.isEmpty else { return nil }
        var minP = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for node in diagram.nodes {
            let p = node.position.simd
            minP = simd_min(minP, p)
            maxP = simd_max(maxP, p)
        }
        return (minP, maxP)
    }

    /// Child nodes under the diagram nodes container (for `SCNCameraController.frameNodes`).
    public static func frameableNodes(in scene: SCNScene) -> [SCNNode] {
        scene.rootNode.childNode(withName: nodesContainerName, recursively: false)?.childNodes ?? []
    }

    public static func applySelection(
        _ selection: Set<UUID>,
        to root: SCNNode,
        scene: DiagramScene3D,
        isDarkAppearance: Bool,
        accent: CodableColor
    ) {
        guard let nodesRoot = root.childNode(withName: nodesContainerName, recursively: false) else { return }
        let byID = Dictionary(uniqueKeysWithValues: scene.nodes.map { ($0.id, $0) })
        for child in nodesRoot.childNodes {
            guard let name = child.name, let id = UUID(uuidString: name), let desc = byID[id] else { continue }
            let level = nodeLevel(nodeID: id, diagram: scene, selection: selection)
            child.childNode(withName: selectionGlowName, recursively: false)?.removeFromParentNode()
            if level == .selected {
                child.addChildNode(makeSelectionGlow(for: desc, accent: accent))
            }
            applyNodeMaterials(to: child, node: desc, level: level, isDarkAppearance: isDarkAppearance, accent: accent)
        }

        guard let edgesRoot = root.childNode(withName: edgesContainerName, recursively: false) else { return }
        edgesRoot.childNodes.forEach { $0.removeFromParentNode() }
        for edge in scene.edges {
            edgesRoot.addChildNode(makeEdge(edge))
        }
    }

    private static func nodeLevel(
        nodeID: UUID,
        diagram: DiagramScene3D,
        selection: Set<UUID>
    ) -> NodeHighlightLevel {
        let nodeIDs = Set(diagram.nodes.map(\.id))
        let edges = diagram.edges.map { ($0.sourceID, $0.destinationID) }
        return DiagramFocusResolver.nodeLevel(
            nodeID: nodeID,
            selection: selection,
            edges: edges,
            nodeIDs: nodeIDs
        )
    }

    private static func makeNodeBox(
        _ node: SceneNode3D,
        level: NodeHighlightLevel,
        isDarkAppearance: Bool,
        accent: CodableColor
    ) -> SCNNode {
        let width = max(node.size.width, 48)
        let height = max(node.size.height, 28)
        let depth = max(min(width, height) * 0.35, 18)
        let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 6)
        let material = SCNMaterial()
        applyNodeMaterials(material: material, node: node, level: level, isDarkAppearance: isDarkAppearance, accent: accent)
        box.firstMaterial = material

        let wrapper = SCNNode(geometry: box)
        wrapper.name = node.id.uuidString
        wrapper.position = SCNVector3(
            Double(node.position.x),
            Double(node.position.y),
            Double(node.position.z)
        )

        if !node.title.isEmpty {
            let labelColor = DiagramFocusResolver.adjustedLabelColor(
                fill: node.fill,
                level: level,
                isDark: isDarkAppearance
            )
            let text = SCNText(string: truncatedTitle(node.title), extrusionDepth: 1)
            text.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            text.flatness = 0.4
            let textMaterial = SCNMaterial()
            textMaterial.lightingModel = .constant
            textMaterial.diffuse.contents = nsColor(labelColor)
            text.firstMaterial = textMaterial
            let textNode = SCNNode(geometry: text)
            let (minB, maxB) = textNode.boundingBox
            let textWidth = maxB.x - minB.x
            let textHeight = maxB.y - minB.y
            let scale: CGFloat = min(0.9, (width * 0.85) / max(textWidth, 1))
            textNode.pivot = SCNMatrix4MakeTranslation(
                minB.x + textWidth / 2,
                minB.y + textHeight / 2,
                0
            )
            textNode.scale = SCNVector3(scale, scale, scale)
            textNode.position = SCNVector3(0, 0, depth / 2 + 1)
            wrapper.addChildNode(textNode)
        }

        if level == .selected {
            wrapper.addChildNode(makeSelectionGlow(for: node, accent: accent))
        }
        return wrapper
    }

    private static func applyNodeMaterials(
        to node: SCNNode,
        node desc: SceneNode3D,
        level: NodeHighlightLevel,
        isDarkAppearance: Bool,
        accent: CodableColor
    ) {
        guard let material = node.geometry?.firstMaterial else { return }
        applyNodeMaterials(
            material: material,
            node: desc,
            level: level,
            isDarkAppearance: isDarkAppearance,
            accent: accent
        )
        for child in node.childNodes {
            guard child.geometry is SCNText, let textMaterial = child.geometry?.firstMaterial else { continue }
            let labelColor = DiagramFocusResolver.adjustedLabelColor(
                fill: desc.fill,
                level: level,
                isDark: isDarkAppearance
            )
            textMaterial.lightingModel = .constant
            textMaterial.diffuse.contents = nsColor(labelColor)
        }
    }

    private static func applyNodeMaterials(
        material: SCNMaterial,
        node: SceneNode3D,
        level: NodeHighlightLevel,
        isDarkAppearance: Bool,
        accent: CodableColor
    ) {
        let fill = DiagramFocusResolver.adjustedColor(
            node.fill,
            level: level,
            isDark: isDarkAppearance
        )
        material.diffuse.contents = nsColor(fill)
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.transparency = 1
        material.writesToDepthBuffer = true
        switch level {
        case .selected:
            material.emission.contents = nsColor(accent, opacity: 0.35)
        case .connected:
            material.emission.contents = nsColor(accent, opacity: 0.18)
        case .normal, .dimmed:
            material.emission.contents = NSColor.black
        }
    }

    private static func makeSelectionGlow(for node: SceneNode3D, accent: CodableColor) -> SCNNode {
        let width = max(node.size.width, 48) * 1.1
        let height = max(node.size.height, 28) * 1.1
        let depth = max(min(width, height) * 0.35, 18) * 1.1
        let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 7)
        let material = SCNMaterial()
        material.diffuse.contents = nsColor(accent, opacity: 0.2)
        material.transparency = 0.55
        box.firstMaterial = material
        let glow = SCNNode(geometry: box)
        glow.name = selectionGlowName
        return glow
    }

    private static func makeEdge(_ edge: SceneEdge3D) -> SCNNode {
        let container = SCNNode()
        container.name = edge.id.uuidString

        switch edge.routing {
        case .straight:
            container.addChildNode(makeStraightSegment(
                from: edge.start.simd,
                to: edge.end.simd,
                stroke: edge.stroke,
                lineWidth: edge.lineWidth
            ))
        case .arc(let bulge):
            let points = ArcEdgeGeometry.sample3D(
                start: edge.start.simd,
                end: edge.end.simd,
                bulge: bulge
            )
            for i in 0..<(points.count - 1) {
                container.addChildNode(makeStraightSegment(
                    from: points[i],
                    to: points[i + 1],
                    stroke: edge.stroke,
                    lineWidth: edge.lineWidth
                ))
            }
        }
        return container
    }

    private static func makeStraightSegment(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        stroke: CodableColor,
        lineWidth: CGFloat
    ) -> SCNNode {
        let vector = end - start
        let distance = length(vector)
        guard distance > 1e-3 else { return SCNNode() }

        let radius = max(lineWidth * 0.6, 1.2)
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(distance))
        let material = SCNMaterial()
        material.diffuse.contents = nsColor(stroke)
        cylinder.firstMaterial = material

        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3(
            Double((start.x + end.x) / 2),
            Double((start.y + end.y) / 2),
            Double((start.z + end.z) / 2)
        )
        node.look(
            at: SCNVector3(Double(end.x), Double(end.y), Double(end.z)),
            up: SCNVector3(0, 1, 0),
            localFront: SCNVector3(0, 1, 0)
        )
        return node
    }

    private static func truncatedTitle(_ title: String) -> String {
        if title.count <= 28 { return title }
        return String(title.prefix(27)) + "…"
    }

    private static func nsColor(_ color: CodableColor) -> NSColor {
        NSColor(
            srgbRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.opacity
        )
    }

    /// Same conversion with the alpha overridden — used for emission/glow tints
    /// derived from `theme.accent` at a fixed opacity.
    private static func nsColor(_ color: CodableColor, opacity: Double) -> NSColor {
        NSColor(
            srgbRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: opacity
        )
    }
}
