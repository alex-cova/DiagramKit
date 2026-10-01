import Foundation

public nonisolated struct DiagramMeta: Codable, Sendable, Equatable {
    public var title: String
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        title: String = "Untitled Diagram",
        notes: String = "",
        createdAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
