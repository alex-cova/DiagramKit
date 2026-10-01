import SwiftUI
import UniformTypeIdentifiers

/// A single row in `DiagramDocumentTabBar`. Deliberately decoupled from any feature's session
/// type — callers project their tab state into this value and dispatch actions back by `id`,
/// the same shape `WorkbenchTabItem` uses for query tabs.
public struct DiagramDocumentTabItem: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var isDirty: Bool
    public init(
        id: UUID,
        title: String,
        isDirty: Bool
    ) {
        self.id = id
        self.title = title
        self.isDirty = isDirty
    }
}

/// Closable, reorderable document-tab strip for diagram tools that support multiple open
/// canvases. Visual twin of `WorkbenchTabBar` / `EditorTabBar` (underline selection, hover fill,
/// hover-revealed close) with dirty-dot semantics restored — query tabs have no unsaved concept,
/// but diagram documents do.
public struct DiagramDocumentTabBar: View {
    public let items: [DiagramDocumentTabItem]
    public let selectedID: UUID?
    public var canAddTab: Bool = true
    public let onSelect: (UUID) -> Void
    public let onClose: (UUID) -> Void
    public let onCloseOthers: (UUID) -> Void
    public let onCloseAll: () -> Void
    public let onMove: (Int, Int) -> Void
    public let onAdd: () -> Void

    @State private var draggingID: UUID?

    public var body: some View {
        HStack(spacing: 0) {
            if items.isEmpty {
                emptyLabel
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(items) { item in
                            DiagramDocumentTab(
                                title: item.title,
                                isDirty: item.isDirty,
                                isSelected: item.id == selectedID,
                                onSelect: { onSelect(item.id) },
                                onClose: { onClose(item.id) }
                            )
                            .contextMenu {
                                Button("Close") { onClose(item.id) }
                                Button("Close Others") { onCloseOthers(item.id) }
                                    .disabled(items.count < 2)
                                Button("Close All") { onCloseAll() }
                            }
                            .onDrag {
                                draggingID = item.id
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: DiagramTabReorderDropDelegate(
                                targetID: item.id,
                                items: items,
                                draggingID: $draggingID,
                                onMove: onMove
                            ))
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                }
                .scrollIndicators(.hidden)
            }

            addButton
        }
        .frame(height: 32)
        .background(Theme.cardBackground.opacity(0.28))
    }

    private var emptyLabel: some View {
        HStack {
            Text("No open canvases")
                .font(Theme.Typography.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var addButton: some View {
        Button("New canvas", systemImage: "plus", action: onAdd)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(canAddTab ? .secondary : .tertiary)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(minWidth: 44, minHeight: 32)
            .contentShape(Rectangle())
            .disabled(!canAddTab)
            .help(canAddTab ? "New canvas" : "Maximum canvases open")
    }
    public init(
        items: [DiagramDocumentTabItem],
        selectedID: UUID? = nil,
        canAddTab: Bool = true,
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void,
        onCloseOthers: @escaping (UUID) -> Void,
        onCloseAll: @escaping () -> Void,
        onMove: @escaping (Int, Int) -> Void,
        onAdd: @escaping () -> Void
    ) {
        self.items = items
        self.selectedID = selectedID
        self.canAddTab = canAddTab
        self.onSelect = onSelect
        self.onClose = onClose
        self.onCloseOthers = onCloseOthers
        self.onCloseAll = onCloseAll
        self.onMove = onMove
        self.onAdd = onAdd
    }
}

private struct DiagramTabReorderDropDelegate: DropDelegate {
    let targetID: UUID
    let items: [DiagramDocumentTabItem]
    @Binding var draggingID: UUID?
    let onMove: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != targetID,
              let from = items.firstIndex(where: { $0.id == draggingID }),
              let to = items.firstIndex(where: { $0.id == targetID })
        else { return }
        // Same destination index `TabListEngine.reorderDestination` uses: moving right
        // inserts after the target, moving left lands on it.
        onMove(from, to > from ? to + 1 : to)
    }
}

private struct DiagramDocumentTab: View {
    let title: String
    let isDirty: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            Button(action: onSelect) {
                HStack(spacing: Theme.Spacing.xs + 2) {
                    Circle()
                        .fill(isDirty ? Theme.Status.warning.opacity(0.95) : .clear)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel(isDirty ? "Unsaved changes" : "Saved")

                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Button("Close \(title)", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .opacity(isHovered || isSelected ? 1 : 0.35)
                .buttonStyle(.plain)
                .help("Close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(isSelected ? Theme.accent : .clear)
                    .frame(height: 2)
            }
        }
        .background {
            Rectangle()
                .fill(tabFill)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(Theme.Motion.quick) { isHovered = hovering }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .themedAnimation(Theme.Motion.standard, value: isSelected)
    }

    private var tabFill: Color {
        if isSelected {
            Theme.accent.opacity(Theme.Opacity.subtle)
        } else if isHovered {
            Theme.Interaction.hoverFill
        } else {
            .clear
        }
    }
}

#Preview("Diagram document tab bar") {
    let boardID = UUID()
    return DiagramDocumentTabBar(
        items: [
            DiagramDocumentTabItem(id: boardID, title: "Board", isDirty: false),
            DiagramDocumentTabItem(id: UUID(), title: "Wireframe", isDirty: true),
            DiagramDocumentTabItem(id: UUID(), title: "Flows", isDirty: false),
        ],
        selectedID: boardID,
        onSelect: { _ in },
        onClose: { _ in },
        onCloseOthers: { _ in },
        onCloseAll: {},
        onMove: { _, _ in },
        onAdd: {}
    )
    .frame(width: 420)
}
