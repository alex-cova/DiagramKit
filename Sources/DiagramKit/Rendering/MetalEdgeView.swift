import AppKit
import Metal
import MetalKit
import simd
import SwiftUI

public extension EnvironmentValues {
    @Entry var diagramUseMetalEdges = false
}

public nonisolated enum MetalDiagramSupport {
    /// Validates the *full* chain `MetalEdgeRenderer.attach(to:)` depends on — device, command
    /// queue, shader compilation, and pipeline state — not just device creation. `attach(to:)` can
    /// still fail past device creation (bad driver, `makeLibrary`/`makeRenderPipelineState`
    /// rejecting the pipeline), and by the time that's discovered the `ZStack` in `MetalEdgeView`
    /// has already committed to the Metal branch with no Canvas fallback, so solid edges would
    /// silently vanish. Compute once — this can't change during a process's lifetime.
    public static let isAvailable: Bool = {
        guard let device = MTLCreateSystemDefaultDevice(),
              device.makeCommandQueue() != nil,
              let library = try? device.makeLibrary(source: MetalEdgeGeometry.shaderSource, options: nil),
              let vertexFn = library.makeFunction(name: "edge_vertex"),
              let fragmentFn = library.makeFunction(name: "edge_fragment")
        else { return false }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Matches `MetalEdgeRenderer.attach(to:)`'s vertex descriptor exactly — a `[[stage_in]]`
        // vertex function needs one to create a pipeline state at all, so validating without it
        // would be checking a different (and looser) pipeline than the one actually drawn with.
        descriptor.vertexDescriptor = MetalEdgeRenderer.makeVertexDescriptor()
        return (try? device.makeRenderPipelineState(descriptor: descriptor)) != nil
    }()
}

public nonisolated struct MetalEdgePolyline: Sendable, Equatable {
    public var points: [CGPoint]
    public var color: CodableColor
    public var lineWidth: CGFloat
    public var dashed: Bool
    public init(
        points: [CGPoint],
        color: CodableColor,
        lineWidth: CGFloat,
        dashed: Bool
    ) {
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.dashed = dashed
    }
}

/// Metal edge layer: solid polylines via `MTKView`; dashed edges stay on Canvas.
///
/// `contentVersion` should be a value that only changes when edge *geometry* (world-space
/// points, color, width) changes — e.g. `DiagramScene.fingerprint` — and must NOT change on pan
/// or zoom. The vertex buffer is world-space and rebuilt only when this version changes; the
/// viewport transform is applied on the GPU every frame via a uniform, so panning costs no CPU
/// geometry work at all. Callers should pass the full (unculled) edge set — the GPU clips
/// off-screen triangles for free, and pre-culling here would make `contentVersion` viewport
/// -dependent and defeat the persistent buffer.
public struct MetalEdgeView: View {
    public var edges: [MetalEdgePolyline]
    public var viewport: ViewportState
    public var contentVersion: UInt64

    public var body: some View {
        // Single pass over `edges` instead of two independent `filter`s.
        var solidEdges: [MetalEdgePolyline] = []
        var dashedEdges: [MetalEdgePolyline] = []
        for edge in edges where edge.points.count >= 2 {
            if edge.dashed {
                dashedEdges.append(edge)
            } else {
                solidEdges.append(edge)
            }
        }

        return ZStack {
            if MetalDiagramSupport.isAvailable, !solidEdges.isEmpty {
                MetalEdgeMTKRepresentable(edges: solidEdges, viewport: viewport, contentVersion: contentVersion)
            } else {
                canvasStroke(solidEdges)
            }
            if !dashedEdges.isEmpty {
                canvasStroke(dashedEdges)
            }
        }
        .allowsHitTesting(false)
    }

    private func canvasStroke(_ edges: [MetalEdgePolyline]) -> some View {
        // `Canvas` already rasterizes in a single pass; `drawingGroup(opaque: false)` used to add
        // an extra alpha-blended offscreen layer with no compositing benefit here.
        Canvas { context, _ in
            for edge in edges {
                guard let first = edge.points.first else { continue }
                var path = Path()
                path.move(to: viewport.worldToView(first))
                for point in edge.points.dropFirst() {
                    path.addLine(to: viewport.worldToView(point))
                }
                context.stroke(
                    path,
                    with: .color(edge.color.swiftUIColor),
                    style: StrokeStyle(lineWidth: edge.lineWidth, dash: edge.dashed ? [6, 4] : [])
                )
            }
        }
    }
    public init(
        edges: [MetalEdgePolyline],
        viewport: ViewportState,
        contentVersion: UInt64
    ) {
        self.edges = edges
        self.viewport = viewport
        self.contentVersion = contentVersion
    }
}

// MARK: - MTKView
//
// Vertex/uniform layout (`MetalEdgeVertex`, `MetalEdgeUniforms`) and the pure geometry builder
// live in `MetalEdgeGeometry.swift` — split out so they're testable without a GPU device and so
// this file stays focused on the `NSViewRepresentable`/`MTKViewDelegate` machinery.

private struct MetalEdgeMTKRepresentable: NSViewRepresentable {
    var edges: [MetalEdgePolyline]
    var viewport: ViewportState
    var contentVersion: UInt64

    func makeCoordinator() -> MetalEdgeRenderer {
        MetalEdgeRenderer()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        // Transaction-locked rendering: the draw is driven synchronously from `updateNSView`,
        // which runs inside SwiftUI's render pass — the same `CATransaction` that commits the
        // node layers' `.offset`/`.scaleEffect`. `presentsWithTransaction = true` tells
        // `CAMetalLayer` to fold its drawable's present into that same transaction instead of
        // scheduling it on its own clock.
        //
        // A prior attempt at `presentsWithTransaction` was reverted as "worse — garbled/torn
        // frames," but it combined the flag with two things that break it: driving the redraw
        // via `DispatchQueue.main.async { setNeedsDisplay }` (a turn *after* the transaction that
        // moved the nodes, so there was nothing left to sync to) and presenting via
        // `MTLCommandBuffer.present(_:)`, which is schedule-on-completion — exactly the semantics
        // `presentsWithTransaction` doesn't support. Fixed here: `view.draw()` is called
        // synchronously below, and `draw(in:)` presents with `waitUntilScheduled()` followed by
        // `drawable.present()` (see there).
        view.presentsWithTransaction = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true // covers resize/redisplay outside a SwiftUI update
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
            coordinator.edges = edges
            coordinator.contentVersion = contentVersion
        }
        coordinator.viewport = viewport
        // Synchronous, not `setNeedsDisplay` — this call happens inside SwiftUI's render pass,
        // so the draw (and, via `presentsWithTransaction`, its present) lands in the same
        // `CATransaction` as the node layers committed this frame.
        view.draw()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTKView, context: Context) -> CGSize? {
        let width = proposal.width ?? max(nsView.bounds.width, 1)
        let height = proposal.height ?? max(nsView.bounds.height, 1)
        return CGSize(width: width, height: height)
    }
}

@MainActor
public final class MetalEdgeRenderer: NSObject, MTKViewDelegate {
    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?

    private var vertexBuffer: MTLBuffer?
    private var vertexBufferCapacity: Int = 0
    private var vertexCount: Int = 0
    private var builtVersion: UInt64?

    // Coalescing guard: `updateNSView` now calls `view.draw()` synchronously on every SwiftUI
    // body evaluation, several of which can happen per frame (e.g. selection/theme changes that
    // don't move the viewport). Skipping a redundant draw avoids acquiring a fresh
    // `currentDrawable` when nothing this renderer cares about has actually changed — acquiring
    // one blocks the main thread once three drawables are already in flight.
    private var lastDrawnViewport: ViewportState?
    private var lastDrawnVersion: UInt64?
    private var lastDrawnSize: CGSize?

    public var edges: [MetalEdgePolyline] = []
    public var viewport = ViewportState()
    public var contentVersion: UInt64 = 0

    /// Shared with `MetalDiagramSupport.isAvailable`'s startup validation so both build a pipeline
    /// from the exact same vertex layout — otherwise the validation could pass or fail against a
    /// pipeline shape different from the one actually drawn with. `nonisolated` because it's pure
    /// (compile-time `MemoryLayout` offsets only) and `isAvailable` calls it from a nonisolated
    /// context to compute a `static let` at process startup.
    public nonisolated static func makeVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDesc = MTLVertexDescriptor()
        vertexDesc.attributes[0].format = .float2
        vertexDesc.attributes[0].offset = MemoryLayout<MetalEdgeVertex>.offset(of: \.world)!
        vertexDesc.attributes[0].bufferIndex = 0
        vertexDesc.attributes[1].format = .float2
        vertexDesc.attributes[1].offset = MemoryLayout<MetalEdgeVertex>.offset(of: \.normal)!
        vertexDesc.attributes[1].bufferIndex = 0
        vertexDesc.attributes[2].format = .float
        vertexDesc.attributes[2].offset = MemoryLayout<MetalEdgeVertex>.offset(of: \.halfWidth)!
        vertexDesc.attributes[2].bufferIndex = 0
        vertexDesc.attributes[3].format = .float4
        vertexDesc.attributes[3].offset = MemoryLayout<MetalEdgeVertex>.offset(of: \.color)!
        vertexDesc.attributes[3].bufferIndex = 0
        vertexDesc.layouts[0].stride = MemoryLayout<MetalEdgeVertex>.stride
        return vertexDesc
    }

    public func attach(to view: MTKView) {
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
        desc.vertexDescriptor = Self.makeVertexDescriptor()

        pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        rebuildGeometryIfNeeded()

        let size = view.drawableSize
        guard size.width > 0, size.height > 0 else { return }

        // Coalesce: `updateNSView` now calls `view.draw()` synchronously on every SwiftUI body
        // evaluation, and several can happen per displayed frame (e.g. a selection or theme
        // change that doesn't move the viewport). Skip the `currentDrawable` acquisition — which
        // blocks the main thread once three drawables are already in flight — when nothing this
        // renderer cares about changed since the last successful present.
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

        // Derive scale from the drawable itself rather than `window?.backingScaleFactor`: before
        // the view is in a window (or during teardown) that falls back to a hardcoded `2`, while
        // `drawableSize` may already be sized at 1x — drawing every edge at double its intended
        // screen position. `size`/`view.bounds` agree by construction since both come from the
        // same view.
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
        // `presentsWithTransaction` requires this exact sequence — a scheduling wait (not a
        // completion wait; sub-millisecond for this one draw call) followed by an immediate
        // `drawable.present()` — rather than `MTLCommandBuffer.present(_:)`'s schedule-on
        // -completion semantics, which is what made the earlier sync attempt tear.
        buffer.waitUntilScheduled()
        drawable.present()

        lastDrawnViewport = viewport
        lastDrawnVersion = contentVersion
        lastDrawnSize = size
    }

    /// Rebuilds the world-space vertex buffer only when `contentVersion` actually changed — a
    /// pan or zoom leaves `builtVersion == contentVersion` and this is a single integer compare.
    /// The geometry itself comes from `MetalEdgeGeometry.buildVertices`, a pure function of
    /// `edges` that never touches `viewport`.
    private func rebuildGeometryIfNeeded() {
        guard builtVersion != contentVersion else { return }
        upload(MetalEdgeGeometry.buildVertices(for: edges))
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
    public override init() {
        super.init()
    }
}
