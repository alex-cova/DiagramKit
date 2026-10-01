import SwiftUI

/// Segmented orbit / pan toggle for SceneKit diagram canvases.
public struct DiagramSceneNavigationControl: View {
    @Binding public var mode: SceneKitNavigationMode

    public var body: some View {
        Picker("Navigation", selection: $mode) {
            ForEach(SceneKitNavigationMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 132)
        .help("Choose whether dragging orbits or moves the 3D view")
        .accessibilityLabel("3D navigation mode")
    }
    public init(mode: Binding<SceneKitNavigationMode>) {
        self._mode = mode
    }
}
