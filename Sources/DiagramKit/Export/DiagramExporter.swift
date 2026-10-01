import AppKit
import CoreGraphics
import Foundation
import SwiftUI

public nonisolated enum ExportScale: Int, CaseIterable, Identifiable, Sendable {
    case x1 = 1
    case x2 = 2
    case x3 = 3
    case x4 = 4

    public var id: Int { rawValue }
    public var label: String { "\(rawValue)×" }
}

public nonisolated enum ExportError: Error, LocalizedError, Sendable {
    case renderFailed
    case encodeFailed
    case pdfFailed
    case emptyDocument

    public var errorDescription: String? {
        switch self {
        case .renderFailed: "Failed to render diagram"
        case .encodeFailed: "Failed to encode image"
        case .pdfFailed: "Failed to create PDF"
        case .emptyDocument: "Nothing to export"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .renderFailed:
            "Try exporting a smaller region or reduce the scale multiplier."
        case .encodeFailed:
            "Retry the export; if it persists, restart the app and export again."
        case .pdfFailed:
            "Ensure the diagram has visible content and at least one page to export."
        case .emptyDocument:
            "Add some markdown content before exporting."
        }
    }
}

public nonisolated enum DiagramExporter {
    public static let defaultContentPadding: CGFloat = 32

    @MainActor
    public static func png<Content: View>(content: Content, scale: ExportScale) throws -> Data {
        let renderer = ImageRenderer(content: content)
        renderer.scale = CGFloat(scale.rawValue)
        guard let image = renderer.cgImage else {
            throw ExportError.renderFailed
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.encodeFailed
        }
        return data
    }

    public static func pdf(
        bounds: CGRect,
        background: CodableColor? = nil,
        draw: @escaping (CGContext) -> Void
    ) throws -> Data {
        try pdf(pages: [(bounds: bounds, background: background, draw: draw)])
    }

    public static func pdf(
        pages: [(bounds: CGRect, background: CodableColor?, draw: (CGContext) -> Void)]
    ) throws -> Data {
        guard !pages.isEmpty else { throw ExportError.pdfFailed }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw ExportError.pdfFailed
        }

        for page in pages {
            let mediaBox = CGRect(origin: .zero, size: page.bounds.size)
            var box = mediaBox
            context.beginPage(mediaBox: &box)
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -page.bounds.minX, y: -page.bounds.minY)
            if let background = page.background {
                context.setFillColor(background.cgColor)
                context.fill(page.bounds)
            }
            page.draw(context)
            context.endPage()
        }
        context.closePDF()
        return data as Data
    }

    /*
     * Single-page behavior delegates above so both APIs share the same PDF coordinate transform.
     */
    public static func legacyPDF(
        bounds: CGRect,
        background: CodableColor? = nil,
        draw: (CGContext) -> Void
    ) throws -> Data {
        let mediaBox = CGRect(origin: .zero, size: bounds.size)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else {
            throw ExportError.pdfFailed
        }

        var box = mediaBox
        context.beginPage(mediaBox: &box)

        // Flip to top-left origin matching SwiftUI / SVG.
        context.translateBy(x: 0, y: mediaBox.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)

        if let background {
            context.setFillColor(background.cgColor)
            context.fill(bounds)
        }

        draw(context)

        context.endPage()
        context.closePDF()
        return data as Data
    }

    public static func svg(
        bounds: CGRect,
        background: CodableColor? = nil,
        draw: (SVGGraphics) -> Void
    ) throws -> Data {
        let graphics = SVGGraphics(bounds: bounds)
        if let background {
            graphics.fillBackground(background)
        }
        draw(graphics)
        return graphics.makeData()
    }
}
