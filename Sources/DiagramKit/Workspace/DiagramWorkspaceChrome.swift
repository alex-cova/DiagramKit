import SwiftUI

// MARK: - Document strip

public struct DiagramDocumentStrip: View {
    public let symbol: String
    public let tint: Color
    public let title: String
    public let pathHelp: String
    public let isDirty: Bool

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.sm))

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if isDirty {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.cardBackground.opacity(0.65), in: .rect(cornerRadius: Theme.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.quietStroke, lineWidth: 1)
        }
        .help(pathHelp)
    }
    public init(
        symbol: String,
        tint: Color,
        title: String,
        pathHelp: String,
        isDirty: Bool
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.pathHelp = pathHelp
        self.isDirty = isDirty
    }
}

// MARK: - Edit / Undo

public struct DiagramEditMenu: View {
    public let selectedNodeCount: Int
    public let canPaste: Bool
    public var selectedElementCount: Int? = nil
    public let onCut: () -> Void
    public let onCopy: () -> Void
    public let onPaste: () -> Void
    public var onDuplicate: (() -> Void)? = nil
    public var onSelectAll: (() -> Void)? = nil
    public var onBringToFront: (() -> Void)? = nil
    public var onSendToBack: (() -> Void)? = nil

    public var body: some View {
        let selectionCount = selectedElementCount ?? selectedNodeCount
        Menu {
            Button("Cut", action: onCut)
                .keyboardShortcut("x", modifiers: .command)
                .disabled(selectionCount == 0)
            Button("Copy", action: onCopy)
                .keyboardShortcut("c", modifiers: .command)
                .disabled(selectionCount == 0)
            Button("Paste", action: onPaste)
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!canPaste)
            if let onDuplicate {
                Divider()
                Button("Duplicate", action: onDuplicate)
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(selectionCount == 0)
            }
            if let onSelectAll {
                Button("Select All", action: onSelectAll)
                    .keyboardShortcut("a", modifiers: .command)
            }
            if let onBringToFront, let onSendToBack {
                Divider()
                Button("Bring to Front", action: onBringToFront)
                    .keyboardShortcut("]", modifiers: [.command, .option])
                    .disabled(selectionCount == 0)
                Button("Send to Back", action: onSendToBack)
                    .keyboardShortcut("[", modifiers: [.command, .option])
                    .disabled(selectedNodeCount == 0)
            }
        } label: {
            Label("Edit", systemImage: "doc.on.clipboard")
                .labelStyle(.iconOnly)
        }
        .help("Cut, Copy, Paste")
    }
    public init(
        selectedNodeCount: Int,
        canPaste: Bool,
        selectedElementCount: Int? = nil,
        onCut: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onPaste: @escaping () -> Void,
        onDuplicate: (() -> Void)? = nil,
        onSelectAll: (() -> Void)? = nil,
        onBringToFront: (() -> Void)? = nil,
        onSendToBack: (() -> Void)? = nil
    ) {
        self.selectedNodeCount = selectedNodeCount
        self.canPaste = canPaste
        self.selectedElementCount = selectedElementCount
        self.onCut = onCut
        self.onCopy = onCopy
        self.onPaste = onPaste
        self.onDuplicate = onDuplicate
        self.onSelectAll = onSelectAll
        self.onBringToFront = onBringToFront
        self.onSendToBack = onSendToBack
    }
}

public struct DiagramUndoButtons: View {
    public let canUndo: Bool
    public let canRedo: Bool
    public let generation: Int
    public let onUndo: () -> Void
    public let onRedo: () -> Void

    public var body: some View {
        HStack(spacing: 2) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: onUndo)
                .disabled(!canUndo)
                .help("Undo")
                .id(generation)

            Button("Redo", systemImage: "arrow.uturn.forward", action: onRedo)
                .disabled(!canRedo)
                .help("Redo")
                .id(generation)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
    public init(
        canUndo: Bool,
        canRedo: Bool,
        generation: Int,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void
    ) {
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.generation = generation
        self.onUndo = onUndo
        self.onRedo = onRedo
    }
}

// MARK: - File menu

public struct DiagramFileMenuCluster: View {
    public let isDirty: Bool
    public let newHelp: String
    public let openHelp: String
    public let saveHelp: String
    public let recentURLs: [URL]
    public let onNew: () -> Void
    public let onOpen: () -> Void
    public let onSave: () -> Void
    public let onSaveAs: () -> Void
    public let onLoadSample: () -> Void
    public let onOpenURL: (URL) -> Void
    @ViewBuilder public var editMenu: () -> DiagramEditMenu

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button(action: onNew) {
                Label("New", systemImage: "doc.badge.plus")
            }
            .help(newHelp)

            Button(action: onOpen) {
                Label("Open", systemImage: "folder")
            }
            .help(openHelp)

            Button(action: onSave) {
                Label(isDirty ? "Save…" : "Save", systemImage: "square.and.arrow.down")
            }
            .help(saveHelp)

            editMenu()

            Menu("More Actions", systemImage: "ellipsis.circle") {
                Button("Save As…", action: onSaveAs)
                Button("Load Sample", action: onLoadSample)
                if !recentURLs.isEmpty {
                    Divider()
                    ForEach(recentURLs, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            onOpenURL(url)
                        }
                    }
                }
            }
            .help("More file actions")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
    public init(
        isDirty: Bool,
        newHelp: String,
        openHelp: String,
        saveHelp: String,
        recentURLs: [URL],
        onNew: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onSaveAs: @escaping () -> Void,
        onLoadSample: @escaping () -> Void,
        onOpenURL: @escaping (URL) -> Void,
        @ViewBuilder editMenu: @escaping () -> DiagramEditMenu
    ) {
        self.isDirty = isDirty
        self.newHelp = newHelp
        self.openHelp = openHelp
        self.saveHelp = saveHelp
        self.recentURLs = recentURLs
        self.onNew = onNew
        self.onOpen = onOpen
        self.onSave = onSave
        self.onSaveAs = onSaveAs
        self.onLoadSample = onLoadSample
        self.onOpenURL = onOpenURL
        self.editMenu = editMenu
    }
}

// MARK: - View / Arrange

public struct DiagramViewMenu: View {
    public let canvas: CanvasSettings
    public let onCanvasChange: (CanvasSettings) -> Void

    public var body: some View {
        Menu {
            Toggle(
                "Grid",
                isOn: Binding(
                    get: { canvas.showGrid },
                    set: { value in
                        var settings = canvas
                        settings.showGrid = value
                        onCanvasChange(settings)
                    }
                )
            )
            Toggle(
                "Snap",
                isOn: Binding(
                    get: { canvas.snapEnabled },
                    set: { value in
                        var settings = canvas
                        settings.snapEnabled = value
                        onCanvasChange(settings)
                    }
                )
            )
            Toggle(
                "Rulers",
                isOn: Binding(
                    get: { canvas.showRulers },
                    set: { value in
                        var settings = canvas
                        settings.showRulers = value
                        onCanvasChange(settings)
                    }
                )
            )
            Toggle(
                "Mini-map",
                isOn: Binding(
                    get: { canvas.showMiniMap },
                    set: { value in
                        var settings = canvas
                        settings.showMiniMap = value
                        onCanvasChange(settings)
                    }
                )
            )
        } label: {
            Label("View", systemImage: "eye")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .help("Grid, snap, rulers, mini-map")
    }
    public init(
        canvas: CanvasSettings,
        onCanvasChange: @escaping (CanvasSettings) -> Void
    ) {
        self.canvas = canvas
        self.onCanvasChange = onCanvasChange
    }
}

public struct DiagramArrangeMenu<ExtraLayouts: View>: View {
    public let nodeCount: Int
    public let selectedNodeCount: Int
    public let canvas: CanvasSettings
    public let onCanvasChange: (CanvasSettings) -> Void
    public let onAutoLayout: () -> Void
    public let onHierarchical: () -> Void
    public let onGrid: () -> Void
    public let onTree: () -> Void
    public let onForceDirected: () -> Void
    public let onAlign: (AlignmentEdge) -> Void
    public let onDistribute: (DistributionAxis) -> Void
    @ViewBuilder public var extraLayouts: () -> ExtraLayouts

    public var body: some View {
        Menu {
            Button("Auto Layout", action: onAutoLayout)
                .disabled(nodeCount == 0)
            Button("Layout Hierarchical", action: onHierarchical)
                .disabled(nodeCount == 0)
            Button("Layout Grid", action: onGrid)
                .disabled(nodeCount == 0)
            Button("Layout Tree", action: onTree)
                .disabled(nodeCount == 0)
            Button("Layout Force-Directed", action: onForceDirected)
                .disabled(nodeCount == 0)

            extraLayouts()

            Divider()

            Menu("Align") {
                Button("Left") { onAlign(.left) }
                Button("Center") { onAlign(.centerX) }
                Button("Right") { onAlign(.right) }
                Divider()
                Button("Top") { onAlign(.top) }
                Button("Middle") { onAlign(.centerY) }
                Button("Bottom") { onAlign(.bottom) }
            }
            .disabled(selectedNodeCount < 2)

            Menu("Distribute") {
                Button("Horizontally") { onDistribute(.horizontal) }
                Button("Vertically") { onDistribute(.vertical) }
            }
            .disabled(selectedNodeCount < 3)

            Divider()

            Picker(
                "Edge Routing",
                selection: Binding(
                    get: { canvas.edgeRouting },
                    set: { style in
                        var settings = canvas
                        settings.edgeRouting = style
                        onCanvasChange(settings)
                    }
                )
            ) {
                ForEach(EdgeRoutingStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }

            Toggle(
                "Avoid Obstacles",
                isOn: Binding(
                    get: { canvas.avoidObstacles },
                    set: { value in
                        var settings = canvas
                        settings.avoidObstacles = value
                        onCanvasChange(settings)
                    }
                )
            )

            Toggle(
                "Animate Layout",
                isOn: Binding(
                    get: { canvas.animateLayout },
                    set: { value in
                        var settings = canvas
                        settings.animateLayout = value
                        onCanvasChange(settings)
                    }
                )
            )

            Picker(
                "Theme",
                selection: Binding(
                    get: { canvas.themeID },
                    set: { id in
                        var settings = canvas
                        settings.themeID = id
                        onCanvasChange(settings)
                    }
                )
            ) {
                ForEach(DiagramThemeCatalog.all) { theme in
                    Text(theme.displayName).tag(theme.id)
                }
            }
        } label: {
            Label("Arrange", systemImage: "align.horizontal.left")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .help("Layout, align, and edge routing")
    }
    public init(
        nodeCount: Int,
        selectedNodeCount: Int,
        canvas: CanvasSettings,
        onCanvasChange: @escaping (CanvasSettings) -> Void,
        onAutoLayout: @escaping () -> Void,
        onHierarchical: @escaping () -> Void,
        onGrid: @escaping () -> Void,
        onTree: @escaping () -> Void,
        onForceDirected: @escaping () -> Void,
        onAlign: @escaping (AlignmentEdge) -> Void,
        onDistribute: @escaping (DistributionAxis) -> Void,
        @ViewBuilder extraLayouts: @escaping () -> ExtraLayouts
    ) {
        self.nodeCount = nodeCount
        self.selectedNodeCount = selectedNodeCount
        self.canvas = canvas
        self.onCanvasChange = onCanvasChange
        self.onAutoLayout = onAutoLayout
        self.onHierarchical = onHierarchical
        self.onGrid = onGrid
        self.onTree = onTree
        self.onForceDirected = onForceDirected
        self.onAlign = onAlign
        self.onDistribute = onDistribute
        self.extraLayouts = extraLayouts
    }
}

public extension DiagramArrangeMenu where ExtraLayouts == EmptyView {
    init(
        nodeCount: Int,
        selectedNodeCount: Int,
        canvas: CanvasSettings,
        onCanvasChange: @escaping (CanvasSettings) -> Void,
        onAutoLayout: @escaping () -> Void,
        onHierarchical: @escaping () -> Void,
        onGrid: @escaping () -> Void,
        onTree: @escaping () -> Void,
        onForceDirected: @escaping () -> Void,
        onAlign: @escaping (AlignmentEdge) -> Void,
        onDistribute: @escaping (DistributionAxis) -> Void
    ) {
        self.init(
            nodeCount: nodeCount,
            selectedNodeCount: selectedNodeCount,
            canvas: canvas,
            onCanvasChange: onCanvasChange,
            onAutoLayout: onAutoLayout,
            onHierarchical: onHierarchical,
            onGrid: onGrid,
            onTree: onTree,
            onForceDirected: onForceDirected,
            onAlign: onAlign,
            onDistribute: onDistribute,
            extraLayouts: { EmptyView() }
        )
    }
}

// MARK: - Drop overlay / Export sheet

public struct DiagramDropOverlay: View {
    public let tint: Color
    public let message: String

    public var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.md)
            .fill(tint.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(tint.opacity(0.45), lineWidth: 2)
            }
            .overlay {
                Label(message, systemImage: "arrow.down.doc.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.cardBackground.opacity(0.92), in: .capsule)
            }
            .allowsHitTesting(false)
    }
    public init(
        tint: Color,
        message: String
    ) {
        self.tint = tint
        self.message = message
    }
}

public struct DiagramExportSheet: View {
    public let title: String
    public let tint: Color
    @Binding public var exportScale: ExportScale
    @Binding public var exportTransparent: Bool
    public let onExportPNG: () -> Void
    public let onExportPDF: () -> Void
    public let onExportSVG: () -> Void
    public let onCancel: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Label(title, systemImage: "square.and.arrow.up")
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)

            Picker("PNG Scale", selection: $exportScale) {
                ForEach(ExportScale.allCases) { scale in
                    Text(scale.label).tag(scale)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Transparent PNG background", isOn: $exportTransparent)
            Text("PDF exports every page in document order. PNG and SVG export the active page.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Export PNG…", action: onExportPNG)
                    .keyboardShortcut(.defaultAction)

                Button("Export PDF…", action: onExportPDF)

                Button("Export SVG…", action: onExportSVG)

                Spacer()

                Button("Cancel", action: onCancel)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 420)
    }
    public init(
        title: String,
        tint: Color,
        exportScale: Binding<ExportScale>,
        exportTransparent: Binding<Bool>,
        onExportPNG: @escaping () -> Void,
        onExportPDF: @escaping () -> Void,
        onExportSVG: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.tint = tint
        self._exportScale = exportScale
        self._exportTransparent = exportTransparent
        self.onExportPNG = onExportPNG
        self.onExportPDF = onExportPDF
        self.onExportSVG = onExportSVG
        self.onCancel = onCancel
    }
}

public struct DiagramEmptyLandingHint: View {
    public let symbol: String
    public let title: String
    public let tint: Color

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint.opacity(0.85))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    public init(
        symbol: String,
        title: String,
        tint: Color
    ) {
        self.symbol = symbol
        self.title = title
        self.tint = tint
    }
}
