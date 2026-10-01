import CoreGraphics
import Foundation
import simd

/// World-space vertex fed to the edge vertex shader — see `MetalEdgeRenderer.attach(to:)` for
/// the Metal shader source that consumes this exact attribute layout. Pure, viewport-independent
/// data: pan/zoom apply on the GPU via `MetalEdgeUniforms`, never baked in here. That's what lets
/// `MetalEdgeRenderer` upload this buffer once per content version and reuse it across every
/// pan/zoom frame with zero CPU geometry work.
public nonisolated struct MetalEdgeVertex: Equatable {
    public var world: SIMD2<Float>
    public var normal: SIMD2<Float>
    public var halfWidth: Float
    public var color: SIMD4<Float>
    public init(
        world: SIMD2<Float>,
        normal: SIMD2<Float>,
        halfWidth: Float,
        color: SIMD4<Float>
    ) {
        self.world = world
        self.normal = normal
        self.halfWidth = halfWidth
        self.color = color
    }
}

/// Field order matches the Metal `Uniforms` struct in `MetalEdgeRenderer.attach(to:)` exactly, so
/// the raw bytes handed to `setVertexBytes` line up under Metal's std-constant layout rules.
public nonisolated struct MetalEdgeUniforms: Equatable {
    public var viewportSize: SIMD2<Float>
    public var offset: SIMD2<Float>
    public var zoom: Float
    public var scale: Float
    public init(
        viewportSize: SIMD2<Float>,
        offset: SIMD2<Float>,
        zoom: Float,
        scale: Float
    ) {
        self.viewportSize = viewportSize
        self.offset = offset
        self.zoom = zoom
        self.scale = scale
    }
}

/// Pure geometry builder for `MetalEdgeView`'s persistent vertex buffer — split out from the
/// `NSViewRepresentable`/`MTKViewDelegate` machinery so it's testable without a GPU device, and
/// `nonisolated` so it never implicitly depends on main-actor state.
public nonisolated enum MetalEdgeGeometry {
    /// Shared with `MetalEdgeRenderer.attach(to:)` and `MetalDiagramSupport`'s startup validation
    /// so both compile the exact same source — one produces the pipeline actually drawn with, the
    /// other proves that compilation succeeds before the view commits to the Metal branch.
    public static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VertexIn {
        float2 world [[attribute(0)]];
        float2 normal [[attribute(1)]];
        float halfWidth [[attribute(2)]];
        float4 color [[attribute(3)]];
    };
    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };
    struct Uniforms {
        float2 viewportSize;
        float2 offset;
        float zoom;
        float scale;
    };
    vertex VertexOut edge_vertex(VertexIn in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
        VertexOut out;
        float2 viewPt = (in.world * u.zoom + u.offset) * u.scale;
        float2 pos = viewPt + in.normal * in.halfWidth * u.scale;
        out.position = float4(pos.x / u.viewportSize.x * 2.0 - 1.0,
                               1.0 - pos.y / u.viewportSize.y * 2.0,
                               0.0, 1.0);
        out.color = in.color;
        return out;
    }
    fragment float4 edge_fragment(VertexOut in [[stage_in]]) {
        return in.color;
    }
    """

    /// Builds a screen-space quad (two triangles, 6 vertices) for one polyline segment, in world
    /// coordinates plus a unit normal. `ViewportState.worldToView`'s scale is uniform, so a
    /// segment's direction (and thus its perpendicular) is identical whether computed in world or
    /// view space — that invariant is what makes this buffer reusable at any zoom level without
    /// rebuilding.
    public static func appendQuad(
        from a: CGPoint,
        to b: CGPoint,
        halfWidth: Float,
        color: SIMD4<Float>,
        into vertices: inout [MetalEdgeVertex]
    ) {
        let ax = Float(a.x)
        let ay = Float(a.y)
        let bx = Float(b.x)
        let by = Float(b.y)
        var dx = bx - ax
        var dy = by - ay
        let len = max(sqrt(dx * dx + dy * dy), 0.0001)
        dx /= len
        dy /= len
        let normal = SIMD2<Float>(-dy, dx)
        let negNormal = -normal
        let pa = SIMD2<Float>(ax, ay)
        let pb = SIMD2<Float>(bx, by)

        vertices.append(contentsOf: [
            MetalEdgeVertex(world: pa, normal: normal, halfWidth: halfWidth, color: color),
            MetalEdgeVertex(world: pa, normal: negNormal, halfWidth: halfWidth, color: color),
            MetalEdgeVertex(world: pb, normal: normal, halfWidth: halfWidth, color: color),
            MetalEdgeVertex(world: pb, normal: normal, halfWidth: halfWidth, color: color),
            MetalEdgeVertex(world: pa, normal: negNormal, halfWidth: halfWidth, color: color),
            MetalEdgeVertex(world: pb, normal: negNormal, halfWidth: halfWidth, color: color),
        ])
    }

    /// Builds the full vertex buffer content for a set of polylines. A pure function of `edges`
    /// alone — no `ViewportState` involved — which is what lets `MetalEdgeRenderer` cache the
    /// result across pan/zoom frames keyed only by a content version.
    public static func buildVertices(for edges: [MetalEdgePolyline]) -> [MetalEdgeVertex] {
        var vertices: [MetalEdgeVertex] = []
        vertices.reserveCapacity(edges.reduce(0) { $0 + max(0, $1.points.count - 1) * 6 })
        for edge in edges {
            let points = edge.points
            guard points.count >= 2 else { continue }
            let color = edge.color
            let rgba = SIMD4<Float>(
                Float(color.red),
                Float(color.green),
                Float(color.blue),
                Float(color.opacity)
            )
            let half = Float(edge.lineWidth) * 0.5
            for index in 0..<(points.count - 1) {
                appendQuad(from: points[index], to: points[index + 1], halfWidth: half, color: rgba, into: &vertices)
            }
        }
        return vertices
    }

    /// CPU reimplementation of the vertex shader's position math in `MetalEdgeRenderer.attach(to:)`
    /// — kept in parity with the Metal source via tests, since the shader itself can't be unit
    /// tested directly.
    public static func projectedNDC(_ vertex: MetalEdgeVertex, uniforms: MetalEdgeUniforms) -> SIMD2<Float> {
        let viewPoint = (vertex.world * uniforms.zoom + uniforms.offset) * uniforms.scale
        let position = viewPoint + vertex.normal * vertex.halfWidth * uniforms.scale
        return SIMD2(
            position.x / uniforms.viewportSize.x * 2 - 1,
            1 - position.y / uniforms.viewportSize.y * 2
        )
    }
}

/// Combines `MetalEdgeView`'s `contentVersion` inputs: the viewport-independent geometry
/// fingerprint (e.g. `CFGEdgeRouting.geometryFingerprint`, node frames + endpoints + routing
/// style) plus the two things that change an edge's *appearance* without moving it — selection
/// (drives `SceneEdge.stroke`/`lineWidth`) and the active theme. Both are O(selection)/O(1) to
/// fold in here, so callers don't need an O(edges) per-frame diff to catch a highlight or theme
/// change. Must never take a `ViewportState` — see `MetalEdgeView`'s doc comment.
public nonisolated enum DiagramEdgeVersion {
    public static func combine(geometry: UInt64, selection: Set<UUID>, themeID: String) -> UInt64 {
        // `Set` iteration order isn't stable, so fold selection with an order-independent XOR
        // rather than an ordered `Hasher.combine` sequence.
        var selectionMix: UInt64 = 0
        for id in selection {
            var hasher = Hasher()
            hasher.combine(id)
            selectionMix ^= UInt64(bitPattern: Int64(hasher.finalize()))
        }
        var hasher = Hasher()
        hasher.combine(geometry)
        hasher.combine(selectionMix)
        hasher.combine(themeID)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}
