import AppKit
import SwiftUI

/// Interaction callbacks for the shared canvas chrome (pan/zoom/marquee/move/resize).
@MainActor
public struct DiagramCanvasInteraction {
    public var isPanToolActive: Bool
    public var allowsMarqueeSelection: Bool
    public var selectedIDs: () -> Set<UUID>
    public var nodeFrames: () -> [NodeFrame]
    public var frame: (UUID) -> CGRect?
    public var hitTestNode: (CGPoint) -> UUID?
    public var hitTestEdge: (CGPoint) -> UUID?
    public var onSelect: (_ id: UUID?, _ additive: Bool) -> Void
    public var onMarqueeSelect: (_ ids: Set<UUID>, _ additive: Bool) -> Void
    public var onClearSelection: () -> Void
    public var onSetNodeFrames: (_ frames: [NodeFrame], _ registerUndo: Bool) -> Void
    public var onResizeNode: (_ id: UUID, _ frame: CGRect, _ registerUndo: Bool) -> Void
    public var onDeleteSelection: () -> Void
    public var canDeleteSelection: () -> Bool = { true }
    public var onTap: (_ worldPoint: CGPoint, _ shift: Bool) -> Void
    public var onEscape: () -> Void
    public var onHoverWorld: ((CGPoint) -> Void)?
    /// When false, primary drag does not start move/marquee/resize (domain tools handle placement).
    public var shouldHandleSelectDrag: Bool
    public var onCopy: (() -> Void)?
    public var onCut: (() -> Void)?
    public var onPaste: (() -> Void)?
    public var onSelectAll: (() -> Void)?
    public var onDuplicate: (() -> Void)?
    public var onBringToFront: (() -> Void)?
    public var onSendToBack: (() -> Void)?
    /// Called with world-space delta for arrow-key nudge.
    public var onNudge: ((CGSize) -> Void)?
    /// Base nudge step in world units (Shift multiplies by 10 in the canvas).
    public var nudgeStep: CGFloat
    /// Marquee hit-test (prefer spatial index for large graphs).
    public var intersectingNodes: (CGRect) -> Set<UUID>
    /// Ephemeral alignment guides while dragging (empty to clear).
    public var onGuidesChange: (([GuideLine]) -> Void)?
    /// Fires `true` when a node move drag begins and `false` when it ends, so node layers can
    /// suppress their per-node layout animation for the duration (see `DiagramSession.isDraggingNodes`).
    public var onDragStateChange: ((Bool) -> Void)? = nil
    public init(
        isPanToolActive: Bool,
        allowsMarqueeSelection: Bool,
        selectedIDs: @escaping () -> Set<UUID>,
        nodeFrames: @escaping () -> [NodeFrame],
        frame: @escaping (UUID) -> CGRect?,
        hitTestNode: @escaping (CGPoint) -> UUID?,
        hitTestEdge: @escaping (CGPoint) -> UUID?,
        onSelect: @escaping (_ id: UUID?, _ additive: Bool) -> Void,
        onMarqueeSelect: @escaping (_ ids: Set<UUID>, _ additive: Bool) -> Void,
        onClearSelection: @escaping () -> Void,
        onSetNodeFrames: @escaping (_ frames: [NodeFrame], _ registerUndo: Bool) -> Void,
        onResizeNode: @escaping (_ id: UUID, _ frame: CGRect, _ registerUndo: Bool) -> Void,
        onDeleteSelection: @escaping () -> Void,
        canDeleteSelection: @escaping () -> Bool = { true },
        onTap: @escaping (_ worldPoint: CGPoint, _ shift: Bool) -> Void,
        onEscape: @escaping () -> Void,
        onHoverWorld: ((CGPoint) -> Void)? = nil,
        shouldHandleSelectDrag: Bool,
        onCopy: (() -> Void)? = nil,
        onCut: (() -> Void)? = nil,
        onPaste: (() -> Void)? = nil,
        onSelectAll: (() -> Void)? = nil,
        onDuplicate: (() -> Void)? = nil,
        onBringToFront: (() -> Void)? = nil,
        onSendToBack: (() -> Void)? = nil,
        onNudge: ((CGSize) -> Void)? = nil,
        nudgeStep: CGFloat,
        intersectingNodes: @escaping (CGRect) -> Set<UUID>,
        onGuidesChange: (([GuideLine]) -> Void)? = nil,
        onDragStateChange: ((Bool) -> Void)? = nil
    ) {
        self.isPanToolActive = isPanToolActive
        self.allowsMarqueeSelection = allowsMarqueeSelection
        self.selectedIDs = selectedIDs
        self.nodeFrames = nodeFrames
        self.frame = frame
        self.hitTestNode = hitTestNode
        self.hitTestEdge = hitTestEdge
        self.onSelect = onSelect
        self.onMarqueeSelect = onMarqueeSelect
        self.onClearSelection = onClearSelection
        self.onSetNodeFrames = onSetNodeFrames
        self.onResizeNode = onResizeNode
        self.onDeleteSelection = onDeleteSelection
        self.canDeleteSelection = canDeleteSelection
        self.onTap = onTap
        self.onEscape = onEscape
        self.onHoverWorld = onHoverWorld
        self.shouldHandleSelectDrag = shouldHandleSelectDrag
        self.onCopy = onCopy
        self.onCut = onCut
        self.onPaste = onPaste
        self.onSelectAll = onSelectAll
        self.onDuplicate = onDuplicate
        self.onBringToFront = onBringToFront
        self.onSendToBack = onSendToBack
        self.onNudge = onNudge
        self.nudgeStep = nudgeStep
        self.intersectingNodes = intersectingNodes
        self.onGuidesChange = onGuidesChange
        self.onDragStateChange = onDragStateChange
    }
}

/// Infinite canvas chrome: grid, viewport gestures, selection marquee, move/resize.
/// Domain layers (nodes, edges, tools) are injected as content.
public struct DiagramCanvasView<Content: View>: View {
    @Binding public var viewport: ViewportState
    @Binding public var marqueeWorld: CGRect?
    public var canvas: CanvasSettings
    public var backgroundOverride: CodableColor? = nil
    public var selection: Set<UUID>
    public var interaction: DiagramCanvasInteraction
    public var guides: [GuideLine] = []
    public var contentBounds: CGRect? = nil
    public var onViewSizeChange: ((CGSize) -> Void)? = nil
    /// When true, selection changes from side panels reclaim canvas keyboard focus so Delete/nudge
    /// work. Keep false for tools with inline editors (e.g. Chalkboard text) that also mutate selection.
    public var claimsFocusOnSelectionChange: Bool = false
    @ViewBuilder public var content: () -> Content

    @State private var isSpaceDown = false
    @State private var dragMode: DragMode = .none
    @State private var dragStartWorld: CGPoint = .zero
    @State private var dragOriginFrames: [UUID: CGRect] = [:]
    /// Frames of the non-moving nodes, captured once when a move drag begins rather than
    /// recomputed (via `interaction.nodeFrames()` + filter + map — three O(n) allocations) on
    /// every gesture-change event. They can't change mid-drag since only the moving nodes move.
    @State private var dragOtherFrames: [CGRect] = []
    @State private var resizeStartFrame: CGRect = .zero
    @State private var resizeNodeID: UUID?
    @State private var lastDragTranslation: CGSize = .zero
    @State private var magnifyBaseZoom: CGFloat?
    @FocusState private var isCanvasFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private enum DragMode {
        case none
        case pan
        case move
        case marquee
        case resize
    }

    public var body: some View {
        GeometryReader { geo in
            let theme = canvas.resolvedTheme(forDarkAppearance: colorScheme == .dark)
            let visible = viewport.visibleWorldRect(viewSize: geo.size)
            let background = backgroundOverride ?? theme.canvasBackground
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(background.swiftUIColor)

                if canvas.showGrid {
                    gridLayer(size: geo.size, theme: theme)
                }

                content()

                if canvas.showGuides, !guides.isEmpty {
                    GuideOverlay(guides: guides, viewport: viewport)
                }

                SelectionOverlay(marquee: marqueeWorld, viewport: viewport, theme: theme)

                if canvas.showRulers {
                    RulerBars(viewport: viewport, viewSize: geo.size, theme: theme)
                }

                if canvas.showMiniMap {
                    MiniMapView(
                        contentBounds: contentBounds ?? visible,
                        nodes: interaction.nodeFrames(),
                        selectedIDs: selection,
                        visibleWorldRect: visible,
                        viewport: $viewport,
                        theme: theme
                    )
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .environment(\.visibleWorldRect, visible)
            .contentShape(Rectangle())
            .onAppear { onViewSizeChange?(geo.size) }
            .onChange(of: geo.size) { _, size in onViewSizeChange?(size) }
            .gesture(primaryDragGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(tapGesture)
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    interaction.onHoverWorld?(viewport.viewToWorld(location))
                }
            }
            .focusable()
            .focused($isCanvasFocused)
            .onChange(of: selection) { _, _ in
                guard claimsFocusOnSelectionChange else { return }
                // Selection can originate in the layers or inspector while another
                // control (e.g. an inspector TextField) still owns keyboard focus.
                isCanvasFocused = true
            }
            .onKeyPress(.delete) {
                guard interaction.canDeleteSelection() else { return .ignored }
                interaction.onDeleteSelection()
                return .handled
            }
            .onKeyPress(.escape) {
                interaction.onEscape()
                interaction.onGuidesChange?([])
                marqueeWorld = nil
                return .handled
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                guard interaction.onNudge != nil else { return .ignored }
                let step = interaction.nudgeStep * (press.modifiers.contains(.shift) ? 10 : 1)
                var dx: CGFloat = 0
                var dy: CGFloat = 0
                switch press.key {
                case .leftArrow: dx = -step
                case .rightArrow: dx = step
                case .upArrow: dy = -step
                case .downArrow: dy = step
                default: return .ignored
                }
                interaction.onNudge?(CGSize(width: dx, height: dy))
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "c")) { press in
                guard press.modifiers.contains(.command), let onCopy = interaction.onCopy else {
                    return .ignored
                }
                onCopy()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "x")) { press in
                guard press.modifiers.contains(.command), let onCut = interaction.onCut else {
                    return .ignored
                }
                onCut()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "v")) { press in
                guard press.modifiers.contains(.command), let onPaste = interaction.onPaste else {
                    return .ignored
                }
                onPaste()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "a")) { press in
                guard press.modifiers.contains(.command), let onSelectAll = interaction.onSelectAll else {
                    return .ignored
                }
                onSelectAll()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "d")) { press in
                guard press.modifiers.contains(.command), let onDuplicate = interaction.onDuplicate else {
                    return .ignored
                }
                onDuplicate()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "]")) { press in
                guard press.modifiers.contains([.command, .option]),
                      let onBringToFront = interaction.onBringToFront
                else { return .ignored }
                onBringToFront()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "[")) { press in
                guard press.modifiers.contains([.command, .option]),
                      let onSendToBack = interaction.onSendToBack
                else { return .ignored }
                onSendToBack()
                return .handled
            }
            .background(SpaceKeyMonitor(isSpaceDown: $isSpaceDown))
            .background(CanvasScrollMonitor(viewport: $viewport, viewSize: geo.size))
            .environment(\.diagramResolvedTheme, theme)
            .environment(\.diagramIsDarkAppearance, colorScheme == .dark)
        }
        .clipped()
        .onChange(of: colorScheme, initial: true) { _, scheme in
            DiagramAppearance.update(colorScheme: scheme)
        }
    }

    private func gridLayer(size: CGSize, theme: DiagramTheme) -> some View {
        // Hoisted out of the draw closure: one Color resolution per frame instead of one per
        // line (~575 at low zoom), and all lines become subpaths of a single `Path` stroked once.
        let color = theme.gridMinor.swiftUIColor
        return Canvas { context, _ in
            let bounds = CGRect(origin: .zero, size: size)
            let segments = GridRenderer.lines(
                viewBounds: bounds,
                viewport: viewport,
                gridSize: canvas.gridSize
            )
            guard !segments.isEmpty else { return }
            var path = Path()
            for (a, b) in segments {
                path.move(to: a)
                path.addLine(to: b)
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard dragMode == .none else { return }
                isCanvasFocused = true
                let shift = NSEvent.modifierFlags.contains(.shift)
                let world = viewport.viewToWorld(value.location)
                interaction.onTap(world, shift)
            }
    }

    private var primaryDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnifyBaseZoom == nil {
                    magnifyBaseZoom = viewport.zoom
                }
                guard let base = magnifyBaseZoom else { return }
                let target = base * value.magnification
                let factor = target / max(viewport.zoom, 0.001)
                viewport = viewport.zoom(by: factor, toward: value.startLocation)
            }
            .onEnded { _ in
                magnifyBaseZoom = nil
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        isCanvasFocused = true
        let world = viewport.viewToWorld(value.startLocation)
        let flags = NSEvent.modifierFlags
        let isPan = interaction.isPanToolActive || isSpaceDown

        if dragMode == .none {
            lastDragTranslation = .zero
            if isPan {
                dragMode = .pan
            } else if interaction.shouldHandleSelectDrag {
                if let nodeID = interaction.hitTestNode(world) {
                    let frame = interaction.frame(nodeID) ?? .zero
                    if selection.contains(nodeID),
                       CanvasEngine.hitTestResizeHandle(at: world, frame: frame, zoom: viewport.zoom)
                    {
                        dragMode = .resize
                        resizeNodeID = nodeID
                        resizeStartFrame = frame
                    } else {
                        if !interaction.selectedIDs().contains(nodeID) {
                            interaction.onSelect(nodeID, flags.contains(.shift))
                        }
                        dragMode = .move
                        interaction.onDragStateChange?(true)
                        let ids = interaction.selectedIDs()
                        let allFrames = interaction.nodeFrames()
                        let selectedFrames = allFrames.filter { ids.contains($0.id) }
                        dragOriginFrames = Dictionary(uniqueKeysWithValues: selectedFrames.map { ($0.id, $0.frame) })
                        if dragOriginFrames.isEmpty {
                            dragOriginFrames = [nodeID: frame]
                            interaction.onSelect(nodeID, false)
                        }
                        // Captured once for the whole drag — see `dragOtherFrames`.
                        let movingIDs = Set(dragOriginFrames.keys)
                        dragOtherFrames = allFrames.filter { !movingIDs.contains($0.id) }.map(\.frame)
                    }
                } else if interaction.allowsMarqueeSelection, flags.contains(.option) {
                    // ⌥-drag preserves marquee; plain empty drag pans the viewport.
                    dragMode = .marquee
                    dragStartWorld = world
                    if !flags.contains(.shift) {
                        interaction.onClearSelection()
                    }
                } else {
                    dragMode = .pan
                }
            } else {
                interaction.onHoverWorld?(viewport.viewToWorld(value.location))
                return
            }
        }

        switch dragMode {
        case .pan:
            let delta = CGSize(
                width: value.translation.width - lastDragTranslation.width,
                height: value.translation.height - lastDragTranslation.height
            )
            viewport = viewport.pan(by: delta)
            lastDragTranslation = value.translation
        case .move:
            let worldDelta = CGSize(
                width: value.translation.width / viewport.zoom,
                height: value.translation.height / viewport.zoom
            )
            let others = dragOtherFrames
            var frames: [NodeFrame] = []
            var guides: [GuideLine] = []
            for (id, origin) in dragOriginFrames {
                var next = origin.offsetBy(dx: worldDelta.width, dy: worldDelta.height)
                if canvas.snapEnabled {
                    next.origin = SnapEngine.snap(next.origin, grid: canvas.gridSize)
                }
                if canvas.showGuides, !others.isEmpty {
                    let snapped = SnapEngine.snapFrame(next, to: others)
                    next = snapped.frame
                    guides.append(contentsOf: snapped.guides)
                }
                frames.append(NodeFrame(id: id, frame: next))
            }
            interaction.onSetNodeFrames(frames, false)
            interaction.onGuidesChange?(guides)
        case .marquee:
            let current = viewport.viewToWorld(value.location)
            marqueeWorld = CGRect(
                x: min(dragStartWorld.x, current.x),
                y: min(dragStartWorld.y, current.y),
                width: abs(current.x - dragStartWorld.x),
                height: abs(current.y - dragStartWorld.y)
            )
        case .resize:
            handleResizeDrag(nodeID: resizeNodeID, translation: value.translation)
        case .none:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        switch dragMode {
        case .marquee:
            if let marquee = marqueeWorld {
                let hits = interaction.intersectingNodes(marquee)
                interaction.onMarqueeSelect(hits, NSEvent.modifierFlags.contains(.shift))
            }
            marqueeWorld = nil
        case .move:
            commitMove()
            interaction.onGuidesChange?([])
            interaction.onDragStateChange?(false)
        case .resize:
            commitResize()
        case .pan, .none:
            break
        }
        dragMode = .none
        dragOriginFrames = [:]
        dragOtherFrames = []
        resizeNodeID = nil
        lastDragTranslation = .zero
    }

    private func commitMove() {
        let origins = dragOriginFrames
        guard !origins.isEmpty else { return }
        let finals: [NodeFrame] = interaction.nodeFrames().compactMap { item in
            guard origins[item.id] != nil else { return nil }
            return item
        }
        interaction.onSetNodeFrames(origins.map { NodeFrame(id: $0.key, frame: $0.value) }, false)
        interaction.onSetNodeFrames(finals, true)
    }

    private func handleResizeDrag(nodeID: UUID?, translation: CGSize) {
        guard let nodeID else { return }
        if resizeNodeID != nodeID {
            resizeNodeID = nodeID
            resizeStartFrame = interaction.frame(nodeID) ?? .zero
            dragMode = .resize
        }
        var size = CGSize(
            width: resizeStartFrame.width + translation.width / viewport.zoom,
            height: resizeStartFrame.height + translation.height / viewport.zoom
        )
        size = CanvasEngine.clampMinSize(size)
        if canvas.snapEnabled {
            size = SnapEngine.snapSize(size, grid: canvas.gridSize)
        }
        let frame = CGRect(origin: resizeStartFrame.origin, size: size)
        interaction.onResizeNode(nodeID, frame, false)
    }

    private func commitResize() {
        guard let nodeID = resizeNodeID else { return }
        let final = interaction.frame(nodeID) ?? resizeStartFrame
        interaction.onResizeNode(nodeID, resizeStartFrame, false)
        interaction.onResizeNode(nodeID, final, true)
        resizeNodeID = nil
    }
    public init(
        viewport: Binding<ViewportState>,
        marqueeWorld: Binding<CGRect?>,
        canvas: CanvasSettings,
        backgroundOverride: CodableColor? = nil,
        selection: Set<UUID>,
        interaction: DiagramCanvasInteraction,
        guides: [GuideLine] = [],
        contentBounds: CGRect? = nil,
        onViewSizeChange: ((CGSize) -> Void)? = nil,
        claimsFocusOnSelectionChange: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._viewport = viewport
        self._marqueeWorld = marqueeWorld
        self.canvas = canvas
        self.backgroundOverride = backgroundOverride
        self.selection = selection
        self.interaction = interaction
        self.guides = guides
        self.contentBounds = contentBounds
        self.onViewSizeChange = onViewSizeChange
        self.claimsFocusOnSelectionChange = claimsFocusOnSelectionChange
        self.content = content
    }
}

public struct SpaceKeyMonitor: NSViewRepresentable {
    @Binding public var isSpaceDown: Bool

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.isSpaceDown = $isSpaceDown
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak coordinator = context.coordinator] event in
            guard event.keyCode == 49 else { return event }
            if let first = NSApp.keyWindow?.firstResponder, first is NSTextView {
                return event
            }
            DispatchQueue.main.async {
                coordinator?.isSpaceDown?.wrappedValue = (event.type == .keyDown)
            }
            return event.type == .keyDown ? nil : event
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isSpaceDown = $isSpaceDown
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        .zero
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        public var monitor: Any?
        public var isSpaceDown: Binding<Bool>?
    }
    public init(isSpaceDown: Binding<Bool>) {
        self._isSpaceDown = isSpaceDown
    }
}

/// Captures right-clicks over the canvas and reports the world-space point, so context menus can
/// hit-test accurately even when `onContinuousHover` hasn't fired yet (common on a cold right-click).
public struct CanvasRightClickMonitor: NSViewRepresentable {
    public var viewport: ViewportState
    public let onRightClick: (CGPoint) -> Void

    public func makeNSView(context: Context) -> NSView {
        let view = PassThroughMonitorView()
        context.coordinator.install(viewport: viewport, onRightClick: onRightClick)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.viewport = viewport
        context.coordinator.onRightClick = onRightClick
        context.coordinator.hostView = nsView
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        // Match the canvas so `bounds.contains` can filter right-clicks; hit-testing is disabled
        // via `PassThroughMonitorView` so the filled frame does not steal gestures.
        proposal.replacingUnspecifiedDimensions()
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        public var viewport: ViewportState = .default
        public var onRightClick: ((CGPoint) -> Void)?
        public weak var hostView: NSView?
        private var monitor: Any?

        public func install(viewport: ViewportState, onRightClick: @escaping (CGPoint) -> Void) {
            self.viewport = viewport
            self.onRightClick = onRightClick
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self,
                      let host = self.hostView,
                      let window = host.window,
                      event.windowNumber == window.windowNumber
                else { return event }

                let local: CGPoint
                if host.superview != nil {
                    local = host.convert(event.locationInWindow, from: nil)
                } else {
                    local = event.locationInWindow
                }
                guard host.bounds.contains(local) else { return event }

                let world = self.viewport.viewToWorld(local)
                // Update before SwiftUI evaluates the context-menu builder. If
                // this is deferred, the menu is built with the previous point
                // and the node-specific Delete action is missing.
                self.onRightClick?(world)
                return event
            }
        }

        public func tearDown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
    public init(
        viewport: ViewportState,
        onRightClick: @escaping (CGPoint) -> Void
    ) {
        self.viewport = viewport
        self.onRightClick = onRightClick
    }
}

/// Fills the canvas for right-click bounds filtering without claiming AppKit hit tests
/// from the SwiftUI canvas above. `isFlipped` matches SwiftUI's top-left space so
/// `viewToWorld` receives the same coordinates as canvas gestures.
private final class PassThroughMonitorView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// ⌘-scroll zoom for the diagram canvas, expressed in terms of the shared `ScrollWheelZoomCatcher`.
public struct CanvasScrollMonitor: View {
    @Binding public var viewport: ViewportState
    public var viewSize: CGSize

    public var body: some View {
        ScrollWheelZoomCatcher { factor, point in
            viewport = viewport.zoom(by: factor, toward: point)
        }
    }
    public init(
        viewport: Binding<ViewportState>,
        viewSize: CGSize
    ) {
        self._viewport = viewport
        self.viewSize = viewSize
    }
}
