import SwiftUI

/// Layer management: add, reorder, rename, lock, hide, delete.
/// Locked or hidden layers receive no new strokes.
struct LayerPanel: View {
    @Binding var layers: [InkLayer]
    @Environment(\.dismiss) private var dismiss
    @State private var renameTarget: InkLayer?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(layers.sorted(by: { $0.zIndex > $1.zIndex })) { layer in
                    HStack {
                        Button {
                            toggleVisible(layer)
                        } label: {
                            Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.plain)

                        Text(layer.name)

                        Spacer()

                        Button {
                            toggleLock(layer)
                        } label: {
                            Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions {
                        Button("Hapus", role: .destructive) { remove(layer) }
                    }
                    .contextMenu {
                        Button("Ubah nama") { renameTarget = layer; renameText = layer.name }
                        Button("Naikkan") { move(layer, up: true) }
                        Button("Turunkan") { move(layer, up: false) }
                    }
                }
                .onMove(perform: reorder)
            }
            .navigationTitle("Lapisan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addLayer() } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            .alert("Ubah nama lapisan", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } })) {
                TextField("Nama", text: $renameText)
                Button("Simpan") {
                    if let t = renameTarget, let i = layers.firstIndex(where: { $0.id == t.id }) {
                        layers[i].name = renameText
                    }
                    renameTarget = nil
                }
                Button("Batal", role: .cancel) { renameTarget = nil }
            }
        }
    }

    private func addLayer() {
        let top = layers.map(\.zIndex).max() ?? 0
        layers.append(InkLayer(id: UUID(), name: "Lapisan \(layers.count + 1)",
                               isVisible: true, isLocked: false, zIndex: top + 1))
    }

    private func remove(_ layer: InkLayer) {
        guard layers.count > 1 else { return }   // always keep one drawable layer
        layers.removeAll { $0.id == layer.id }
    }

    private func toggleVisible(_ layer: InkLayer) {
        guard let i = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers[i].isVisible.toggle()
    }

    private func toggleLock(_ layer: InkLayer) {
        guard let i = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers[i].isLocked.toggle()
    }

    private func move(_ layer: InkLayer, up: Bool) {
        guard let i = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers[i].zIndex += up ? 1 : -1
    }

    private func reorder(from: IndexSet, to: Int) {
        var sorted = layers.sorted { $0.zIndex > $1.zIndex }
        sorted.move(fromOffsets: from, toOffset: to)
        for (idx, l) in sorted.enumerated() {
            if let i = layers.firstIndex(where: { $0.id == l.id }) {
                layers[i].zIndex = Int32(sorted.count - idx)
            }
        }
    }
}
