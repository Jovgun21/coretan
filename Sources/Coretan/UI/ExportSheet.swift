import SwiftUI

struct ExportSheet: View {
    let notebook: NotebookMeta
    let pages: [PageMeta]
    @Environment(\.dismiss) private var dismiss

    @State private var includeAnnotations = true
    @State private var quality: Double = 1.0
    @State private var useRange = false
    @State private var from = 1
    @State private var to = 1
    @State private var exportURL: URL?
    @State private var errorText: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Isi") {
                    Toggle("Sertakan anotasi", isOn: $includeAnnotations)
                }
                Section("Kualitas") {
                    Slider(value: $quality, in: 0.5...2.0, step: 0.25) {
                        Text("Skala render")
                    }
                    Text("\(quality, specifier: "%.2f")×").font(.caption).foregroundStyle(.secondary)
                }
                Section("Halaman") {
                    Toggle("Hanya rentang tertentu", isOn: $useRange)
                    if useRange {
                        Stepper("Dari: \(from)", value: $from, in: 1...max(pages.count, 1))
                        Stepper("Sampai: \(to)", value: $to, in: 1...max(pages.count, 1))
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
                if let exportURL {
                    Section("Hasil") {
                        ShareLink(item: exportURL) { Label("Bagikan PDF", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle("Ekspor PDF")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "Memproses…" : "Ekspor") { run() }.disabled(working)
                }
            }
        }
    }

    private func run() {
        working = true
        errorText = nil
        var opts = PDFExporter.Options()
        opts.includeAnnotations = includeAnnotations
        opts.quality = CGFloat(quality)
        if useRange {
            let lo = max(0, min(from, to) - 1)
            let hi = max(0, max(from, to) - 1)
            opts.pageRange = lo...hi
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let url = PDFExporter.exportToFile(notebook: notebook, pages: pages, options: opts)
            DispatchQueue.main.async {
                working = false
                if let url { exportURL = url } else { errorText = "Ekspor gagal: tidak ada halaman yang bisa diproses." }
            }
        }
    }
}
