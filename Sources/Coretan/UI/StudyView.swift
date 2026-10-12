import SwiftUI

/// Flashcard review with SM-2 scheduling and progress readout.
struct StudyView: View {
    @StateObject private var store = StudyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var session: [Flashcard] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var reviewed = 0
    @State private var started = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !started { intro }
                else if index < session.count { cardView }
                else { doneView }
            }
            .padding()
            .navigationTitle("Belajar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } }
            }
        }
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack").font(.system(size: 44)).foregroundStyle(.tint)
            Text("\(store.cards.count) kartu total").font(.headline)
            Text("\(store.dueToday.count) perlu diulang hari ini").foregroundStyle(.secondary)
            if store.cards.isEmpty {
                Text("Belum ada kartu. Buat dari panel AI → Flashcard.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Mulai sesi") {
                session = store.dueToday.isEmpty ? store.cards.shuffled() : store.dueToday
                index = 0; reviewed = 0; revealed = false; started = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.cards.isEmpty)

            Button("Sesi tambahan (semua kartu)") {
                session = store.cards.shuffled(); index = 0; reviewed = 0; revealed = false; started = true
            }
            .disabled(store.cards.isEmpty)
        }
    }

    private var cardView: some View {
        VStack(spacing: 18) {
            HStack {
                Text("\(index + 1)/\(session.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Selesai: \(reviewed)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 14) {
                Text(session[index].question).font(.title3).bold().multilineTextAlignment(.center)
                if let f = session[index].formula {
                    Text(f).font(.system(.body, design: .monospaced))
                }
                if revealed {
                    Divider()
                    Text(session[index].answer).font(.body).multilineTextAlignment(.center)
                    if let nb = session[index].sourceNotebookID {
                        Label("Sumber: \(nb.uuidString.prefix(8))", systemImage: "doc.text")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if !revealed {
                Button("Lihat jawaban") { revealed = true }
                    .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    ForEach(ReviewGrade.allCases, id: \.self) { g in
                        Button(g.label) { grade(g) }
                            .buttonStyle(.bordered)
                            .tint(tint(g))
                    }
                }
            }
        }
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(.green)
            Text("Sesi selesai").font(.headline)
            Text("\(reviewed) kartu diulas").foregroundStyle(.secondary)
            Button("Selesai") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    private func tint(_ g: ReviewGrade) -> Color {
        switch g {
        case .again: return .red
        case .hard: return .orange
        case .good: return .blue
        case .easy: return .green
        }
    }

    private func grade(_ g: ReviewGrade) {
        var card = session[index]
        SpacedRepetition.apply(g, to: &card)
        store.update(card)
        reviewed += 1
        revealed = false
        if g == .again {
            session.append(card)   // same-session repeat for lapsed cards
        }
        index += 1
    }
}
