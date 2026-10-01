import AppKit
import SceneKit
import SwiftUI
import simd

@MainActor
public final class DiagramSCNView: SCNView {
    public var scrollWheelHandler: ((NSEvent) -> Void)?
    public var magnifyHandler: ((NSEvent) -> Void)?
    public var onCameraZoomChanged: (() -> Void)?

    public override func scrollWheel(with event: NSEvent) {
        if let scrollWheelHandler {
            scrollWheelHandler(event)
            return
        }
        super.scrollWheel(with: event)
        onCameraZoomChanged?()
    }

    public override func magnify(with event: NSEvent) {
        if let magnifyHandler {
            magnifyHandler(event)
            return
        }
        super.magnify(with: event)
        onCameraZoomChanged?()
    }
}

/// Hosts an `SCNView` for DiagramKit 3D scenes: orbit camera, hit-test selection, boxed nodes,
/// and cylinder edges. Structural edits stay in the SwiftUI chrome; this view is presentational
/// plus selection.
public struct SceneKitDiagramView: NSViewRepresentable {
    public var scene: DiagramScene3D
    public var selection: Set<UUID>
    public var background: CodableColor
    public var onSelect: (UUID?, Bool) -> Void
    /// Optional toolbar bridge for zoom / center / fit / 1:1.
    public var cameraBridge: SceneKitCameraBridge?
    public var navigationMode: SceneKitNavigationMode = .orbit
    public var isDarkAppearance: Bool = false
    public var accent: CodableColor

    public func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, cameraBridge: cameraBridge)
    }

    public func makeNSView(context: Context) -> SCNView {
        let view = DiagramSCNView(frame: .zero)
        view.backgroundColor = NSColor(cgColor: background.cgColor) ?? .windowBackgroundColor
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.scene = SCNScene()

        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        click.numberOfClicksRequired = 1
        view.addGestureRecognizer(click)

        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.buttonMask = 0x1
        view.addGestureRecognizer(pan)
        context.coordinator.panGesture = pan

        context.coordinator.scnView = view
        context.coordinator.applyNavigationMode(navigationMode, to: view)
        context.coordinator.rebuild(
            scene: scene,
            selection: selection,
            background: background,
            isDarkAppearance: isDarkAppearance,
            accent: accent
        )
        return view
    }

    public func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.cameraBridge = cameraBridge
        context.coordinator.scnView = view
        context.coordinator.applyNavigationMode(navigationMode, to: view)
        context.coordinator.rebuild(
            scene: scene,
            selection: selection,
            background: background,
            isDarkAppearance: isDarkAppearance,
            accent: accent
        )
    }

    public static func dismantleNSView(_ nsView: SCNView, coordinator: Coordinator) {
        coordinator.cameraBridge?.detach()
    }

    @MainActor
    public final class Coordinator: NSObject {
        public var onSelect: (UUID?, Bool) -> Void
        public var cameraBridge: SceneKitCameraBridge?
        public weak var scnView: SCNView?
        public weak var panGesture: NSPanGestureRecognizer?
        private var navigationMode: SceneKitNavigationMode = .orbit
        private var lastFingerprint: UInt64 = .max
        private var lastSelection: Set<UUID> = []
        private var lastBackground: CodableColor?
        private var lastIsDarkAppearance: Bool?
        private var lastAccent: CodableColor?
        private var lastDiagram: DiagramScene3D = .empty

        public init(onSelect: @escaping (UUID?, Bool) -> Void, cameraBridge: SceneKitCameraBridge? = nil) {
            self.onSelect = onSelect
            self.cameraBridge = cameraBridge
        }

        public func applyNavigationMode(_ mode: SceneKitNavigationMode, to view: SCNView) {
            navigationMode = mode
            let diagramView = view as? DiagramSCNView
            diagramView?.onCameraZoomChanged = { [weak self] in
                self?.cameraBridge?.syncZoomPercent()
            }
            switch mode {
            case .orbit:
                view.allowsCameraControl = true
                panGesture?.isEnabled = false
                diagramView?.scrollWheelHandler = nil
                diagramView?.magnifyHandler = nil
            case .pan:
                view.allowsCameraControl = false
                panGesture?.isEnabled = true
                diagramView?.scrollWheelHandler = { [weak self] event in
                    self?.handleScrollWheel(event)
                }
                diagramView?.magnifyHandler = { [weak self] event in
                    self?.handleMagnify(event)
                }
            }
        }

        public func rebuild(
            scene: DiagramScene3D,
            selection: Set<UUID>,
            background: CodableColor,
            isDarkAppearance: Bool,
            accent: CodableColor
        ) {
            guard let view = scnView else { return }
            if lastBackground != background {
                view.backgroundColor = NSColor(cgColor: background.cgColor) ?? .windowBackgroundColor
                lastBackground = background
            }

            let geometryChanged = scene.fingerprint != lastFingerprint
            let selectionChanged = selection != lastSelection
            let appearanceChanged = lastIsDarkAppearance != isDarkAppearance
            let accentChanged = lastAccent != accent
            guard geometryChanged || selectionChanged || appearanceChanged || accentChanged else { return }

            if geometryChanged {
                let built = SceneKitDiagramHost.buildScene(
                    from: scene,
                    selection: selection,
                    isDarkAppearance: isDarkAppearance,
                    accent: accent
                )
                view.scene = built.scene
                if let camera = built.cameraNode {
                    view.pointOfView = camera
                    if let bounds = SceneKitDiagramHost.contentBounds(of: scene) {
                        view.defaultCameraController.target = SCNVector3(
                            Double(bounds.min.x + bounds.max.x) * 0.5,
                            Double(bounds.min.y + bounds.max.y) * 0.5,
                            Double(bounds.min.z + bounds.max.z) * 0.5
                        )
                    }
                }
                lastFingerprint = scene.fingerprint
                lastDiagram = scene
                if let bounds = SceneKitDiagramHost.contentBounds(of: scene) {
                    cameraBridge?.attach(view: view, minBound: bounds.min, maxBound: bounds.max)
                } else {
                    cameraBridge?.detach()
                }
            } else if selectionChanged || appearanceChanged || accentChanged, let root = view.scene?.rootNode {
                SceneKitDiagramHost.applySelection(
                    selection,
                    to: root,
                    scene: lastDiagram,
                    isDarkAppearance: isDarkAppearance,
                    accent: accent
                )
            }
            lastSelection = selection
            lastIsDarkAppearance = isDarkAppearance
            lastAccent = accent
        }

        @objc public func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard navigationMode == .pan,
                  let view = scnView,
                  let pov = view.pointOfView else { return }

            let translation = gesture.translation(in: view)
            guard translation != .zero else { return }
            gesture.setTranslation(.zero, in: view)

            let controller = view.defaultCameraController
            var target = SIMD3<Float>(
                Float(controller.target.x),
                Float(controller.target.y),
                Float(controller.target.z)
            )
            var position = pov.simdWorldPosition

            let transform = pov.simdWorldTransform
            var right = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
            var up = SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
            right = simd_normalize(right)
            up = simd_normalize(up)

            let distance = simd_length(position - target)
            let scale = max(distance * 0.0018, 0.75)
            let dx = Float(translation.x) * scale
            let dy = Float(translation.y) * scale
            let offset = right * -dx + up * dy

            target += offset
            position += offset

            controller.target = SCNVector3(Double(target.x), Double(target.y), Double(target.z))
            pov.simdWorldPosition = position
            pov.look(at: controller.target)
        }

        public func handleScrollWheel(_ event: NSEvent) {
            applyZoom(factor: SceneKitCameraZoom.factor(for: event))
        }

        public func handleMagnify(_ event: NSEvent) {
            applyZoom(factor: SceneKitCameraZoom.factor(forMagnify: event))
        }

        private func applyZoom(factor: CGFloat) {
            guard navigationMode == .pan, let view = scnView else { return }
            if let cameraBridge {
                cameraBridge.scrollZoom(by: factor)
            } else if SceneKitCameraZoom.apply(factor: factor, in: view, referenceDistance: nil) {
                cameraBridge?.syncZoomPercent()
            }
        }

        @objc public func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = scnView, gesture.view === view else { return }
            let location = gesture.location(in: view)
            let hits = view.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
            ])
            let shift = NSEvent.modifierFlags.contains(.shift)
            if let node = hits.first?.node {
                if let id = uuid(from: node) {
                    onSelect(id, shift)
                    return
                }
            }
            onSelect(nil, shift)
        }

        private func uuid(from node: SCNNode) -> UUID? {
            var current: SCNNode? = node
            while let candidate = current {
                if let name = candidate.name, let id = UUID(uuidString: name) {
                    return id
                }
                current = candidate.parent
            }
            return nil
        }
    }
    public init(
        scene: DiagramScene3D,
        selection: Set<UUID>,
        background: CodableColor,
        onSelect: @escaping (UUID?, Bool) -> Void,
        cameraBridge: SceneKitCameraBridge? = nil,
        navigationMode: SceneKitNavigationMode = .orbit,
        isDarkAppearance: Bool = false,
        accent: CodableColor
    ) {
        self.scene = scene
        self.selection = selection
        self.background = background
        self.onSelect = onSelect
        self.cameraBridge = cameraBridge
        self.navigationMode = navigationMode
        self.isDarkAppearance = isDarkAppearance
        self.accent = accent
    }
}
