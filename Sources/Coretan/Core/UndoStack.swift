import Foundation

/// Operation-based undo/redo. Strokes are never destructively edited, so an
/// operation only has to record what changed and can be inverted exactly.
enum EditorOp {
    case addStroke(InkStroke)
    case removeStrokes([(index: Int, stroke: InkStroke)])
    case transformStrokes(ids: [UUID], from: [CGPoint], to: [CGPoint])
    case addPage(pageID: UUID, at: Int)
    case removePage(pageID: UUID, at: Int)
    case reorderPage(from: Int, to: Int)

    var label: String {
        switch self {
        case .addStroke: return "Tulis"
        case .removeStrokes: return "Hapus"
        case .transformStrokes: return "Pindah"
        case .addPage: return "Tambah halaman"
        case .removePage: return "Hapus halaman"
        case .reorderPage: return "Urutkan halaman"
        }
    }
}

final class UndoStack: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var undoLabel: String?
    @Published private(set) var redoLabel: String?

    private var undoItems: [EditorOp] = []
    private var redoItems: [EditorOp] = []
    private let limit = 200

    /// Applies an op and pushes it. `invert` receives the op to revert it.
    func perform(_ op: EditorOp, apply: (EditorOp) -> Void, invert: (EditorOp) -> EditorOp?) {
        apply(op)
        undoItems.append(op)
        if undoItems.count > limit { undoItems.removeFirst() }
        redoItems.removeAll()
        refresh()
    }

    func undo(apply: (EditorOp) -> Void, invert: (EditorOp) -> EditorOp?) {
        guard let op = undoItems.popLast() else { return }
        guard let inv = invert(op) else { refresh(); return }
        apply(inv)
        redoItems.append(op)
        refresh()
    }

    func redo(apply: (EditorOp) -> Void, invert: (EditorOp) -> EditorOp?) {
        guard let op = redoItems.popLast() else { return }
        apply(op)
        undoItems.append(op)
        refresh()
    }

    func clearHistory() { undoItems.removeAll(); redoItems.removeAll(); refresh() }

    private func refresh() {
        canUndo = !undoItems.isEmpty
        canRedo = !redoItems.isEmpty
        undoLabel = undoItems.last?.label
        redoLabel = redoItems.last?.label
    }
}
