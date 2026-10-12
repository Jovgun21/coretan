import SwiftUI

/// Notebook/folder browser: grid or list, nested folders, favourites, sort,
/// duplicate, move and trash.
struct LibraryView: View {
    var onSearch: () -> Void
    var onStudy: () -> Void
    var onSettings: () -> Void

    @EnvironmentObject var store: DocumentStore
    @StateObject private var manager = NotebookManager()
    @State private var notebooks: [NotebookMeta] = []
    @State private var currentFolder: UUID?
    @State private var gridMode = true
    @State private var sort: SortOption = .updated
    @State private var favourites: Set<UUID> = []
    @State private var showNew = false
    @State private var showFolderAlert = false
    @State private var newFolderName = ""
    @State private var query = ""

    enum SortOption: String, CaseIterable {
        case name = "Nama"
        case created = "Dibuat"
        case updated = "Terakhir diubah"
    }

    private var visible: [NotebookMeta] {
        var list = notebooks.filter { $0.folderID == currentFolder }
        if !query.isEmpty { list = list.filter { $0.title.localizedCaseInsensitiveContains(query) } }
        switch sort {
        case .name: list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .created: list.sort { $0.createdAt > $1.createdAt }
        case .updated: list.sort { $0.updatedAt > $1.updatedAt }
        }
        return list
    }

    private var title: String {
        manager.folders.first { $0.id == currentFolder }?.name ?? "Coretan"
    }

    var body: some View {
        Group { gridMode ? AnyView(grid) : AnyView(listView) }
            .navigationTitle(title)
            .searchable(text: $query, prompt: "Cari notebook")
            .toolbar {
                if currentFolder != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { currentFolder = nil } label: { Label("Kembali", systemImage: "chevron.left") }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Urutkan", selection: $sort) {
                            ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Button(gridMode ? "Tampilan daftar" : "Tampilan grid") { gridMode.toggle() }
                        Button("Folder baru") { showFolderAlert = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .onAppear(perform: reload)
            .sheet(isPresented: $showNew) {
                NotebookCreationSheet(defaultFolder: currentFolder) { nb in
                    store.saveNotebook(nb); reload()
                }
            }
            .alert("Folder baru", isPresented: $showFolderAlert) {
                TextField("Nama folder", text: $newFolderName)
                Button("Buat") {
                    _ = manager.createFolder(name: newFolderName.isEmpty ? "Folder" : newFolderName, parent: currentFolder)
                    newFolderName = ""; reload()
                }
                Button("Batal", role: .cancel) {}
            }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 18) {
                ForEach(manager.children(of: currentFolder)) { f in
                    FolderTile(folder: f) { currentFolder = f.id }
                }
                ForEach(visible) { nb in
                    NavigationLink(value: nb) {
                        NotebookTile(notebook: nb, isFavourite: favourites.contains(nb.id))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(nb) }
                }
            }
            .padding()
        }
        .navigationDestination(for: NotebookMeta.self) { nb in EditorView(notebook: nb) }
    }

    private var listView: some View {
        List {
            ForEach(manager.children(of: currentFolder)) { f in
                Button { currentFolder = f.id } label: { Label(f.name, systemImage: "folder") }
            }
            ForEach(visible) { nb in
                NavigationLink(value: nb) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nb.title)
                        Text("\(nb.pageCount) hal · \(nb.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contextMenu { contextMenu(nb) }
            }
            .onDelete { idx in
                for i in idx {
                    let nb = visible[i]
                    manager.moveToTrash(nb)
                }
                reload()
            }
        }
        .navigationDestination(for: NotebookMeta.self) { nb in EditorView(notebook: nb) }
    }

    private func contextMenu(_ nb: NotebookMeta) -> some View {
        Group {
            Button(favourites.contains(nb.id) ? "Hapus dari favorit" : "Tandai favorit") {
                if favourites.contains(nb.id) { favourites.remove(nb.id) } else { favourites.insert(nb.id) }
            }
            Button("Gandakan") { _ = manager.duplicate(nb); reload() }
            if !manager.folders.filter({ $0.id != nb.folderID }).isEmpty {
                Menu("Pindahkan ke folder") {
                    ForEach(manager.folders.filter { $0.id != nb.folderID }) { f in
                        Button(f.name) {
                            var copy = nb; copy.folderID = f.id
                            store.saveNotebook(copy); reload()
                        }
                    }
                }
            }
            Button("Hapus", role: .destructive) { manager.moveToTrash(nb); reload() }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 30) {
            Button(action: onSettings) { Image(systemName: "gearshape").font(.title3) }
            Spacer()
            Button(action: onSearch) { Image(systemName: "magnifyingglass").font(.title3) }
            Button(action: onStudy) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "rectangle.stack").font(.title3)
                    let due = StudyStore.shared.dueToday.count
                    if due > 0 {
                        Text("\(min(due, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .padding(3)
                            .background(Color.red, in: Circle())
                            .foregroundStyle(.white)
                            .offset(x: 9, y: -9)
                    }
                }
            }
        }
        .padding(.horizontal, 34).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 8)
    }

    private func reload() {
        notebooks = store.listNotebooks()
    }
}

struct NotebookTile: View {
    let notebook: NotebookMeta
    let isFavourite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.accentColor.opacity(0.55), .accentColor.opacity(0.18)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 168)
                    .overlay {
                        Image(systemName: "book.closed").font(.system(size: 34)).foregroundStyle(.white.opacity(0.9))
                    }
                if isFavourite {
                    Image(systemName: "star.fill").font(.caption).padding(6).foregroundStyle(.yellow)
                }
            }
            Text(notebook.title).font(.subheadline).bold().lineLimit(1)
            Text("\(notebook.pageCount) hal").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FolderTile: View {
    let folder: FolderMeta
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(height: 168)
                    .overlay {
                        Image(systemName: "folder.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                    }
                Text(folder.name).font(.subheadline).bold().lineLimit(1)
                Text("Folder").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct NotebookCreationSheet: View {
    var defaultFolder: UUID?
    var onCreate: (NotebookMeta) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var template: TemplateKind = .ruled
    @State private var pageSizeName = "A4 Potret"

    private let sizes: [(String, PageSize)] = [
        ("A4 Potret", .a4Portrait),
        ("A4 Lanskap", .a4Landscape),
        ("Letter", .letterPortrait),
        ("Rasio iPad", .ipadProportional)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Judul notebook", text: $title) }
                Section("Template awal") {
                    Picker("Template", selection: $template) {
                        ForEach(TemplateKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Ukuran halaman", selection: $pageSizeName) {
                        ForEach(sizes, id: \.0) { Text($0.0).tag($0.0) }
                    }
                }
            }
            .navigationTitle("Notebook baru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Buat") {
                        let size = sizes.first { $0.0 == pageSizeName }?.1 ?? .a4Portrait
                        let nb = NotebookMeta(id: UUID(),
                                              title: title.isEmpty ? "Tanpa judul" : title,
                                              coverAsset: nil, folderID: defaultFolder,
                                              createdAt: Date(), updatedAt: Date(), pageCount: 1)
                        let first = PageMeta(id: UUID(), notebookID: nb.id, index: 0, size: size,
                                             template: TemplateSpec(kind: template, paperColorHex: "#FFFEF7",
                                                                    lineSpacing: 24, gridSize: nil,
                                                                    orientationLocked: false),
                                             thumbnailName: nil)
                        NotebookManager().savePages([first], for: nb.id)
                        onCreate(nb)
                        dismiss()
                    }
                }
            }
        }
    }
}
