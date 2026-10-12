import Foundation

/// High-level AI features. Each one is a thin, explicit prompt builder over the
/// OpenAI-compatible client, and each returns something the user can review
/// before it touches their notes.
final class AIAssistant: ObservableObject {
    private let client: AIClient
    static let shared = AIAssistant()

    init(client: AIClient = AIClient()) { self.client = client }

    // MARK: 9.1 Ask AI

    struct Answer {
        var text: String
        var citations: [NoteChunk]
        var grounded: Bool
    }

    func ask(_ question: String, notebookID: UUID?) async throws -> Answer {
        let chunks = RAGIndex.shared.retrieve(question: question, notebookID: notebookID)
        let ctx = RAGIndex.groundingContext(chunks)
        let system = """
        Kamu asisten belajar untuk catatan pribadi pengguna. Jawab dalam Bahasa Indonesia.
        Jawab HANYA berdasarkan konteks catatan di bawah. Jika konteks tidak memuat jawabannya, \
        katakan dengan jelas bahwa catatan tidak memuat informasi itu, jangan mengarang.
        Setiap klaim yang berasal dari catatan harus menyebut nomor halaman seperti [hal 3].
        """
        let prompt = "Konteks catatan:\n\(ctx)\n\nPertanyaan: \(question)"
        let text = try await client.chat([
            .init(role: "system", content: system),
            .init(role: "user", content: prompt)
        ])
        return Answer(text: text, citations: chunks, grounded: !chunks.isEmpty)
    }

    // MARK: 9.2 Writing assistant

    enum WriteAction: String, CaseIterable {
        case grammar = "Perbaiki tata bahasa"
        case spelling = "Perbaiki ejaan"
        case clarify = "Perjelas kalimat"
        case shorten = "Ringkas"
        case expand = "Perpanjang"
        case bullets = "Jadikan poin"
        case summary = "Buat ringkasan"
        case restyle = "Ubah gaya bahasa"
        case outline = "Susun kerangka belajar"
        case meeting = "Catatan rapat"
    }

    /// Returns proposed text; the caller shows a preview and applies it only on
    /// explicit acceptance (spec 5.1 / 9.2: preview + accept/reject/edit).
    func write(_ text: String, action: WriteAction, tone: String? = nil) async throws -> String {
        let system = "Kamu editor Bahasa Indonesia. Balas hanya dengan teks hasil, tanpa penjelasan tambahan."
        let instruction: String
        switch action {
        case .grammar: instruction = "Perbaiki tata bahasa tanpa mengubah makna."
        case .spelling: instruction = "Perbaiki ejaan dan tanda baca."
        case .clarify: instruction = "Perjelas kalimat yang ambigu."
        case .shorten: instruction = "Ringkas menjadi lebih pendek tanpa kehilangan inti."
        case .expand: instruction = "Perpanjang dengan penjelasan tambahan yang relevan."
        case .bullets: instruction = "Ubah menjadi daftar poin."
        case .summary: instruction = "Buat ringkasan singkat."
        case .restyle: instruction = "Ubah gaya bahasa menjadi \(tone ?? "lebih formal")."
        case .outline: instruction = "Susun kerangka belajar terstruktur dari materi ini."
        case .meeting: instruction = "Susun catatan rapat (topik, keputusan, action items)."
        }
        return try await client.chat([
            .init(role: "system", content: system),
            .init(role: "user", content: "\(instruction)\n\nTeks:\n\(text)")
        ])
    }

    // MARK: 9.3 Math assistant

    func math(_ problem: String) async throws -> String {
        let system = """
        Kamu tutor matematika. Jawab Bahasa Indonesia. Tunjukkan langkah demi langkah dan \
        jelaskan alasan tiap langkah. Gunakan notasi yang rapi. Jika soal tidak bisa kamu \
        selesaikan dengan yakin, katakan bagian mana yang tidak bisa, jangan mengarang langkah.
        """
        return try await client.chat([
            .init(role: "system", content: system),
            .init(role: "user", content: problem)
        ], temperature: 0.1)
    }

    // MARK: 9.4 Study assistant

    enum StudyKind: String, CaseIterable {
        case chapterSummary = "Ringkasan per bab"
        case keyConcepts = "Daftar konsep utama"
        case exercises = "Latihan"
        case multipleChoice = "Soal pilihan ganda"
        case essay = "Soal uraian"
        case quiz = "Kuis"
        case gaps = "Topik yang belum dikuasai"
    }

    func study(_ material: String, kind: StudyKind, count: Int = 5, difficulty: String = "sedang", notebookID: UUID?) async throws -> String {
        let chunks = RAGIndex.shared.retrieve(question: material, notebookID: notebookID)
        let ctx = RAGIndex.groundingContext(chunks)
        let system = "Kamu asisten belajar. Jawab Bahasa Indonesia, berdasarkan materi yang diberikan, dengan rujukan halaman bila ada."
        let prompt = """
        Materi sumber:
        \(ctx.isEmpty ? material : ctx)

        Tugas: \(kind.rawValue). Jumlah: \(count). Tingkat kesulitan: \(difficulty).
        """
        return try await client.chat([
            .init(role: "system", content: system),
            .init(role: "user", content: prompt)
        ])
    }

    // MARK: 8.4 AI flashcard generator

    func flashcards(from material: String, count: Int = 8, notebookID: UUID?) async throws -> [Flashcard] {
        let chunks = RAGIndex.shared.retrieve(question: material, notebookID: notebookID)
        let ctx = RAGIndex.groundingContext(chunks)
        let system = """
        Kamu membuat kartu belajar. Keluarkan HANYA JSON array valid, tanpa teks lain.
        Format: [{"question": "...", "answer": "...", "category": "definisi|rumus|konsep|latihan", "page": 3}]
        """
        let prompt = "Materi:\n\(ctx.isEmpty ? material : ctx)\n\nBuat \(count) kartu."
        let raw = try await client.chat([
            .init(role: "system", content: system),
            .init(role: "user", content: prompt)
        ], temperature: 0.2)

        return Self.parseCards(raw, notebookID: notebookID, chunks: chunks)
    }

    /// Tolerant JSON extraction: models often wrap arrays in prose or fences.
    static func parseCards(_ raw: String, notebookID: UUID?, chunks: [NoteChunk]) -> [Flashcard] {
        guard let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]") else { return [] }
        let json = String(raw[start...end])
        struct Raw: Codable { var question: String; var answer: String; var category: String?; var page: Int? }
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([Raw].self, from: data) else { return [] }
        return list.map { r in
            let pageHit = chunks.first { $0.pageNumber == r.page }
            return Flashcard(question: r.question, answer: r.answer, imageAsset: nil,
                             formula: nil, category: r.category ?? "konsep",
                             sourceNotebookID: pageHit?.notebookID ?? notebookID,
                             sourcePageID: pageHit?.pageID)
        }
    }

    // MARK: 7.3 Transcription + 7.4 meeting notes

    func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        try await client.transcribe(audioURL: audioURL)
    }

    func meetingNotes(from segments: [TranscriptSegment]) async throws -> String {
        let transcript = segments.map { "[\(Int($0.start))s] \($0.text)" }.joined(separator: "\n")
        let system = """
        Kamu menyusun catatan rapat dari transkrip. Bahasa Indonesia.
        Keluarkan: Topik Utama, Keputusan, Action Items (dengan pemilik bila disebut), Ringkasan Singkat.
        Jika transkrip tidak memuat keputusan atau action item, tulis "tidak disebutkan" — jangan mengarang.
        """
        return try await client.chat([
            .init(role: "system", content: system),
            .init(role: "user", content: "Transkrip:\n\(transcript)")
        ])
    }

    // MARK: 9.6 Image generation

    func image(prompt: String) async throws -> Data {
        try await client.generateImage(prompt: prompt)
    }
}
