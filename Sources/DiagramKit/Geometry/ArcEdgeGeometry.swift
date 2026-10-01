import CoreGraphics
import Foundation
import simd

/// Quadratic arc samples for arc-diagram edges (baseline nodes, curved connectors).
public nonisolated enum ArcEdgeGeometry {
  /// Samples a quadratic Bézier from `start` to `end` bulging in SceneKit +Y.
  public static func sample3D(
    start: SIMD3<Float>,
    end: SIMD3<Float>,
    bulge: Float = 0.4,
    segments: Int = 14
  ) -> [SIMD3<Float>] {
    let control = control3D(start: start, end: end, bulge: bulge)
    return sampleQuadratic3D(start: start, control: control, end: end, segments: segments)
  }

  /// Samples a quadratic Bézier in flattened 2D canvas space (bulge toward smaller Y).
  public static func sample2D(
    start: CGPoint,
    end: CGPoint,
    bulge: CGFloat = 0.4,
    segments: Int = 16
  ) -> [CGPoint] {
    let control = control2D(start: start, end: end, bulge: bulge)
    return sampleQuadratic2D(start: start, control: control, end: end, segments: segments)
  }

  public static func control3D(
    start: SIMD3<Float>,
    end: SIMD3<Float>,
    bulge: Float
  ) -> SIMD3<Float> {
    let mid = (start + end) * 0.5
    let distance = simd_length(end - start)
    let height = max(distance * bulge, 20)
    return mid + SIMD3(0, height, 0)
  }

  public static func control2D(
    start: CGPoint,
    end: CGPoint,
    bulge: CGFloat
  ) -> CGPoint {
    let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    let distance = hypot(end.x - start.x, end.y - start.y)
    let height = max(distance * bulge, 18)
    return CGPoint(x: mid.x, y: mid.y - height)
  }

  private static func sampleQuadratic3D(
    start: SIMD3<Float>,
    control: SIMD3<Float>,
    end: SIMD3<Float>,
    segments: Int
  ) -> [SIMD3<Float>] {
    guard segments > 0 else { return [start, end] }
    return (0...segments).map { i in
      let t = Float(i) / Float(segments)
      let omt = 1 - t
      return omt * omt * start + 2 * omt * t * control + t * t * end
    }
  }

  private static func sampleQuadratic2D(
    start: CGPoint,
    control: CGPoint,
    end: CGPoint,
    segments: Int
  ) -> [CGPoint] {
    guard segments > 0 else { return [start, end] }
    return (0...segments).map { i in
      let t = CGFloat(i) / CGFloat(segments)
      let omt = 1 - t
      let x = omt * omt * start.x + 2 * omt * t * control.x + t * t * end.x
      let y = omt * omt * start.y + 2 * omt * t * control.y + t * t * end.y
      return CGPoint(x: x, y: y)
    }
  }
}
