# DiagramKit

A macOS Swift library for editable node-and-edge diagrams: document model, layout,
edge routing, canvas, rendering, and workspace chrome.

Hextech's diagram tools (flow, UML, mind map, chalkboard, Swift map, class-browser CFG)
are the document shells. This package is the canvas and the engines.

## Requirements

- macOS 26 SDK (package platform: `.macOS(.v26)`), Xcode with Swift 6.2 toolchain
- Swift 6 language mode; the target defaults to `MainActor` isolation
- SwiftUI + AppKit + Metal (all system frameworks, no third-party dependencies)

## Installation

Add it as a Swift Package Manager dependency:

```swift
// Package.swift
dependencies: [
    .package(url: "<diagramkit-repo-url>", from: "1.0.0"),
],
targets: [
    .target(name: "MyDiagramTool", dependencies: ["DiagramKit"]),
]
```

Then `import DiagramKit`.

## Core concepts

| Concept | Type | Role |
|---|---|---|
| Node contract | `DiagramNode` | `id` + `frame`. Conform your domain node (or wrap it). |
| Edge contract | `DiagramEdge` | `id` + `sourceID` + `destinationID`. |
| Document | `DiagramDocument<Node, Edge>` / `MutableDiagramDocument` | In-memory shell: `meta`, `canvas`, `nodes`, `edges`. |
| Canvas config | `CanvasSettings` | Grid, snapping, routing style, theme, rulers, minimap. |
| Session | `DiagramSession<Document>` | Selection, viewport, undo, clipboard, route cache. |
| Scene | `DiagramScene` (`SceneNode` / `SceneEdge`) | Cached render descriptors built from a document. |
| Viewport | `ViewportState` | Pan/zoom transform between world and view coordinates. |

## Quick start

### 1. Model your document

```swift
import DiagramKit

struct FlowNode: DiagramNode, ClipboardPasteableNode, Codable {
    var id: UUID = UUID()
    var frame: CGRect
    var title: String
    // ClipboardPasteableNode / Codable conformance for copy-paste and saving.
}

struct FlowEdge: DiagramEdge, ClipboardPasteableEdge, Codable {
    var id: UUID = UUID()
    var sourceID: UUID
    var destinationID: UUID
}

typealias FlowDocument = DiagramDocument<FlowNode, FlowEdge>
```

`DiagramSession` requires `Document: Sendable & Equatable` with
`Node: ClipboardPasteableNode` and `Edge: ClipboardPasteableEdge`.

### 2. Create a session with a routing provider

```swift
let routing = DiagramRoutingProvider<FlowDocument>(
    fingerprint: { doc in /* hash of geometry + routing inputs */ 0 },
    computeRoutes: { doc in
        doc.edges.map { edge in
            let s = doc.node(id: edge.sourceID)!.frame
            let t = doc.node(id: edge.destinationID)!.frame
            return (id: edge.id, route: EdgeRouting.route(source: s, target: t, style: .orthogonal))
        }
    }
)
let session = DiagramSession(document: FlowDocument(), routing: routing)
```

Provide `computeRoutesSubset` too when you want incremental re-routing of only
affected edges instead of a full rebuild on every geometry change.

### 3. Show the canvas

```swift
DiagramCanvasView(
    viewport: $session.viewport,
    marqueeWorld: $session.marqueeWorld,
    canvas: session.document.canvas,
    selection: session.selection,
    interaction: DiagramCanvasInteraction(
        /* hit-testing, selection, move/resize/nudge closures wired to session */ ...
    )
) {
    // Your node + edge layers.
}
```

The canvas supplies the grid, pan/zoom gestures, marquee selection, node
move/resize, alignment guides, rulers, and an optional minimap. Domain node/edge
drawing is injected as `content`.

## Editing: commands, undo, clipboard

All mutations go through `session.applyEdit(_:registerUndo:)` with an
`EditCommand`: `.addNode`, `.addEdge`, `.deleteElements`, `.moveNodes`,
`.setNodeFrames`, `.resizeNode`, `.bringNodesToFront`, `.sendNodesToBack`,
`.setCanvasSettings`, `.setMetaTitle`, `.replaceDocument`. Undo support is
automatic via the session's `UndoManager` (`session.undo()` / `session.redo()`,
plus `beginUndoGrouping()` / `endUndoGrouping()` for multi-step gestures).

```swift
session.applyEdit(.addNode(FlowNode(frame: CGRect(x: 40, y: 40, width: 140, height: 100), title: "Start")))
session.applyEdit(.setNodeFrames([NodeFrame(id: id, frame: newFrame)]))
session.deleteSelection()
session.copySelection(); session.pasteClipboard()
session.alignSelection(.left); session.distributeSelection(.horizontal)
session.autoLayout(TreeLayout())   // any LayoutAlgorithm
```

Viewport helpers: `fitViewport()`, `centerViewport()`, `resetZoomOneToOne()`,
`zoomIn()` / `zoomOut()`.

## Layout algorithms

`LayoutAlgorithm.layout(_:options:)` maps a `LayoutGraph` (node frames + edge
pairs) to new frames, configured with `LayoutOptions` (origin, spacing,
direction). Available implementations:

- `TreeLayout`, `HierarchicalLayout`, `DominanceDrawingLayout`
- `ForceDirectedLayout`, `GridLayout`, `CircularLayout`, `RadialLayout`
- `SpiderLayout`, `TimelineLayout`, `ArcDiagramLayout`
- 3D variants via `LayoutAlgorithm3D` (`ForceDirectedLayout3D`) with
  `LayoutProjection` for 2D/3D mapping

Algorithms also expose an incremental hook
(`layout(_:changedIDs:prior:options:)`, used by
`session.autoLayoutIncremental`) so large graphs can re-lay out only what changed.

## Edge routing

`EdgeRoutingStyle`: `.straight`, `.orthogonal`, `.bezier`, `.spline`
(configured per document via `CanvasSettings.edgeRouting`).

```swift
let route = EdgeRouting.route(
    source: sourceFrame, target: targetFrame,
    sourceAnchor: .auto, targetAnchor: .auto,
    context: EdgeRoutingContext(style: .orthogonal, obstacles: frames, avoidObstacles: true)
)
```

Building blocks: `OrthogonalRouter`, `BezierRouter` / `SplineRouter`
(`CurveRouters`), `ObstacleAvoider`, `EdgeRouteCache` (fingerprint-keyed caching),
`ArcEdgeGeometry` for arc diagrams. `CanvasEngine.hitTestEdge(at:routes:zoom:)`
hit-tests precomputed routes.

## Rendering: Metal with CG fallback

The default renderer is Core Graphics (`DiagramSceneRenderer.drawEdges` /
`drawNodes` into a SwiftUI `Canvas`). For large scenes, opt into the batched
Metal path:

```swift
MetalSceneView(
    nodes: scene.nodes,
    edges: scene.edges,
    viewport: session.viewport,
    contentVersion: DiagramSceneVersion.combine(
        geometry: scene.fingerprint,
        selection: session.selection,
        themeID: session.document.canvas.themeID
    )
)
.environment(\.diagramUseMetal, true)
```

- Metal draws rectangle-node fills/strokes and solid edges in a single `MTKView`
  draw from a persistent world-space vertex buffer (`MetalSceneGeometry`).
- `contentVersion` must change only when scene *content* changes, never on
  pan/zoom — the viewport transform is applied on the GPU every frame.
- Everything Metal cannot draw (non-rectangle shapes, dashed edges, all text)
  is drawn by a CG overlay, so the composed frame stays pixel-complete.
- If Metal is unavailable (`MetalDiagramSupport.isAvailable`) or not requested,
  the whole scene renders through `DiagramSceneRenderer` — the CG path is both
  the default and the automatic fallback.
- The older edge-only layer (`MetalEdgeView`, `diagramUseMetalEdges`) still
  exists for edge-only use cases.
- 3D scenes use `SceneKitDiagramView` / `SceneKitDiagramHost`
  (`DiagramScene3D`, `SceneKitNavigationMode`, `SceneKitCameraBridge`).

## Canvas helpers

- `ViewportState` — `worldToView` / `viewToWorld`, `pan`, `zoom(by:toward:)`,
  `fitting`, `centered`, `oneToOne`, with `minZoom` / `maxZoom` clamping.
- `ViewportCulling` — visible-node/route filtering plus
  `viewport.visibleWorldRect(viewSize:)`.
- `GridRenderer` — adaptive grid segments (coarsens at low zoom to avoid
  sub-pixel wash). `SnapEngine` — grid/frame snapping. `AlignmentEngine` —
  align/distribute/nudge. `SpatialIndex` — hit-testing for large graphs.
- Chrome views: `SelectionOverlay`, `GuideOverlay`, `RulerBars`,
  `MiniMapView`, `DiagramZoomControls`, `DiagramSceneNavigationControl`.

## Workspace chrome

`DiagramWorkspaceShell` is the outer workbench (toolbar slots, canvas pane,
inspector split, shape library, document tabs, drop targeting, error alert,
export sheet host). Supporting pieces: `DiagramDocumentTabBar`,
`DiagramInspectorShell`, `DiagramZoomControls`, and a bundled `SplitView`
layout kit under `Support/SplitView`.

## Export

```swift
let png: Data = try DiagramExporter.png(content: myView, scale: .x2)
let pdf: Data = try DiagramExporter.pdf(bounds: contentBounds, background: theme.canvasBackground) { ctx in
    // draw into CGContext
}
let svg: Data = try DiagramExporter.svg(bounds: contentBounds) { graphics in
    // draw into SVGGraphics
}
```

`ExportScale` (`.x1`–`.x4`), `ExportError` with recovery suggestions.

## Serialization and theming

- `DiagramCodec.encode / decode / write / readData` — versioned JSON plus
  atomic file I/O (`UTType.hexdiagram` is declared for document files).
- `CodableColor` (sRGB + dark-mode lift helpers), `CodableGeometry` helpers.
- `DiagramThemeCatalog`: `light`, `dark`, `blueprint`, `sketch`,
  `presentation`, `chalkboard` — selected per document via
  `CanvasSettings.themeID`, resolved for appearance with
  `theme(id:)` / `resolved(id:forDarkAppearance:)`. `DiagramAppearance.isDark`
  tracks the app color scheme (updated from `DiagramCanvasView`).
- `DiagramShape`: rectangle, rounded rectangle, ellipse, diamond, polygon,
  cylinder, capsule, parallelogram, custom — with `CGPath` generation and
  hit-testing.

## Plugins

Implement `DiagramPlugin` (identifier, display name, `documentUTType`, tools)
and `DiagramPluginUI` (`nodeView`, `drawEdges`, `inspectorContent`) for a
document type; `DiagramPluginRegistry` tracks the known tool identifiers
(UML, CFG, flow, diagrams, Swift map, mind map). `DiagramRoutingProvider`
keeps `DiagramSession` document-generic.

## Project structure

```text
Sources/DiagramKit/
├── Animation/     layout transition helpers
├── Canvas/        DiagramCanvasView, viewport, grid, culling, chrome views
├── Core/          document, node/edge protocols, canvas settings, metadata
├── Editing/       EditCommand, clipboard, alignment engine
├── Export/        PNG/PDF/SVG exporters
├── Geometry/      snapping, spatial index, arc geometry
├── Hierarchy/     container nesting
├── Icons/         icon image cache
├── Inspector/     inspector shell
├── Interaction/   CanvasEngine (hit-testing, bounds)
├── Layout/        2D + 3D layout algorithms
├── Plugins/       DiagramPlugin / UI / registry
├── Rendering/     Metal + SceneKit renderers
├── Routing/       routers, route cache, obstacle avoidance
├── Scene/         DiagramScene(3D), CG scene renderer
├── Serialization/ JSON codec
├── Session/       DiagramSession (selection, undo, clipboard, caches)
├── Shapes/        DiagramShape + styles
├── Styling/       themes, colors, appearance, edge highlights
├── Support/       SplitView kit
└── Workspace/     workspace shell, tab bar, chrome
```
