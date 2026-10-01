import CoreGraphics
import SwiftUI

public extension EnvironmentValues {
    /// World-space rect currently on screen (set by `DiagramCanvasView`).
    @Entry var visibleWorldRect: CGRect = .infinite
}
