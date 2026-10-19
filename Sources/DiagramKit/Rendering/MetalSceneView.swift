import AppKit
import Metal
import MetalKit
import SwiftUI

public extension EnvironmentValues {
    /// Opt-in to the Metal scene path. The CG renderer (`DiagramSceneRenderer`) stays the
    /// default and the automatic fallback: `MetalSceneView` uses Metal only when this is true
    /// *and* `MetalDiagramSupport.isAvailable` passes. Kept separate from
    /// `diagramUseMetalEdges` (edge-only layer) so existing call sites are unaffected.
    @Entry var diagramUseMetal = false
}

public extension MetalDiagramSupport {
    /// Single place resolving "should this frame go to Metal": explicit opt-in plus the
    /// startup-validated device/queue/shader/pipeline chain. Anything else uses CG.
    static func shouldUseMetal(requested: Bool) -> Bool {
        requested && isAvailable
    }
}

/// Full-scene renderer: batched Metal path with the CG renderer as fallback.
///
/// Metal branch draws rectangle-node fills/strokes plus solid edges in one `MTKView` draw
/// (see `MetalSceneGeometry` for the exact coverage). The CG overlay in that branch draws
/// everything Metal cannot — non-rectangle node bodies, dashed edges, all text labels — so
/// the composed frame is pixel-complete. When Metal is not requested or not available, the
/// whole scene goes through `DiagramSceneRenderer` on a `Canvas`.
///
/// `contentVersion` must change only when scene *content* changes (e.g.
/// `DiagramSceneVersion.combine`), never on pan/zoom: the vertex buffer is world-space and
/// rebuilt only on version change, while the viewport transform is applied on the GPU
/// every frame. Pass the full (unculled) scene — the GPU clips off-screen triangles, and
/// pre-culling would make the version viewport-dependent and defeat the persistent buffer.
/// The CG branches cull internally per draw.
public struct MetalSceneView: View {
    public var nodes: [SceneNode]
    public var edges: [SceneEdge]
    public var viewport: ViewportState
    public var contentVersion: UInt64
    public var isDarkAppearance: Bool

    @Environment(\.diagramUseMetal) private var useMetal

    public var body: some View {
        Group {
            if MetalDiagramSupport.shouldUseMetal(requested: useMetal) {
                ZStack {
                    MetalSceneMTKRepresentable(
                        nodes: nodes,
                        edges: edges,
                        viewport: viewport,
                        contentVersion: contentVersion
                    )
                    overlayCanvas
                }
            } else {
                fullFallbackCanvas
            }
        }
        .allowsHitTesting(false)
    }

    /// CG overlay for the Metal branch: fallback bodies plus every text label. Culled to
    /// the visible world rect per draw so large scenes don't pay O(scene) CG work here
    /// while Metal handles the bulk on the GPU.
    private var overlayCanvas: some View {
        Canvas { context, size in
            let worldRect = viewport.visibleWorldRect(viewSize: size)
            let fallback = MetalSceneGeometry.fallbackNodes(in: nodes).filter {
                ViewportCulling.isVisible(frame: $0.frame, in: worldRect)
            }
            if !fallback.isEmpty {
                DiagramSceneRenderer.drawNodes(
                    fallback,
                    viewport: viewport,
                    isDarkAppearance: isDarkAppearance,
                    in: &context
                )
            }
            let metal = MetalSceneGeometry.metalNodes(in: nodes).filter {
                ViewportCulling.isVisible(frame: $0.frame, in: worldRect)
            }
            drawNodeLabels(metal, in: &context)
            let dashed = MetalSceneGeometry.fallbackEdges(in: edges).filter {
                ViewportCulling.isRouteVisible($0.route, in: worldRect)
            }
            if !dashed.isEmpty {
                DiagramSceneRenderer.drawEdges(
                    dashed,
                    viewport: viewport,
                    isDarkAppearance: isDarkAppearance,
                    in: &context
                )
            }
            let solid = edges.filter { !$0.isDashed }.filter {
                ViewportCulling.isRouteVisible($0.route, in: worldRect)
            }
            drawEdgeLabels(solid, in: &context)
        }
    }

    /// Complete CG render — the fallback and still the default. Same culling as the
    /// overlay so panning a large scene costs O(visible), not O(scene).
    private var fullFallbackCanvas: some View {
        Canvas { context, size in
            let worldRect = viewport.visibleWorldRect(viewSize: size)
            let visibleEdges = edges.filter { ViewportCulling.isRouteVisible($0.route, in: worldRect) }
            let visibleNodes = nodes.filter { ViewportCulling.isVisible(frame: $0.frame, in: worldRect) }
            DiagramSceneRenderer.drawEdges(
                visibleEdges,
                viewport: viewport,
                isDarkAppearance: isDarkAppearance,
                in: &context
            )
            DiagramSceneRenderer.drawNodes(
                visibleNodes,
                viewport: viewport,
                isDarkAppearance: isDarkAppearance,
                in: &context
            )
        }
    }

    /// Title + compartment text for nodes Metal already filled/stroked. Mirrors
    /// `DiagramSceneRenderer.drawNodes` text exactly (fonts, anchors, 8-line cap) so
    /// switching branches never reflows labels.
    private func drawNodeLabels(_ nodes: [SceneNode], in context: inout GraphicsContext) {
        for node in nodes {
            let viewFrame = viewport.worldToView(node.frame)
            let labelColor = node.style.fill.contrastingLabel.swiftUIColor
            if !node.title.isEmpty {
                context.draw(
                    Text(node.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(labelColor),
                    at: CGPoint(x: viewFrame.midX, y: viewFrame.minY + 14),
                    anchor: .center
                )
            }
            var y = viewFrame.minY + 28
            for line in node.compartments.prefix(8) {
                context.draw(
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(labelColor),
                    at: CGPoint(x: viewFrame.minX + 8, y: y),
                    anchor: .leading
                )
                y += 12
            }
        }
    }

    /// Edge labels for edges Metal already stroked. Mirrors `DiagramSceneRenderer.drawEdges`
    /// label styling, including the dark-mode display-stroke lift.
    private func drawEdgeLabels(_ edges: [SceneEdge], in context: inout GraphicsContext) {
        for edge in edges where !edge.label.isEmpty {
            let labelStroke = edge.stroke.diagramDisplayStroke(isDark: isDarkAppearance)
            context.draw(
                Text(edge.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(labelStroke.swiftUIColor),
                at: viewport.worldToView(edge.labelPoint),
                anchor: .center
            )
        }
    }

    public init(
        nodes: [SceneNode],
        edges: [SceneEdge],
        viewport: ViewportState,
        contentVersion: UInt64,
        isDarkAppearance: Bool = DiagramAppearance.isDark
    ) {
        self.nodes = nodes
        self.edges = edges
        self.viewport = viewport
        self.contentVersion = contentVersion
        self.isDarkAppearance = isDarkAppearance
    }
}

// MARK: - MTKView

private struct MetalSceneMTKRepresentable: NSViewRepresentable {
    var nodes: [SceneNode]
    var edges: [SceneEdge]
    var viewport: ViewportState
    var contentVersion: UInt64

    func makeCoordinator() -> MetalSceneMTKRenderer {
        MetalSceneMTKRenderer()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        // Same transaction-locked contract as the edge-only layer: driven synchronously
        // from `updateNSView` inside SwiftUI's render pass, presented with
        // `waitUntilScheduled()` + `drawable.present()` (see `MetalSceneMTKRenderer`).
        view.presentsWithTransaction = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.layer?.isOpaque = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.contentVersion != contentVersion {
            coordinator.nodes = nodes
            coordinator.edges = edges
            coordinator.contentVersion = contentVersion
        }
        coordinator.viewport = viewport
        view.draw()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTKView, context: Context) -> CGSize? {
        let width = proposal.width ?? max(nsView.bounds.width, 1)
        let height = proposal.height ?? max(nsView.bounds.height, 1)
        return CGSize(width: width, height: height)
    }
}

@MainActor
final class MetalSceneMTKRenderer: NSObject, MTKViewDelegate {
    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?

    private var vertexBuffer: MTLBuffer?
    private var vertexBufferCapacity: Int = 0
    private var vertexCount: Int = 0
    private var builtVersion: UInt64?

    private var lastDrawnViewport: ViewportState?
    private var lastDrawnVersion: UInt64?
    private var lastDrawnSize: CGSize?

    var nodes: [SceneNode] = []
    var edges: [SceneEdge] = []
    var viewport = ViewportState()
    var contentVersion: UInt64 = 0

    func attach(to view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return }
        self.device = device
        self.queue = queue
        view.device = device
        view.delegate = self

        guard let library = try? device.makeLibrary(source: MetalEdgeGeometry.shaderSource, options: nil),
              let vert = library.makeFunction(name: "edge_vertex"),
              let frag = library.makeFunction(name: "edge_fragment")
        else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vert
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        // Same vertex layout the startup validation in `MetalDiagramSupport.isAvailable`
        // checks — a different descriptor here would draw with (or fail against) a
        // different pipeline than the one availability was proven for.
        desc.vertexDescriptor = MetalEdgeRenderer.makeVertexDescriptor()

        pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        rebuildGeometryIfNeeded()

        let size = view.drawableSize
        guard size.width > 0, size.height > 0 else { return }

        // Coalesce redundant synchronous draws: several SwiftUI body evaluations can land
        // per displayed frame. Skipping the `currentDrawable` acquisition when nothing
        // changed avoids blocking the main thread once three drawables are in flight.
        if lastDrawnViewport == viewport, lastDrawnVersion == contentVersion, lastDrawnSize == size {
            return
        }

        guard let queue,
              let pipeline,
              let vertexBuffer, vertexCount > 0,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        // Derived from the drawable, not `window?.backingScaleFactor`: before the view is
        // in a window that falls back to a hardcoded value while `drawableSize` may
        // already disagree, doubling every position.
        let derivedScale = Float(size.width / max(view.bounds.width, 1))
        let scale = derivedScale.isFinite && derivedScale > 0
            ? derivedScale
            : Float(view.window?.backingScaleFactor ?? 1)

        var uniforms = MetalEdgeUniforms(
            viewportSize: SIMD2(Float(size.width), Float(size.height)),
            offset: SIMD2(Float(viewport.offset.x), Float(viewport.offset.y)),
            zoom: Float(viewport.zoom),
            scale: scale
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalEdgeUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()
        buffer.commit()
        // Required with `presentsWithTransaction`: scheduling wait plus immediate present,
        // not `MTLCommandBuffer.present(_:)` schedule-on-completion semantics.
        buffer.waitUntilScheduled()
        drawable.present()

        lastDrawnViewport = viewport
        lastDrawnVersion = contentVersion
        lastDrawnSize = size
    }

    /// World-space buffer rebuild keyed only by `contentVersion` — pan/zoom frames skip
    /// this entirely (single integer compare) and reuse the GPU buffer with new uniforms.
    private func rebuildGeometryIfNeeded() {
        guard builtVersion != contentVersion else { return }
        upload(MetalSceneGeometry.buildSceneVertices(nodes: nodes, edges: edges))
        builtVersion = contentVersion
    }

    private func upload(_ vertices: [MetalEdgeVertex]) {
        vertexCount = vertices.count
        guard !vertices.isEmpty, let device else {
            vertexBuffer = nil
            vertexBufferCapacity = 0
            return
        }
        let needed = vertices.count * MemoryLayout<MetalEdgeVertex>.stride
        if let existing = vertexBuffer, vertexBufferCapacity >= needed {
            vertices.withUnsafeBytes { raw in
                existing.contents().copyMemory(from: raw.baseAddress!, byteCount: needed)
            }
        } else {
            vertexBuffer = device.makeBuffer(bytes: vertices, length: needed, options: .storageModeShared)
            vertexBufferCapacity = vertexBuffer == nil ? 0 : needed
        }
    }
}
