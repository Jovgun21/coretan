import Foundation
import PDFKit
import UIKit

/// Imports PDFs as page backgrounds. Pages are rasterised once at a crisp scale
/// and cached, so zooming annotations never touches the original document.
enum PDFImporter {

    static func importPDF(from url: URL, into notebookID: UUID, store: DocumentStore,
                          after index: Int, completion: @escaping ([PageMeta]) -> Void) {
        let mgr = NotebookManager()
        let dir = store.bundleURL(for: notebookID)

        guard url.startAccessingSecurityScopedResource() else {
            completion([]); return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let doc = PDFDocument(url: url) else { completion([]); return }

        // copy the source PDF into the notebook bundle so the notebook is self-contained
        let pdfDir = dir.appendingPathComponent("pdf", isDirectory: true)
        try? FileManager.default.createDirectory(at: pdfDir, withIntermediateDirectories: true)
        let pdfName = "\(UUID().uuidString).pdf"
        if let d = try? Data(contentsOf: url) {
            try? d.write(to: pdfDir.appendingPathComponent(pdfName), options: .atomic)
        }

        let assetsDir = dir.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        var created: [PageMeta] = []
        var list = mgr.loadPages(for: notebookID)

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let img = render(page: page, bounds: bounds, scale: scale)
            let assetName = "\(UUID().uuidString).jpg"
            if let jpg = img.jpegData(compressionQuality: 0.85) {
                try? jpg.write(to: assetsDir.appendingPathComponent(assetName))
            }
            let meta = PageMeta(id: UUID(), notebookID: notebookID, index: index + 1 + i,
                                size: PageSize(width: Float(bounds.width), height: Float(bounds.height)),
                                template: TemplateSpec(kind: .blank, paperColorHex: "#FFFFFF",
                                                       lineSpacing: nil, gridSize: nil, orientationLocked: true),
                                thumbnailName: assetName)
            list.insert(meta, at: min(index + 1 + i, list.count))
            created.append(meta)
        }
        mgr.savePages(list, for: notebookID)
        completion(created)
    }

    static func render(page: PDFPage, bounds: CGRect, scale: CGFloat) -> UIImage {
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            UIColor.white.setFill()
            c.fill(CGRect(origin: .zero, size: size))
            c.saveGState()
            c.scaleBy(x: scale, y: scale)
            c.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: c)
            c.restoreGState()
        }
    }
}
