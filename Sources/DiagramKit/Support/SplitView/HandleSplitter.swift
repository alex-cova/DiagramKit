import AppKit
import SwiftUI

/// A divider drawn as nothing but a short capsule at the centre of the boundary, tinted barely
/// above the background. The panes themselves already read as separate surfaces, so a full-length
/// rule is redundant chrome — the capsule's only job is to mark the seam as grabbable.
///
/// Conforming to `SplitDivider` is the whole contract for a custom divider: expose a
/// `SplitStyling`, and `Split` will read `visibleThickness` from it to decide how much space to
/// reserve between the panes. Everything else about the view is yours.
struct HandleSplitter: SplitDivider {
    @Environment(LayoutHolder.self) private var layout
    let styling: SplitStyling

    @State private var hovering = false

    /// - Parameters:
    ///   - color: Capsule colour at rest. Kept close to the background on purpose.
    ///   - activeColor: Capsule colour while hovered, so the affordance firms up under the cursor.
    ///   - thickness: The gap reserved between the two panes.
    ///   - hitThickness: Width of the invisible drag target. Keep this modest — it overlays
    ///     the panes on both sides, and clicks landing inside it never reach their content.
    ///   - handleLength: How far the capsule runs along the seam.
    ///   - handleThickness: How fat the capsule is across the seam.
    init(
        color: Color = Theme.cardStroke,
        activeColor: Color = Color.secondary.opacity(0.5),
        thickness: CGFloat = 6,
        hitThickness: CGFloat = 10,
        handleLength: CGFloat = 36,
        handleThickness: CGFloat = 4
    ) {
        self.activeColor = activeColor
        self.handleLength = handleLength
        self.handleThickness = handleThickness
        styling = SplitStyling(
            color: color,
            inset: 0,
            visibleThickness: thickness,
            invisibleThickness: hitThickness
        )
    }

    private let activeColor: Color
    private let handleLength: CGFloat
    private let handleThickness: CGFloat

    var body: some View {
        let horizontal = layout.isHorizontal
        // While drag-to-hide is previewing, Split expects the divider to disappear.
        let previewing = styling.previewHide && styling.hideSplitter

        ZStack {
            // The drag target: wider than the capsule so the seam stays easy to grab.
            Color.clear
                .frame(
                    width: horizontal ? styling.invisibleThickness : nil,
                    height: horizontal ? nil : styling.invisibleThickness
                )

            Capsule()
                .fill(previewing ? .clear : (hovering ? activeColor : styling.color))
                .frame(
                    width: horizontal ? handleThickness : handleLength,
                    height: horizontal ? handleLength : handleThickness
                )
        }
        .themedAnimation(Theme.Motion.quick, value: hovering)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            // Nested splits can hand the cursor straight from one divider to another, so always
            // pop before deciding whether to push — popping an empty stack is a no-op.
            NSCursor.pop()
            if inside {
                layout.isHorizontal ? NSCursor.resizeLeftRight.push() : NSCursor.resizeUpDown.push()
            }
        }
    }
}
