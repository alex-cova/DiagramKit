import Foundation
import UniformTypeIdentifiers

public extension UTType {
    nonisolated static let hexdiagram = UTType(exportedAs: "com.alex-cova.Ultimate.hexdiagram")
}

public nonisolated enum DiagramCodecError: Error, LocalizedError, Sendable {
    case unsupportedSchemaVersion(Int)
    case encodingFailed
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let v):
            "Unsupported diagram schema version \(v)"
        case .encodingFailed:
            "Failed to encode diagram"
        case .decodingFailed(let message):
            "Failed to decode diagram: \(message)"
        }
    }
}

/// Domain-agnostic JSON encode/decode and atomic file I/O for diagram documents.
public nonisolated enum DiagramCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(value)
        } catch {
            throw DiagramCodecError.encodingFailed
        }
    }

    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        maxSchemaVersion: Int,
        schemaVersion: (T) -> Int
    ) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value: T
        do {
            value = try decoder.decode(type, from: data)
        } catch {
            throw DiagramCodecError.decodingFailed(error.localizedDescription)
        }
        let version = schemaVersion(value)
        guard version <= maxSchemaVersion else {
            throw DiagramCodecError.unsupportedSchemaVersion(version)
        }
        return value
    }

    public static func write(_ data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).diagram.tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try write(try encode(value), to: url)
    }

    public static func readData(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}
