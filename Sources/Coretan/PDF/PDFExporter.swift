import Foundation
import PDFKit
import UIKit

/// Merges paper, PDF background and ink into a flat PDF. Annotations are drawn
/// from the stroke data (not screenshots) so export stays vector-sharp.
enum PDFExporter {

    struct Options {
        var includeAnnotations = true
        var quality: CGFloat = 1.0        // render scale multiplier
        var pageRange: ClosedRange<Int>?
    }

    static func export(notebook: NotebookMeta, pages: [PageMeta], options: Options = Options()) -> Data {
        let mgr = NotebookManager()
        let store = DocumentStore.shared
        let bundle = store.bundleURL(for: notebook.id)
        let range = options.pageRange ?? 0...(max(pages.count - 1, 0))
        let selected = pages.enumerated().filter { range.contains($0.offset) }.map(\.element)

        let out = NSMutableData()
        var mediaBox = CGRect.zero
        guard let consumer = CGDataConsumer(data: out as CFMutableData) else { return Data() }

        var firstPage = true
        for p in selected {
            let size = p.size.cg
            mediaBox = CGRect(origin: .zero, size: size)

            let renderer = UIGraphicsImageRenderer(size: size, format: {
                let f = UIGraphicsImageRendererFormat.default()
                f.scale = options.quality
                f.opaque = true
                return f
            }())
            let composed = renderer.image { ctx in
                let c = ctx.cgContext
                UIColor.white.setFill(); c.fill(mediaBox)

                // 1) PDF background if this page came from an import
                if let asset = p.thumbnailName {
                    let assetURL = bundle.appendingPathComponent("assets/\(asset)")
                    if let img = UIImage(contentsOfFile: assetURL.path) { img.draw(in: mediaBox) }
                } else {
                    TemplateRenderer.image(for: p.template, size: size).draw(at: .zero)
                }

                // 2) ink
                if options.includeAnnotations {
                    let strokes = mgr.loadStrokes(pageID: p.id, notebookID: notebook.id)
                    StrokeRenderer.draw(strokes, in: c, layers: DefaultLayers.all)
                }
            }

            guard let img = composed.cgImage,
                  let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { continue }
            if firstPage { }
            ctx.beginPDFPage(nil)
            ctx.draw(img, in: mediaBox)
            ctx.endPDFPage()
            firstPage = false
            ctx.closePDF()
        }
        return out as Data
    }

    /// Writes to a temporary file and returns its URL for the share sheet.
    static func exportToFile(notebook: NotebookMeta, pages: [PageMeta], options: Options = Options()) -> URL? {
        let data = export(notebook: notebook, pages: pages, options: options)
        guard !data.isEmpty else { return nil }
        let name = notebook.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        try? data.write(to: url, options: .atomic)
        return url
    }
}

enum DefaultLayers {
    static let all: [InkLayer] = []
}
