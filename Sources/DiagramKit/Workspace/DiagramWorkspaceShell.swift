import SwiftUI
import UniformTypeIdentifiers

/// Shared outer chrome for Flow/UML-style diagram workspaces:
/// Split canvas + inspector, workbench padding/gradient, drop targeting, error alert, export sheet host.
public struct DiagramWorkspaceShell<
    LeadingToolbar: View,
    MidToolbar: View,
    TrailingToolbar: View,
    Canvas: View,
    EmptyLanding: View,
    Inspector: View,
    ExportSheet: View
>: View {
    public let tint: Color
    public let alertTitle: String
    public let dropMessage: String
    public let showInspector: Bool
    public let hasSelection: Bool
    public let isEmpty: Bool
    /// When false, `showInspector` alone decides visibility — a persistent inspector, for tools
    /// (like Chalkboard) where default-style controls must be reachable with nothing selected.
    public var inspectorRequiresSelection: Bool = true

    @Binding public var isDropTargeted: Bool
    @Binding public var errorMessage: String?
    @Binding public var showExportSheet: Bool

    public let onDrop: ([NSItemProvider]) -> Bool

    @ViewBuilder public var leadingToolbar: () -> LeadingToolbar
    @ViewBuilder public var midToolbar: () -> MidToolbar
    @ViewBuilder public var trailingToolbar: () -> TrailingToolbar
    @ViewBuilder public var canvas: () -> Canvas
    @ViewBuilder public var emptyLanding: () -> EmptyLanding
    @ViewBuilder public var inspector: () -> Inspector
    @ViewBuilder public var exportSheet: () -> ExportSheet
    /// Optional document-tab strip rendered above the toolbar. `AnyView`-erased rather than an
    /// extra generic parameter so the single-document diagram tools don't have to spell out an
    /// eighth generic just to pass `EmptyView` — only Chalkboard currently supplies one.
    public var tabBar: (() -> AnyView)? = nil

    /// Optional Lucidchart-style shape library on the leading edge of the split.
    public var library: (() -> AnyView)? = nil

    public var body: some View {
        workspacePanes
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.workbenchGradient)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: onDrop)
        .alert(alertTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showExportSheet) {
            exportSheet()
        }
    }

    @ViewBuilder
    private var workspacePanes: some View {
        if let library {
            SplitPanes(
                minPrimary: 200,
                maxPrimary: 320,
                idealPrimary: 240,
                minSecondary: 320,
                storageKey: "diagrams.library"
            ) {
                library()
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            } secondary: {
                canvasAndInspector
            }
        } else {
            canvasAndInspector
        }
    }

    @ViewBuilder
    private var canvasAndInspector: some View {
        if showInspector, hasSelection || !inspectorRequiresSelection {
            SplitPanes(
                minPrimary: 320,
                minSecondary: 220,
                maxSecondary: 380,
                idealSecondary: 280,
                storageKey: "diagrams.inspector",
                priority: .secondary
            ) {
                canvasPane
                    .frame(minWidth: 320)
                    .layoutPriority(1)
            } secondary: {
                inspector()
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
            }
        } else {
            canvasPane
                .frame(minWidth: 320)
                .layoutPriority(1)
        }
    }

    private var canvasPane: some View {
        VStack(spacing: 0) {
            if let tabBar {
                tabBar()
                Divider()
            }
            toolbar
            Divider()
            ZStack {
                canvas()

                if isEmpty {
                    emptyLanding()
                }

                if isDropTargeted {
                    DiagramDropOverlay(tint: tint, message: dropMessage)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .cardSurface()
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            leadingToolbar()
            Divider().frame(height: 18)
            midToolbar()
            trailingToolbar()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.cardBackground.opacity(0.55))
    }
    public init(
        tint: Color,
        alertTitle: String,
        dropMessage: String,
        showInspector: Bool,
        hasSelection: Bool,
        isEmpty: Bool,
        inspectorRequiresSelection: Bool = true,
        isDropTargeted: Binding<Bool>,
        errorMessage: Binding<String?>,
        showExportSheet: Binding<Bool>,
        onDrop: @escaping ([NSItemProvider]) -> Bool,
        @ViewBuilder leadingToolbar: @escaping () -> LeadingToolbar,
        @ViewBuilder midToolbar: @escaping () -> MidToolbar,
        @ViewBuilder trailingToolbar: @escaping () -> TrailingToolbar,
        @ViewBuilder canvas: @escaping () -> Canvas,
        @ViewBuilder emptyLanding: @escaping () -> EmptyLanding,
        @ViewBuilder inspector: @escaping () -> Inspector,
        @ViewBuilder exportSheet: @escaping () -> ExportSheet,
        tabBar: (() -> AnyView)? = nil,
        library: (() -> AnyView)? = nil
    ) {
        self.tint = tint
        self.alertTitle = alertTitle
        self.dropMessage = dropMessage
        self.showInspector = showInspector
        self.hasSelection = hasSelection
        self.isEmpty = isEmpty
        self.inspectorRequiresSelection = inspectorRequiresSelection
        self._isDropTargeted = isDropTargeted
        self._errorMessage = errorMessage
        self._showExportSheet = showExportSheet
        self.onDrop = onDrop
        self.leadingToolbar = leadingToolbar
        self.midToolbar = midToolbar
        self.trailingToolbar = trailingToolbar
        self.canvas = canvas
        self.emptyLanding = emptyLanding
        self.inspector = inspector
        self.exportSheet = exportSheet
        self.tabBar = tabBar
        self.library = library
    }
}
