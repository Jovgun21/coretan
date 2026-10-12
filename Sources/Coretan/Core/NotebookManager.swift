import Foundation

/// Page, folder and notebook operations. Every mutation routes through here so
/// ordering, trash and metadata stay consistent regardless of the UI entry point.
final class NotebookManager: ObservableObject {
    private let store: DocumentStore
    private let fm = FileManager.default

    @Published var pages: [PageMeta] = []
    @Published var folders: [FolderMeta] = []
    @Published var trash: [PageMeta] = []

    init(store: DocumentStore = .shared) { self.store = store }

    // MARK: Notebook CRUD

    func createNotebook(title: String, template: TemplateKind = .ruled, pageSize: PageSize = .a4Portrait) -> NotebookMeta {
        let nbID = UUID()
        let first = PageMeta(id: UUID(), notebookID: nbID, index: 0, size: pageSize,
                             template: TemplateSpec(kind: template, paperColorHex: "#FFFEF7",
                                                    lineSpacing: 24, gridSize: nil, orientationLocked: false),
                             thumbnailName: nil)
        let nb = NotebookMeta(id: nbID, title: title, coverAsset: nil, folderID: nil,
                              createdAt: Date(), updatedAt: Date(), pageCount: 1)
        store.saveNotebook(nb)
        savePages([first], for: nbID)
        return nb
    }

    func rename(_ nb: NotebookMeta, to title: String) -> NotebookMeta {
        var copy = nb; copy.title = title; copy.updatedAt = Date()
        store.saveNotebook(copy); return copy
    }

    func duplicate(_ nb: NotebookMeta) -> NotebookMeta {
        let src = store.bundleURL(for: nb.id)
        let newID = UUID()
        let dst = store.bundleURL(for: newID)
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
        if let items = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) {
            for item in items { try? fm.copyItem(at: item, to: dst.appendingPathComponent(item.lastPathComponent)) }
        }
        var copy = nb
        copy.id = newID; copy.title = nb.title + " copy"
        copy.createdAt = Date(); copy.updatedAt = Date()
        store.saveNotebook(copy)
        return copy
    }

    func moveToTrash(_ nb: NotebookMeta) {
        var copy = nb; copy.folderID = nil; copy.updatedAt = Date()
        let at = store.rootURL.appendingPathComponent(".trash", isDirectory: true)
        try? fm.createDirectory(at: at, withIntermediateDirectories: true)
        try? fm.moveItem(at: store.bundleURL(for: nb.id), to: at.appendingPathComponent(nb.id.uuidString))
        store.deleteNotebook(nb.id)
        _ = copy
    }

    // MARK: Folders

    func createFolder(name: String, parent: UUID?, colorHex: String? = nil) -> FolderMeta {
        let f = FolderMeta(id: UUID(), name: name, parentID: parent, colorHex: colorHex)
        folders.append(f); return f
    }

    func children(of parent: UUID?) -> [FolderMeta] { folders.filter { $0.parentID == parent } }

    // MARK: Pages

    func loadPages(for notebookID: UUID) -> [PageMeta] {
        let url = store.bundleURL(for: notebookID).appendingPathComponent("pages.json")
        guard let d = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([PageMeta].self, from: d)
        else { return [] }
        return list.sorted { $0.index < $1.index }
    }

    func savePages(_ list: [PageMeta], for notebookID: UUID) {
        let url = store.bundleURL(for: notebookID).appendingPathComponent("pages.json")
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var renumbered = list.enumerated().map { idx, p -> PageMeta in var c = p; c.index = idx; return c }
        // atomic: never leave a half-written page index behind
        if let d = try? JSONEncoder().encode(renumbered) {
            try? d.write(to: url, options: .atomic)
        }
        if notebookID == pages.first?.notebookID { pages = renumbered }
        _ = renumbered
    }

    func addPage(after index: Int, notebookID: UUID, template: TemplateKind, size: PageSize) -> PageMeta {
        var list = loadPages(for: notebookID)
        let p = PageMeta(id: UUID(), notebookID: notebookID, index: index + 1, size: size,
                         template: TemplateSpec(kind: template, paperColorHex: "#FFFEF7",
                                                lineSpacing: 24, gridSize: nil, orientationLocked: false),
                         thumbnailName: nil)
        list.insert(p, at: min(index + 1, list.count))
        savePages(list, for: notebookID)
        return p
    }

    func deletePages(ids: [UUID], notebookID: UUID, hard: Bool = false) {
        var list = loadPages(for: notebookID)
        let removed = list.filter { ids.contains($0.id) }
        list.removeAll { ids.contains($0.id) }
        if list.isEmpty {   // a notebook must always keep at least one page
            list.append(PageMeta(id: UUID(), notebookID: notebookID, index: 0, size: .a4Portrait,
                                 template: .ruled, thumbnailName: nil))
        }
        if !hard {
            trash.append(contentsOf: removed)
            // keep the ink file: it is what makes restore possible
        } else {
            for p in removed {
                try? fm.removeItem(at: store.bundleURL(for: notebookID)
                    .appendingPathComponent("pages/\(p.id.uuidString).ctnk"))
            }
        }
        savePages(list, for: notebookID)
    }

    func duplicatePages(ids: [UUID], notebookID: UUID) {
        var list = loadPages(for: notebookID)
        let dir = store.bundleURL(for: notebookID).appendingPathComponent("pages", isDirectory: true)
        for id in ids {
            guard let idx = list.firstIndex(where: { $0.id == id }) else { continue }
            let src = list[idx]
            let newID = UUID()
            var copy = src; copy.id = newID
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? fm.copyItem(at: dir.appendingPathComponent("\(src.id.uuidString).ctnk"),
                             to: dir.appendingPathComponent("\(newID.uuidString).ctnk"))
            list.insert(copy, at: idx + 1)
        }
        savePages(list, for: notebookID)
    }

    func movePage(from: Int, to: Int, notebookID: UUID) {
        var list = loadPages(for: notebookID)
        guard from >= 0, from < list.count, to >= 0, to < list.count, from != to else { return }
        let p = list.remove(at: from)
        list.insert(p, at: to)
        savePages(list, for: notebookID)
    }

    func rotate(pageID: UUID, notebookID: UUID) {
        var list = loadPages(for: notebookID)
        guard let i = list.firstIndex(where: { $0.id == pageID }) else { return }
        list[i].size = list[i].size.rotated
        savePages(list, for: notebookID)
    }

    func restoreFromTrash(_ ids: [UUID], notebookID: UUID) {
        var list = loadPages(for: notebookID)
        let back = trash.filter { ids.contains($0.id) }
        list.append(contentsOf: back)
        trash.removeAll { ids.contains($0.id) }
        savePages(list, for: notebookID)
    }

    // MARK: Ink blob access

    func inkURL(pageID: UUID, notebookID: UUID) -> URL {
        store.bundleURL(for: notebookID)
            .appendingPathComponent("pages", isDirectory: true)
            .appendingPathComponent("\(pageID.uuidString).ctnk")
    }

    func loadStrokes(pageID: UUID, notebookID: UUID) -> [InkStroke] {
        guard let d = try? Data(contentsOf: inkURL(pageID: pageID, notebookID: notebookID)),
              let pages = InkCodec.decode(d), let first = pages.first
        else { return [] }
        return first.strokes
    }

    func saveStrokes(_ strokes: [InkStroke], pageID: UUID, notebookID: UUID,
                     size: PageSize, template: TemplateSpec, layers: [InkLayer] = []) {
        let url = inkURL(pageID: pageID, notebookID: notebookID)
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = InkCodec.PagePayload(pageID: pageID, size: size, template: template,
                                           backgroundAsset: nil, layers: layers,
                                           strokes: strokes, media: [])
        if let d = InkCodec.encode(pages: [payload]).nonEmpty {
            try? d.write(to: url, options: .atomic)
        }
    }
}

private extension Data {
    var nonEmpty: Data? { isEmpty ? nil : self }
}
