import Foundation
import SwiftUI

/// Timing and curves for diagram transitions (layout, selection, zoom).
public nonisolated enum LayoutTransition {
    public static let duration: TimeInterval = 0.35
    public static let selectionDuration: TimeInterval = 0.18
    public static let zoomDuration: TimeInterval = 0.22

    public enum Curve: Sendable {
        case easeInOut
        case easeOut
        case spring

        @MainActor
        public var animation: Animation {
            switch self {
            case .easeInOut:
                .easeInOut(duration: LayoutTransition.duration)
            case .easeOut:
                .easeOut(duration: LayoutTransition.selectionDuration)
            case .spring:
                .spring(response: 0.35, dampingFraction: 0.82)
            }
        }
    }
}

/// Helpers for applying diagram animations behind `CanvasSettings.animateLayout`.
@MainActor
public enum DiagramAnimation {
    public static func layout(
        enabled: Bool,
        curve: LayoutTransition.Curve = .easeInOut,
        _ updates: () -> Void
    ) {
        if enabled {
            withAnimation(curve.animation, updates)
        } else {
            updates()
        }
    }

    public static func layoutAnimation(enabled: Bool) -> Animation? {
        enabled ? LayoutTransition.Curve.easeInOut.animation : nil
    }

    public static func selectionAnimation(enabled: Bool) -> Animation? {
        enabled ? LayoutTransition.Curve.easeOut.animation : nil
    }

    public static func zoomToFit(enabled: Bool) -> Animation? {
        enabled ? .easeOut(duration: LayoutTransition.zoomDuration) : nil
    }

    /// Placeholder for future expand/collapse group animations (CFG clusters).
    public static func expandCollapse(enabled: Bool) -> Animation? {
        enabled ? LayoutTransition.Curve.spring.animation : nil
    }
}

/// Simple LRU-ish cache for measured text sizes used by layout engines.
public nonisolated final class TextMeasurementCache: @unchecked Sendable {
    private var storage: [String: CGSize] = [:]
    private let lock = NSLock()
    private let capacity: Int

    public init(capacity: Int = 2_048) {
        self.capacity = max(64, capacity)
    }

    public func size(for key: String, compute: () -> CGSize) -> CGSize {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] {
            return cached
        }
        let value = compute()
        if storage.count >= capacity {
            storage.removeAll(keepingCapacity: true)
        }
        storage[key] = value
        return value
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll(keepingCapacity: true)
    }
}
