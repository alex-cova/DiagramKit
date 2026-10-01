import SwiftUI

/// Shared toolbar cluster for diagram canvas zoom / framing.
public struct DiagramZoomControls: View {
    public let zoomPercent: Int
    public var canFrameContent: Bool = true
    public let onZoomOut: () -> Void
    public let onZoomIn: () -> Void
    public let onOneToOne: () -> Void
    public let onCenter: () -> Void
    public let onFit: () -> Void

    public var body: some View {
        HStack(spacing: 2) {
            Button("Zoom Out", systemImage: "minus.magnifyingglass", action: onZoomOut)
                .labelStyle(.iconOnly)
                .help("Zoom out")

            Button("Zoom In", systemImage: "plus.magnifyingglass", action: onZoomIn)
                .labelStyle(.iconOnly)
                .help("Zoom in")

            Button(action: onOneToOne) {
                Text("1:1")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 28)
            }
            .help("Actual size (100%)")
            .accessibilityLabel("Actual size 100%")
            .disabled(!canFrameContent)

            Button("Center Content", systemImage: "viewfinder", action: onCenter)
                .labelStyle(.iconOnly)
                .help("Center content")
                .disabled(!canFrameContent)

            Button("Fit Content", systemImage: "arrow.up.left.and.arrow.down.right", action: onFit)
                .labelStyle(.iconOnly)
                .help("Fit content")
                .disabled(!canFrameContent)

            Text("\(zoomPercent)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .buttonStyle(.borderless)
    }
    public init(
        zoomPercent: Int,
        canFrameContent: Bool = true,
        onZoomOut: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onOneToOne: @escaping () -> Void,
        onCenter: @escaping () -> Void,
        onFit: @escaping () -> Void
    ) {
        self.zoomPercent = zoomPercent
        self.canFrameContent = canFrameContent
        self.onZoomOut = onZoomOut
        self.onZoomIn = onZoomIn
        self.onOneToOne = onOneToOne
        self.onCenter = onCenter
        self.onFit = onFit
    }
}
