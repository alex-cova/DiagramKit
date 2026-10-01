import Foundation
import UniformTypeIdentifiers

/// Palette / toolbar tool advertised by a diagram plugin.
public nonisolated struct DiagramToolDescriptor: Identifiable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var systemImage: String

    public init(id: String, displayName: String, systemImage: String) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
    }

    public static let select = DiagramToolDescriptor(id: "select", displayName: "Select", systemImage: "arrow.up.left.and.arrow.down.right")
    public static let pan = DiagramToolDescriptor(id: "pan", displayName: "Pan", systemImage: "hand.draw")
}

/// Domain-agnostic plugin metadata (no SwiftUI).
public nonisolated protocol DiagramPlugin: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    var documentUTType: UTType { get }
    var tools: [DiagramToolDescriptor] { get }
}

/// Routing helpers supplied by the domain so `DiagramSession` stays document-generic.
public nonisolated struct DiagramRoutingProvider<Document: MutableDiagramDocument>: Sendable {
    public var fingerprint: @Sendable (Document) -> UInt64
    public var computeRoutes: @Sendable (Document) -> [(id: UUID, route: EdgeRoute)]
    /// Routes for a subset of edges only (document order not required — the cache reindexes).
    /// Optional so features can opt in one at a time; when `nil`, `DiagramSession` falls back to
    /// a full `computeRoutes` rebuild on every geometry change, exactly as before this existed.
    public var computeRoutesSubset: (@Sendable (Document, Set<UUID>) -> [(id: UUID, route: EdgeRoute)])?

    public init(
        fingerprint: @escaping @Sendable (Document) -> UInt64,
        computeRoutes: @escaping @Sendable (Document) -> [(id: UUID, route: EdgeRoute)],
        computeRoutesSubset: (@Sendable (Document, Set<UUID>) -> [(id: UUID, route: EdgeRoute)])? = nil
    ) {
        self.fingerprint = fingerprint
        self.computeRoutes = computeRoutes
        self.computeRoutesSubset = computeRoutesSubset
    }
}
