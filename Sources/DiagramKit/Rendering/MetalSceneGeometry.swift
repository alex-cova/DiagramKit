import CoreGraphics
import Foundation
import simd

/// Batched world-space geometry for the full-scene Metal path (`MetalSceneView`).
///
/// Same vertex/uniform layout and shader as the edge-only path — see
/// `MetalEdgeGeometry.shaderSource` and `MetalEdgeRenderer.makeVertexDescriptor()`. Node fills
/// are plain triangles (`normal == .zero`, `halfWidth == 0`), so the edge vertex shader
/// positions them with the identical pan/zoom math and one pipeline draws everything.
///
/// Deliberately covers only what triangulates exactly without CPU text or curve work:
/// axis-aligned rectangle fills/strokes plus solid polyline edges. Everything else —
/// non-rectangle shapes, dashed edges, labels/compartments — stays on the CG fallback
/// (`DiagramSceneRenderer`), which remains the pixel-complete renderer. `MetalSceneView`
/// partitions each frame with the helpers below so Metal never draws a wrong pixel.
public nonisolated enum MetalSceneGeometry {
    /// Shapes whose fill and stroke are exactly an axis-aligned rectangle, so a 2-triangle
    /// fan plus 4 border quads reproduces the CG path pixel-for-pixel (up to antialiasing).
    /// All other shapes keep their `CGPath` on the fallback — no rect approximation is ever
    /// uploaded for them.
    public static func isMetalEligible(_ shape: DiagramShape) -> Bool {
        switch shape {
        case .rectangle, .custom:
            return true
        case .roundedRectangle, .ellipse, .diamond, .polygon, .cylinder, .capsule, .parallelogram:
            return false
        }
    }

    /// Scene nodes in `nodes` that Metal draws fully (fill + stroke). The rest must be drawn
    /// by the CG fallback.
    public static func metalNodes(in nodes: [SceneNode]) -> [SceneNode] {
        nodes.filter { isMetalEligible($0.shape) }
    }

    /// Scene nodes the CG fallback must draw fully (fill + stroke + text).
    public static func fallbackNodes(in nodes: [SceneNode]) -> [SceneNode] {
        nodes.filter { !isMetalEligible($0.shape) }
    }

    /// Solid polyline edges Metal strokes. Dashed edges stay on Canvas — dashing in the
    /// shader would need per-fragment arc-length tracking for zero visual gain.
    public static func metalEdges(in edges: [SceneEdge]) -> [SceneEdge] {
        edges.filter { !$0.isDashed && $0.route.points.count >= 2 }
    }

    /// Edges the CG fallback must stroke (dashed ones, plus degenerate routes Metal skips).
    public static func fallbackEdges(in edges: [SceneEdge]) -> [SceneEdge] {
        edges.filter { $0.isDashed }
    }

    public static func rgba(of color: CodableColor) -> SIMD4<Float> {
        SIMD4(Float(color.red), Float(color.green), Float(color.blue), Float(color.opacity))
    }

    /// Two triangles filling `rect` in world space. `normal == .zero` / `halfWidth == 0`
    /// makes the shared edge vertex shader place them with pure pan/zoom math.
    public static func appendRectFill(
        _ rect: CGRect,
        color: SIMD4<Float>,
        into vertices: inout [MetalEdgeVertex]
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        let zero = SIMD2<Float>(0, 0)
        let minX = Float(rect.minX)
        let minY = Float(rect.minY)
        let maxX = Float(rect.maxX)
        let maxY = Float(rect.maxY)
        let a = SIMD2<Float>(minX, minY)
        let b = SIMD2<Float>(maxX, minY)
        let c = SIMD2<Float>(maxX, maxY)
        let d = SIMD2<Float>(minX, maxY)
        vertices.append(contentsOf: [
            MetalEdgeVertex(world: a, normal: zero, halfWidth: 0, color: color),
            MetalEdgeVertex(world: b, normal: zero, halfWidth: 0, color: color),
            MetalEdgeVertex(world: c, normal: zero, halfWidth: 0, color: color),
            MetalEdgeVertex(world: a, normal: zero, halfWidth: 0, color: color),
            MetalEdgeVertex(world: c, normal: zero, halfWidth: 0, color: color),
            MetalEdgeVertex(world: d, normal: zero, halfWidth: 0, color: color),
        ])
    }

    /// Four border quads stroking `rect` with a centered `lineWidth`, matching CG's
    /// default centered stroke placement. Reuses the edge quad builder so border joins
    /// behave exactly like polyline segments.
    public static func appendRectStroke(
        _ rect: CGRect,
        lineWidth: CGFloat,
        color: SIMD4<Float>,
        into vertices: inout [MetalEdgeVertex]
    ) {
        guard rect.width > 0, rect.height > 0, lineWidth > 0 else { return }
        let half = Float(lineWidth) * 0.5
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        MetalEdgeGeometry.appendQuad(from: topLeft, to: topRight, halfWidth: half, color: color, into: &vertices)
        MetalEdgeGeometry.appendQuad(from: topRight, to: bottomRight, halfWidth: half, color: color, into: &vertices)
        MetalEdgeGeometry.appendQuad(from: bottomRight, to: bottomLeft, halfWidth: half, color: color, into: &vertices)
        MetalEdgeGeometry.appendQuad(from: bottomLeft, to: topLeft, halfWidth: half, color: color, into: &vertices)
    }

    /// Full Metal vertex buffer content for one scene revision: rect-node fills, rect-node
    /// strokes, then solid edges. Pure function of `nodes`/`edges` alone — no `ViewportState`
    /// — so the renderer caches it across pan/zoom frames keyed by `contentVersion`.
    /// Colors are the raw scene colors, matching `DiagramSceneRenderer` exactly.
    public static func buildSceneVertices(nodes: [SceneNode], edges: [SceneEdge]) -> [MetalEdgeVertex] {
        var vertices: [MetalEdgeVertex] = []
        let nodeCount = nodes.count
        let segmentCount = edges.reduce(0) { $0 + max(0, $1.route.points.count - 1) }
        vertices.reserveCapacity(nodeCount * 30 + segmentCount * 6)
        for node in nodes where isMetalEligible(node.shape) {
            appendRectFill(node.frame, color: rgba(of: node.style.fill), into: &vertices)
        }
        for node in nodes where isMetalEligible(node.shape) {
            appendRectStroke(
                node.frame,
                lineWidth: node.style.lineWidth,
                color: rgba(of: node.style.stroke),
                into: &vertices
            )
        }
        for edge in edges where !edge.isDashed {
            let points = edge.route.points
            guard points.count >= 2 else { continue }
            let color = rgba(of: edge.stroke)
            let half = Float(edge.lineWidth) * 0.5
            for index in 0..<(points.count - 1) {
                MetalEdgeGeometry.appendQuad(
                    from: points[index],
                    to: points[index + 1],
                    halfWidth: half,
                    color: color,
                    into: &vertices
                )
            }
        }
        return vertices
    }
}

/// Content-version fingerprint for `MetalSceneView`: viewport-independent scene geometry
/// plus the appearance inputs that change pixels without moving anything. Same
/// order-independent selection folding as `DiagramEdgeVersion` — `Set` iteration order is
/// unstable, so selection mixes by XOR rather than ordered `Hasher.combine`.
public nonisolated enum DiagramSceneVersion {
    public static func combine(geometry: UInt64, selection: Set<UUID>, themeID: String) -> UInt64 {
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
