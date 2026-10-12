import SwiftUI
import UniformTypeIdentifiers

/// Lets the toolbar reach into the live canvas (OCR, thumbnails) without
/// coupling the SwiftUI tree to UIKit internals.
final class CanvasHandle: ObservableObject {
    var snapshot: (() -> UIImage?)?
    var strokesProvider: (() -> [InkStroke])?
    var seekToStroke: ((UUID) -> Void)?
    @Published var layers: [InkLayer] = [
        InkLayer(id: UUID(), name: "Tinta", isVisible: true, isLocked: false, zIndex: 0)
    ] {
        didSet { applyLayers?(layers) }
    }
    var applyLayers: (([InkLayer]) -> Void)?
}

/// Main editing surface: zoomable page, ink canvas, toolbar, page strip, autosave.
struct EditorView: View {
    let notebook: NotebookMeta
    @StateObject private var manager = NotebookManager()
    @State private var pages: [PageMeta] = []
    @State private var currentIndex = 0
    @State private var tool: EditorTool = .pen(.pen, InkColor(r: 0.1, g: 0.1, b: 0.1, a: 1), 3)
    @State private var color: UIColor = .black
    @State private var width: CGFloat = 3
    @State private var fingerDrawing = false
    @State private var undo = UndoStack()
    @State private var showImport = false
    @State private var showExport = false
    @State private var saveStatus = "Tersimpan"
    @State private var showAudio = false
    @State private var showAI = false
    @State private var showLayers = false
    @State private var recognizedText = ""
    @StateObject private var handle = CanvasHandle()

    var body: some View {
        VStack(spacing: 0) {
            ZoomablePageView(
                pageID: pages.indices.contains(currentIndex) ? pages[currentIndex].id : UUID(),
                notebookID: notebook.id,
                pageSize: pages.indices.contains(currentIndex) ? pages[currentIndex].size : .a4Portrait,
                template: pages.indices.contains(currentIndex) ? pages[currentIndex].template : .ruled,
                tool: tool,
                fingerDrawing: fingerDrawing,
                undo: undo,
                handle: handle,
                onAutosave: { saveStatus = "Menyimpan…" },
                onSaved: { saveStatus = "Tersimpan" }
            )
            .id(pages.indices.contains(currentIndex) ? pages[currentIndex].id : UUID())

            pageStrip
            toolbar
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pages = manager.loadPages(for: notebook.id) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { undo.undo(apply: { _ in }) { _ in nil } } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!undo.canUndo)
                Button { undo.redo(apply: { _ in }) { _ in nil } } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!undo.canRedo)
                Text(saveStatus).font(.caption2).foregroundStyle(.secondary)
                Button { showAudio = true } label: { Image(systemName: "waveform") }
                Button { showAI = true } label: { Image(systemName: "sparkles") }
                Menu {
                    Button("Impor PDF") { showImport = true }
                    Button("Ekspor PDF") { showExport = true }
                    Button("Gandakan halaman") {
                        manager.duplicatePages(ids: [pages[currentIndex].id], notebookID: notebook.id)
                        pages = manager.loadPages(for: notebook.id)
                    }
                    Button("Putar halaman") {
                        manager.rotate(pageID: pages[currentIndex].id, notebookID: notebook.id)
                        pages = manager.loadPages(for: notebook.id)
                    }
                    Divider()
                    Button("Kenali tulisan tangan halaman ini") { recognize() }
                    Button("Lapisan") { showLayers = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                PDFImporter.importPDF(from: url, into: notebook.id, store: .shared,
                                      after: currentIndex) { newPages in
                    pages = manager.loadPages(for: notebook.id)
                    if let first = newPages.first, let idx = pages.firstIndex(of: first) { currentIndex = idx }
                }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(notebook: notebook, pages: pages)
        }
        .sheet(isPresented: $showAudio) {
            AudioPanel(notebookID: notebook.id,
                       pageID: pages.indices.contains(currentIndex) ? pages[currentIndex].id : nil)
        }
        .sheet(isPresented: $showAI) {
            AIPanel(notebookID: notebook.id, pageText: recognizedText)
        }
        .sheet(isPresented: $showLayers) {
            LayerPanel(layers: Binding(
                get: { handle.layers },
                set: { handle.layers = $0 }))
        }
    }

    /// Runs Vision OCR over the current page and indexes the result, so the
    /// page becomes searchable by its handwriting.
    private func recognize() {
        guard let img = handle.snapshot?(), pages.indices.contains(currentIndex) else { return }
        let pageID = pages[currentIndex].id
        SearchIndex.shared.recognizeHandwriting(in: img, pageID: pageID, notebookID: notebook.id) { text in
            recognizedText = text
        }
    }

    private var pageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { idx, p in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(idx == currentIndex ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                            .frame(width: 52, height: 68)
                            .overlay(Text("\(idx + 1)").font(.caption2))
                        if idx == currentIndex {
                            Capsule().fill(Color.accentColor).frame(width: 18, height: 3)
                        }
                    }
                    .onTapGesture { currentIndex = idx }
                    .contextMenu {
                        Button("Gandakan") { manager.duplicatePages(ids: [p.id], notebookID: notebook.id); pages = manager.loadPages(for: notebook.id) }
                        Button("Hapus", role: .destructive) {
                            manager.deletePages(ids: [p.id], notebookID: notebook.id)
                            pages = manager.loadPages(for: notebook.id)
                            currentIndex = min(currentIndex, max(pages.count - 1, 0))
                        }
                    }
                }
                Button {
                    let p = manager.addPage(after: currentIndex, notebookID: notebook.id, template: .ruled, size: .a4Portrait)
                    pages = manager.loadPages(for: notebook.id)
                    if let i = pages.firstIndex(of: p) { currentIndex = i }
                } label: {
                    Image(systemName: "plus").frame(width: 52, height: 68)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(height: 86)
        .background(.bar)
    }

    private var toolbar: some View {
        PenPalette(tool: $tool, color: $color, width: $width, fingerDrawing: $fingerDrawing)
            .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

/// Hosts the ink canvas inside a scroll view so pinch-zoom and pan never alter
/// the relative position of any object.
struct ZoomablePageView: UIViewRepresentable {
    let pageID: UUID
    let notebookID: UUID
    let pageSize: PageSize
    let template: TemplateSpec
    let tool: EditorTool
    let fingerDrawing: Bool
    let undo: UndoStack
    let handle: CanvasHandle
    let onAutosave: () -> Void
    let onSaved: () -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.maximumZoomScale = 6
        scroll.minimumZoomScale = 0.4
        scroll.bouncesZoom = true
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .systemGroupedBackground

        let canvas = InkCanvasView(frame: CGRect(origin: .zero, size: pageSize.cg))
        canvas.pageSize = pageSize
        canvas.template = template
        canvas.currentPageID = pageID
        canvas.delegate = context.coordinator
        canvas.load(strokes: NotebookManager().loadStrokes(pageID: pageID, notebookID: notebookID))
        scroll.addSubview(canvas)
        scroll.contentSize = pageSize.cg
        context.coordinator.canvas = canvas
        context.coordinator.scroll = scroll
        context.coordinator.apply(tool: tool, finger: fingerDrawing)
        context.coordinator.notebookID = notebookID
        context.coordinator.pageID = pageID
        context.coordinator.onAutosave = onAutosave
        context.coordinator.onSaved = onSaved
        handle.snapshot = { [weak canvas] in canvas?.snapshot() }
        handle.strokesProvider = { [weak canvas] in canvas?.currentStrokes() ?? [] }
        handle.applyLayers = { [weak canvas] layers in canvas?.layers = layers }
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.apply(tool: tool, finger: fingerDrawing)
        context.coordinator.canvas?.layers = handle.layers
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate, InkCanvasDelegate {
        weak var canvas: InkCanvasView?
        weak var scroll: UIScrollView?
        var notebookID: UUID = UUID()
        var pageID: UUID = UUID()
        var onAutosave: (() -> Void)?
        var onSaved: (() -> Void)?
        private var saveWork: DispatchWorkItem?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

        func apply(tool: EditorTool, finger: Bool) {
            canvas?.tool = tool
            canvas?.isUserInteractionEnabled = true
        }

        // MARK: InkCanvasDelegate

        func canvas(_ c: InkCanvasView, didFinish stroke: InkStroke, onPage pageID: UUID) { scheduleSave(c) }
        func canvas(_ c: InkCanvasView, didErase strokes: [UUID], onPage pageID: UUID) { scheduleSave(c) }
        func canvas(_ c: InkCanvasView, didTransform ids: [UUID], from: [CGPoint], to: [CGPoint]) { scheduleSave(c) }
        func canvasDidChangeSelection(_ c: InkCanvasView, ids: [UUID]) {}

        private func scheduleSave(_ c: InkCanvasView) {
            onAutosave?()
            saveWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak c] in
                guard let self, let c else { return }
                let strokes = c.currentStrokes()
                let mgr = NotebookManager()
                mgr.saveStrokes(strokes, pageID: self.pageID, notebookID: self.notebookID,
                                size: c.pageSize, template: c.template, layers: c.layers)
                // thumbnail for the page strip
                if let thumb = c.snapshot()?.jpegData(compressionQuality: 0.6) {
                    let dir = DocumentStore.shared.bundleURL(for: self.notebookID)
                        .appendingPathComponent("pages", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? thumb.write(to: dir.appendingPathComponent("\(self.pageID.uuidString).thumb.jpg"))
                }
                SearchIndex.shared.index(pageID: self.pageID, notebookID: self.notebookID, strokes: strokes)
                DispatchQueue.main.async { self.onSaved?() }
            }
            saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
        }
    }
}
