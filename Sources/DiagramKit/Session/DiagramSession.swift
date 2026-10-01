import AppKit
import Foundation
import Observation
import SwiftUI

/// Shared diagram host: selection, viewport, undo, clipboard, spatial index, edge-route cache.
@MainActor
@Observable
public class DiagramSession<Document: MutableDiagramDocument>
where Document: Sendable & Equatable,
      Document.Node: Sendable & ClipboardPasteableNode,
      Document.Edge: Sendable & ClipboardPasteableEdge {
    public private(set) var document: Document
    public private(set) var fileURL: URL?
    public private(set) var isDirty: Bool = false
    public var selection: Set<UUID> = []
    public var viewport: ViewportState = .default
    /// Last canvas `GeometryReader` size; used by toolbar zoom / fit actions.
    public var canvasViewSize: CGSize = CGSize(width: 800, height: 600)
    public var marqueeWorld: CGRect?
    public var errorMessage: String?
    /// Ephemeral alignment guides shown while dragging.
    public var activeGuides: [GuideLine] = []
    /// True for the duration of a node move drag. Node layers read this to suppress the
    /// per-node layout animation while it's set — otherwise each moving node restarts a 0.35s
    /// easeInOut on every gesture-change event, which fights the drag instead of following it.
    public private(set) var isDraggingNodes = false

    public private(set) var isUndoGrouping = false
    public let undoManager = UndoManager()
    public private(set) var undoGeneration: Int = 0

    @ObservationIgnored
    private var clipboard: DiagramClipboardPayload<Document.Node, Document.Edge>?
    @ObservationIgnored
    private var spatialIndex = SpatialIndex(cellSize: 256)
    @ObservationIgnored
    private var spatialFingerprint: UInt64 = 0
    @ObservationIgnored
    private var edgeRouteCache = EdgeRouteCache()
    @ObservationIgnored
    public let routing: DiagramRoutingProvider<Document>
    @ObservationIgnored
    public private(set) var drawnEdgeCache: [UUID: CachedDrawnEdge] = [:]
    @ObservationIgnored
    public private(set) var dirtyNodeIDs: Set<UUID> = []
    @ObservationIgnored
    private var lastScene: DiagramScene = .empty
    /// Bumped on every `document` mutation (`applyEdit`, `replaceDocument`). Lets
    /// `currentFingerprint()` skip `routing.fingerprint(document)` — an O(nodes+edges) hash with
    /// its own array allocations — on frames where nothing but the viewport changed, which is
    /// the common case while panning/zooming since `cachedEdgeRoutes()` and `ensureSpatialIndex()`
    /// are called unconditionally from view bodies every such frame.
    @ObservationIgnored
    private var documentVersion: UInt64 = 0
    @ObservationIgnored
    private var cachedFingerprint: (version: UInt64, value: UInt64)?

    public init(document: Document, routing: DiagramRoutingProvider<Document>) {
        self.document = document
        self.routing = routing
        undoManager.levelsOfUndo = 100
    }

    public var hasSelection: Bool { !selection.isEmpty }

    public var selectedNodeFrames: [NodeFrame] {
        document.nodes
            .filter { selection.contains($0.id) }
            .map { NodeFrame(id: $0.id, frame: $0.frame) }
    }

    public var selectedNodeCount: Int {
        document.nodes.count(where: { selection.contains($0.id) })
    }

    public var canPaste: Bool { clipboard != nil }

    // MARK: - Commands

    public func applyEdit(_ command: EditCommand<Document>, registerUndo: Bool = true) {
        // `before` is just a reference copy (COW) — cheap regardless of `registerUndo`, and
        // `noteGeometryEdit` needs it below to compute a moved node's swept path. What's actually
        // expensive is `command.inverse(before:)` itself — for `.setNodeFrames` it does an O(k·n)
        // `document.nodes.first(where:)` scan per listed frame — so that part alone is skipped
        // when the result will never be registered, which is the common in-flight drag/resize case.
        let before = document
        let inverse = registerUndo ? command.inverse(before: before) : nil
        command.apply(to: &document)
        documentVersion &+= 1
        isDirty = true
        noteGeometryEdit(command, before: before)
        if command.canOrphanSelection {
            pruneSelection()
        }
        guard registerUndo, let inverse else { return }

        undoManager.registerUndo(withTarget: self) { session in
            session.applyEdit(inverse, registerUndo: true)
        }
        undoGeneration &+= 1
    }

    private func noteGeometryEdit(_ command: EditCommand<Document>, before: Document) {
        if command.requiresFullGeometryRebuild {
            invalidateGeometryCaches()
            dirtyNodeIDs = Set(document.nodes.map(\.id))
            return
        }
        let affected = command.affectedNodeIDs
        if !affected.isEmpty {
            dirtyNodeIDs.formUnion(affected)
            // Drop drawn cache entries for edges incident to dirty nodes.
            let incident = document.edges.filter {
                affected.contains($0.sourceID) || affected.contains($0.destinationID)
            }.map(\.id)
            for id in incident {
                drawnEdgeCache.removeValue(forKey: id)
            }
            evictAffectedRoutes(movedNodeIDs: affected, before: before)
            spatialFingerprint = 0
        }
    }

    /// Drops only the routes a geometry edit could plausibly have changed, instead of the whole
    /// cache. Needs `before` (pre-edit node frames) to compute the moved nodes' swept path for
    /// obstacle-avoidance eviction; when undo wasn't requested `applyEdit` doesn't snapshot one,
    /// so this falls back to a full invalidate in that case (registerUndo: false is itself the
    /// common drag-delta path, which still benefits from `routing.computeRoutesSubset` below via
    /// `cachedEdgeRoutes()`'s own fingerprint-vs-missing check — a full invalidate here just means
    /// the *next* call recomputes everything once, not on every event).
    private func evictAffectedRoutes(movedNodeIDs: Set<UUID>, before: Document?) {
        guard routing.computeRoutesSubset != nil, let before else {
            edgeRouteCache.invalidate()
            return
        }
        let beforeFrames = Dictionary(uniqueKeysWithValues: before.nodes.map { ($0.id, $0.frame) })
        let afterFrames = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0.frame) })
        let edgeTriples = document.edges.map { (id: $0.id, source: $0.sourceID, destination: $0.destinationID) }
        let toEvict = EdgeRouteCache.edgesNeedingReroute(
            movedNodeIDs: movedNodeIDs,
            beforeFrames: beforeFrames,
            afterFrames: afterFrames,
            edges: edgeTriples,
            routeBoxes: { edgeRouteCache.route(id: $0)?.boundingBox },
            avoidObstacles: document.canvas.avoidObstacles
        )
        edgeRouteCache.evict(toEvict)
    }

    public func beginUndoGrouping() {
        guard !isUndoGrouping else { return }
        undoManager.beginUndoGrouping()
        isUndoGrouping = true
    }

    public func endUndoGrouping() {
        guard isUndoGrouping else { return }
        undoManager.endUndoGrouping()
        isUndoGrouping = false
        undoGeneration &+= 1
    }

    public func undo() {
        endUndoGrouping()
        undoManager.undo()
        undoGeneration &+= 1
    }

    public func redo() {
        endUndoGrouping()
        undoManager.redo()
        undoGeneration &+= 1
    }

    // MARK: - Document I/O helpers

    public func replaceDocument(_ next: Document, fileURL: URL? = nil, markDirty: Bool = false) {
        endUndoGrouping()
        document = next
        documentVersion &+= 1
        self.fileURL = fileURL
        isDirty = markDirty
        selection = []
        marqueeWorld = nil
        activeGuides = []
        undoManager.removeAllActions()
        invalidateGeometryCaches()
    }

    public func markSaved(fileURL: URL) {
        self.fileURL = fileURL
        isDirty = false
    }

    /// Apply a domain-level document rewrite with undo support.
    public func replaceDocumentWithUndo(_ next: Document, registerUndo: Bool = true) {
        applyEdit(.replaceDocument(next), registerUndo: registerUndo)
    }

    public func bumpUndoGeneration() {
        undoGeneration &+= 1
    }

    // MARK: - Editing

    public func deleteSelection() {
        guard !selection.isEmpty else { return }
        let nodeIDs = Set(document.nodes.map(\.id)).intersection(selection)
        let edgeIDs = Set(document.edges.map(\.id)).intersection(selection)
        applyEdit(.deleteElements(nodeIDs: nodeIDs, edgeIDs: edgeIDs))
        selection = []
    }

    public func bringSelectionToFront() {
        bringNodesToFront(Set(document.nodes.map(\.id)).intersection(selection))
    }

    public func sendSelectionToBack() {
        sendNodesToBack(Set(document.nodes.map(\.id)).intersection(selection))
    }

    public func bringNodesToFront(_ nodeIDs: Set<UUID>) {
        reorderNodes(nodeIDs, toFront: true)
    }

    public func sendNodesToBack(_ nodeIDs: Set<UUID>) {
        reorderNodes(nodeIDs, toFront: false)
    }

    public func alignSelection(_ edge: AlignmentEdge) {
        let frames = selectedNodeFrames
        guard frames.count >= 2 else { return }
        applyEdit(.setNodeFrames(AlignmentEngine.align(frames, edge: edge)))
    }

    public func distributeSelection(_ axis: DistributionAxis) {
        let frames = selectedNodeFrames
        guard frames.count >= 3 else { return }
        applyEdit(.setNodeFrames(AlignmentEngine.distribute(frames, axis: axis)))
    }

    public func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        let frames = selectedNodeFrames
        guard !frames.isEmpty else { return }
        applyEdit(.setNodeFrames(AlignmentEngine.nudge(frames, offset: CGSize(width: dx, height: dy))))
    }

    private func reorderNodes(_ nodeIDs: Set<UUID>, toFront: Bool) {
        guard !nodeIDs.isEmpty else { return }

        let currentIDs = document.nodes.map(\.id)
        let moving = document.nodes.filter { nodeIDs.contains($0.id) }.map(\.id)
        let staying = document.nodes.filter { !nodeIDs.contains($0.id) }.map(\.id)
        let reorderedIDs = toFront ? staying + moving : moving + staying
        guard currentIDs != reorderedIDs else { return }

        let command: EditCommand<Document> = toFront
            ? .bringNodesToFront(nodeIDs: nodeIDs)
            : .sendNodesToBack(nodeIDs: nodeIDs)
        applyEdit(command)
    }

    public func autoLayout(_ algorithm: some LayoutAlgorithm) {
        guard !document.nodes.isEmpty else { return }
        let frames = document.nodes.map { NodeFrame(id: $0.id, frame: $0.frame) }
        let edges = document.edges.map { (source: $0.sourceID, destination: $0.destinationID) }
        let graph = LayoutGraph(nodes: frames, edges: edges)
        let laidOut = algorithm.layout(graph, options: LayoutOptions())
        DiagramAnimation.layout(enabled: document.canvas.animateLayout) {
            self.applyEdit(.setNodeFrames(laidOut))
        }
    }

    public func autoLayoutIncremental(_ algorithm: some LayoutAlgorithm, changedIDs: Set<UUID>) {
        guard !document.nodes.isEmpty else { return }
        let frames = document.nodes.map { NodeFrame(id: $0.id, frame: $0.frame) }
        let edges = document.edges.map { (source: $0.sourceID, destination: $0.destinationID) }
        let graph = LayoutGraph(nodes: frames, edges: edges)
        let laidOut = algorithm.layout(graph, changedIDs: changedIDs, prior: frames, options: LayoutOptions())
        DiagramAnimation.layout(enabled: document.canvas.animateLayout) {
            self.applyEdit(.setNodeFrames(laidOut))
        }
    }

    public func copySelection() {
        clipboard = DiagramClipboard.slice(
            nodes: document.nodes,
            edges: document.edges,
            selectedIDs: selection
        )
    }

    public func cutSelection() {
        copySelection()
        guard clipboard != nil else { return }
        deleteSelection()
    }

    public func duplicateSelection() {
        duplicate(nodes: Set(document.nodes.map(\.id)).intersection(selection))
    }

    public func duplicate(nodes nodeIDs: Set<UUID>) {
        guard let payload = DiagramClipboard.slice(
            nodes: document.nodes,
            edges: document.edges,
            selectedIDs: nodeIDs
        ) else { return }
        let step = max(1, document.canvas.gridSize) * 2
        let pasted = DiagramClipboard.paste(
            payload: payload,
            offset: CGSize(width: step, height: step)
        )
        beginUndoGrouping()
        for node in pasted.nodes {
            applyEdit(.addNode(node))
        }
        for edge in pasted.edges {
            applyEdit(.addEdge(edge))
        }
        endUndoGrouping()
        selection = pasted.newSelection
    }

    public func pasteClipboard() {
        let step = max(1, document.canvas.gridSize) * 2
        pasteClipboard(offset: CGSize(width: step, height: step))
    }

    public func pasteClipboard(at worldPoint: CGPoint) {
        guard let clipboard, !clipboard.nodes.isEmpty else { return }
        let frames = clipboard.nodes.map(\.frame)
        let bounds = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let offset = CGSize(
            width: worldPoint.x - bounds.midX,
            height: worldPoint.y - bounds.midY
        )
        pasteClipboard(offset: offset)
    }

    public func pasteClipboard(offset: CGSize) {
        guard let clipboard else { return }
        let pasted = DiagramClipboard.paste(payload: clipboard, offset: offset)
        beginUndoGrouping()
        for node in pasted.nodes {
            applyEdit(.addNode(node))
        }
        for edge in pasted.edges {
            applyEdit(.addEdge(edge))
        }
        endUndoGrouping()
        selection = pasted.newSelection
    }

    public func selectOnly(_ id: UUID?, additive: Bool = false) {
        guard let id else {
            if !additive { selection = [] }
            return
        }
        if additive {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } else {
            selection = [id]
        }
    }

    public func selectAll() {
        selection = Set(document.nodes.map(\.id)).union(document.edges.map(\.id))
    }

    public func hitTestNode(at worldPoint: CGPoint) -> UUID? {
        CanvasEngine.hitTestNode(at: worldPoint, index: ensureSpatialIndex())
    }

    public func nodesIntersecting(marquee: CGRect) -> Set<UUID> {
        CanvasEngine.nodesIntersecting(marquee: marquee, index: ensureSpatialIndex())
    }

    public func hitTestEdge(at worldPoint: CGPoint) -> UUID? {
        CanvasEngine.hitTestEdge(
            at: worldPoint,
            routes: cachedEdgeRoutes(),
            zoom: viewport.zoom
        )
    }

    /// `routing.fingerprint(document)`, memoized against `documentVersion` — see its doc comment.
    private func currentFingerprint() -> UInt64 {
        if let cachedFingerprint, cachedFingerprint.version == documentVersion {
            return cachedFingerprint.value
        }
        let value = routing.fingerprint(document)
        cachedFingerprint = (documentVersion, value)
        return value
    }

    public func cachedEdgeRoutes() -> [(id: UUID, route: EdgeRoute)] {
        let fingerprint = currentFingerprint()
        if let computeSubset = routing.computeRoutesSubset {
            return edgeRouteCache.patch(
                fingerprint: fingerprint,
                order: document.edges.map(\.id)
            ) { missing in
                computeSubset(document, missing)
            }
        }
        return edgeRouteCache.routes(fingerprint: fingerprint) {
            routing.computeRoutes(document)
        }
    }

    /// Store / reuse drawn edge paint data (markers already expanded).
    public func cachedDrawnEdge(id: UUID, build: () -> CachedDrawnEdge) -> CachedDrawnEdge {
        if let cached = drawnEdgeCache[id] {
            return cached
        }
        let value = build()
        drawnEdgeCache[id] = value
        return value
    }

    public func takeDirtyNodeIDs() -> Set<UUID> {
        let ids = dirtyNodeIDs
        dirtyNodeIDs = []
        return ids
    }

    public func storeScene(_ scene: DiagramScene) {
        lastScene = scene
    }

    public func previousScene() -> DiagramScene {
        lastScene
    }

    // `fitViewport`/`centerViewport`/`resetZoomOneToOne` used to wrap the viewport write in
    // `withAnimation(.easeOut)`. Nodes are drawn with animatable SwiftUI modifiers (`.offset`,
    // `.scaleEffect`) so they'd ease into the new viewport over ~0.18s — but edges are painted
    // inside a `Canvas`/`MTKView` draw closure, which reads `viewport` as a plain, non-animatable
    // value and jumps straight to the final transform. The result was edges visibly tearing away
    // from nodes for the duration of the animation on every Fit/Center/1:1. Assigning directly
    // keeps both frame-locked; there is no way to animate one without desyncing the other.
    public func fitViewport(to viewSize: CGSize? = nil, padding: CGFloat = 40) {
        let size = viewSize ?? canvasViewSize
        let bounds = CanvasEngine.contentBounds(nodes: document.nodes, padding: padding)
        guard let next = ViewportState.fitting(bounds: bounds, in: size) else { return }
        viewport = next
    }

    public func centerViewport(padding: CGFloat = 40) {
        let bounds = CanvasEngine.contentBounds(nodes: document.nodes, padding: padding)
        viewport = viewport.centered(on: bounds, in: canvasViewSize)
    }

    public func resetZoomOneToOne(padding: CGFloat = 40) {
        let bounds = CanvasEngine.contentBounds(nodes: document.nodes, padding: padding)
        viewport = ViewportState.oneToOne(centering: bounds, in: canvasViewSize)
    }

    public func zoomIn() {
        let center = CGPoint(x: canvasViewSize.width / 2, y: canvasViewSize.height / 2)
        viewport = viewport.zoomedIn(toward: center)
    }

    public func zoomOut() {
        let center = CGPoint(x: canvasViewSize.width / 2, y: canvasViewSize.height / 2)
        viewport = viewport.zoomedOut(toward: center)
    }

    @discardableResult
    public func ensureSpatialIndex() -> SpatialIndex {
        let fingerprint = currentFingerprint()
        if fingerprint != spatialFingerprint {
            spatialIndex.rebuild(document.nodes)
            spatialFingerprint = fingerprint
        }
        return spatialIndex
    }

    public func invalidateGeometryCaches() {
        spatialFingerprint = 0
        edgeRouteCache.invalidate()
        drawnEdgeCache.removeAll(keepingCapacity: true)
        dirtyNodeIDs = Set(document.nodes.map(\.id))
        lastScene = .empty
    }

    public func pruneSelection() {
        guard !selection.isEmpty else { return }
        let valid = Set(document.nodes.map(\.id)).union(document.edges.map(\.id))
        let next = selection.intersection(valid)
        // `@Observable` invalidates every reader on write — skip it when nothing actually changed
        // (the common case: pruneSelection now only runs for delete/replace, but a delete of
        // unselected elements still leaves the selection untouched).
        if next != selection {
            selection = next
        }
    }

    /// Update alignment guides, but skip the `@Observable` write when the new guides are
    /// geometrically identical to the current ones. `GuideLine.id` is now derived from
    /// `axis`/`position` rather than a fresh `UUID()` per construction, so two calls describing
    /// the same guide lines during a drag actually compare `==` instead of always differing.
    public func setGuides(_ guides: [GuideLine]) {
        if activeGuides != guides {
            activeGuides = guides
        }
    }

    public func setDraggingNodes(_ value: Bool) {
        if isDraggingNodes != value {
            isDraggingNodes = value
        }
    }
}


/// Cached vector edge ready for stroke painting / Metal.
public nonisolated struct CachedDrawnEdge: Sendable, Equatable {
    public var points: [CGPoint]
    public var isDashed: Bool
    public var label: String
    public var labelPoint: CGPoint
    public var markerPolylines: [[CGPoint]]
    public var markersClosed: [Bool]
    public var markersFilled: [Bool]

    public init(
        points: [CGPoint],
        isDashed: Bool,
        label: String,
        labelPoint: CGPoint,
        markerPolylines: [[CGPoint]] = [],
        markersClosed: [Bool] = [],
        markersFilled: [Bool] = []
    ) {
        self.points = points
        self.isDashed = isDashed
        self.label = label
        self.labelPoint = labelPoint
        self.markerPolylines = markerPolylines
        self.markersClosed = markersClosed
        self.markersFilled = markersFilled
    }
}

public nonisolated struct GuideLine: Sendable, Equatable, Identifiable {
    public enum Axis: Sendable, Equatable, Hashable {
        case horizontal
        case vertical
    }

    public var axis: Axis
    public var position: CGFloat

    public init(axis: Axis, position: CGFloat) {
        self.axis = axis
        self.position = position
    }

    /// Derived from geometry, not a fresh `UUID()` per construction — two guides describing the
    /// same line (same axis + position) must compare `Identifiable`-equal so repeated snap
    /// updates during a drag can be deduplicated (see `DiagramSession.setGuides`).
    public var id: Int {
        var hasher = Hasher()
        hasher.combine(axis)
        hasher.combine(position)
        return hasher.finalize()
    }
}
