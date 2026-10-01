import SwiftUI

/// Effective light/dark appearance for diagram rendering.
///
/// `CanvasSettings.theme` resolves through here so engines and scene builders can pick the
/// dark palette without threading `ColorScheme` through every call site. SwiftUI views should
/// still read `@Environment(\.colorScheme)` so the canvas re-renders when appearance changes;
/// `MainWindow` keeps this value in sync.
public nonisolated enum DiagramAppearance {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var isDark = false
    }

    private static let state = State()

    public nonisolated static var isDark: Bool {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.isDark
    }

    @MainActor
    public static func update(isDark: Bool) {
        state.lock.lock()
        state.isDark = isDark
        state.lock.unlock()
    }

    @MainActor
    public static func update(colorScheme: ColorScheme) {
        update(isDark: colorScheme == .dark)
    }
}

public extension EnvironmentValues {
    /// Active diagram palette for the current app appearance (light↔dark swap when applicable).
    @Entry var diagramResolvedTheme: DiagramTheme = DiagramThemeCatalog.light
    /// Whether diagram chrome should render for dark canvas appearance.
    @Entry var diagramIsDarkAppearance = false
}
