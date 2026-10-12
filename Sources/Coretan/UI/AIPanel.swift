import SwiftUI
import UIKit

/// AI surface: ask, write, math, study, flashcards, image, usage.
/// Every action that would modify a note produces a preview the user accepts first.
struct AIPanel: View {
    let notebookID: UUID
    let pageText: String
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .ask
    @State private var input = ""
    @State private var output = ""
    @State private var citations: [NoteChunk] = []
    @State private var busy = false
    @State private var errorText: String?
    @State private var writeAction: AIAssistant.WriteAction = .grammar
    @State private var studyKind: AIAssistant.StudyKind = .chapterSummary
    @State private var cardCount = 8
    @State private var generatedCards: [Flashcard] = []
    @State private var generatedImage: UIImage?
    @StateObject private var meter = UsageMeter.shared

    enum Mode: String, CaseIterable {
        case ask = "Tanya"
        case write = "Tulis"
        case math = "Matematika"
        case study = "Belajar"
        case cards = "Flashcard"
        case image = "Gambar"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        inputArea
                        if mode == .write { actionPicker }
                        if mode == .study { studyPicker }
                        if mode == .cards { cardPicker }
                        runButton
                        if let errorText { errorBanner(errorText) }
                        outputArea
                    }
                    .padding()
                }
            }
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { usageBadge }
            }
        }
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode == .ask ? "Pertanyaan" : "Materi / teks")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: mode == .ask ? $input : .constant(input.isEmpty ? pageText : input))
                .frame(minHeight: 110)
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if input.isEmpty && !pageText.isEmpty && mode != .ask {
                        Text("Kosong = pakai teks halaman ini").font(.caption2)
                            .foregroundStyle(.secondary).padding(10)
                    }
                }
        }
    }

    private var actionPicker: some View {
        Picker("Aksi", selection: $writeAction) {
            ForEach(AIAssistant.WriteAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }

    private var studyPicker: some View {
        Picker("Jenis", selection: $studyKind) {
            ForEach(AIAssistant.StudyKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }

    private var cardPicker: some View {
        Stepper("Jumlah kartu: \(cardCount)", value: $cardCount, in: 3...30)
    }

    private var runButton: some View {
        Button {
            Task { await run() }
        } label: {
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Text(busy ? "Memproses…" : "Jalankan")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(busy || (input.isEmpty && pageText.isEmpty))
    }

    private var outputArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !output.isEmpty {
                Text(output).textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            if !citations.isEmpty {
                Text("Sumber").font(.caption).foregroundStyle(.secondary)
                ForEach(citations) { c in
                    Label("[hal \(c.pageNumber)] \(c.text.prefix(70))…", systemImage: "doc.text")
                        .font(.caption)
                }
            }
            if !generatedCards.isEmpty {
                Text("Kartu yang dihasilkan").font(.caption).foregroundStyle(.secondary)
                ForEach(generatedCards) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.question).font(.subheadline).bold()
                        Text(c.answer).font(.caption).foregroundStyle(.secondary)
                        Text(c.category).font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                Button("Simpan \(generatedCards.count) kartu") {
                    StudyStore.shared.add(generatedCards); generatedCards = []
                }
                .buttonStyle(.borderedProminent)
            }
            if let img = generatedImage {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var usageBadge: some View {
        Text("\(meter.remaining)/\(meter.limit)")
            .font(.caption2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(meter.remaining == 0 ? Color.red.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
    }

    private func errorBanner(_ s: String) -> some View {
        Label(s, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.red)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func run() async {
        busy = true; errorText = nil; output = ""; citations = []; generatedCards = []; generatedImage = nil
        defer { busy = false }
        do {
            switch mode {
            case .ask:
                let a = try await AIAssistant.shared.ask(input.isEmpty ? pageText : input, notebookID: notebookID)
                output = a.text; citations = a.citations
            case .write:
                output = try await AIAssistant.shared.write(input.isEmpty ? pageText : input, action: writeAction)
            case .math:
                output = try await AIAssistant.shared.math(input)
            case .study:
                output = try await AIAssistant.shared.study(input.isEmpty ? pageText : input,
                                                            kind: studyKind, notebookID: notebookID)
            case .cards:
                generatedCards = try await AIAssistant.shared.flashcards(from: input.isEmpty ? pageText : input,
                                                                        count: cardCount, notebookID: notebookID)
            case .image:
                let data = try await AIAssistant.shared.image(prompt: input)
                generatedImage = UIImage(data: data)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
