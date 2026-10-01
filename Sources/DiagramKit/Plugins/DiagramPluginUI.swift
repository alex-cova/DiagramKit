import SwiftUI

/// MainActor UI surface a plugin provides for a concrete document type.
@MainActor
public protocol DiagramPluginUI {
    associatedtype Document: MutableDiagramDocument & Sendable & Equatable
    where Document.Node: Sendable & ClipboardPasteableNode,
          Document.Edge: Sendable & ClipboardPasteableEdge

    var plugin: any DiagramPlugin { get }

    func nodeView(
        node: Document.Node,
        isSelected: Bool,
        onResizeHandleDrag: ((CGSize) -> Void)?,
        onResizeHandleEnd: (() -> Void)?
    ) -> AnyView

    func drawEdges(
        document: Document,
        routes: [(id: UUID, route: EdgeRoute)],
        selection: Set<UUID>,
        viewport: ViewportState,
        visibleWorldRect: CGRect,
        context: inout GraphicsContext
    )

    func inspectorContent(session: DiagramSession<Document>) -> AnyView
}
