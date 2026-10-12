import SwiftUI

/// Global search across notebook names, typed text, PDF text and handwriting.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [SearchIndex.Hit] = []
    @State private var notebookHits: [NotebookMeta] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            VStack {
                if query.isEmpty {
                    ContentUnavailableView("Cari apa saja", systemImage: "magnifyingglass",
                                           description: Text("Nama notebook, teks, atau tulisan tangan yang sudah dikenali."))
                } else if hits.isEmpty && notebookHits.isEmpty && !searching {
                    ContentUnavailableView("Tidak ada hasil", systemImage: "magnifyingglass",
                                           description: Text("Tidak ditemukan \"\(query)\"."))
                } else {
                    List {
                        if !notebookHits.isEmpty {
                            Section("Notebook") {
                                ForEach(notebookHits) { nb in
                                    Label(nb.title, systemImage: "book.closed")
                                }
                            }
                        }
                        if !hits.isEmpty {
                            Section("Halaman") {
                                ForEach(hits, id: \.pageID) { h in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Notebook \(h.notebookID.uuidString.prefix(8))").font(.caption).foregroundStyle(.secondary)
                                        Text(h.snippet).font(.callout)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Cari")
            .onChange(of: query) { _, newValue in run(newValue) }
            .navigationTitle("Cari")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
        }
    }

    private func run(_ q: String) {
        searching = true
        let text = q.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { hits = []; notebookHits = []; searching = false; return }
        notebookHits = DocumentStore.shared.listNotebooks().filter {
            $0.title.localizedCaseInsensitiveContains(text)
        }
        hits = SearchIndex.shared.search(text)
        searching = false
    }
}
