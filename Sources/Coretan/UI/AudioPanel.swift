import SwiftUI

/// Recording, transcript and replay, bound to the current notebook.
struct AudioPanel: View {
    let notebookID: UUID
    let pageID: UUID?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var replay = NoteReplay()
    @State private var segments: [TranscriptSegment] = []
    @State private var summary = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    recorderCard
                    if recorder.isRecording || recorder.fileURL != nil { timeline }
                    if !segments.isEmpty { transcriptCard }
                    if !summary.isEmpty { summaryCard }
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Rekaman")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } }
            }
        }
    }

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(recorder.isRecording ? Color.red : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(recorder.isRecording ? (recorder.isPaused ? "Dijeda" : "Merekam") : "Siap merekam")
                    .font(.headline)
                Spacer()
                Text(AudioRecorder.formatted(recorder.elapsed)).monospacedDigit()
            }
            levelMeter
            HStack(spacing: 10) {
                if !recorder.isRecording {
                    Button {
                        recorder.requestPermission { ok in
                            if ok { recorder.start(notebookID: notebookID, pageID: pageID) }
                            else { errorText = "Izin mikrofon ditolak. Aktifkan di Pengaturan iOS." }
                        }
                    } label: { Label("Mulai", systemImage: "record.circle") }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { recorder.isPaused ? recorder.resume() : recorder.pause() } label: {
                        Label(recorder.isPaused ? "Lanjut" : "Jeda", systemImage: recorder.isPaused ? "play" : "pause")
                    }
                    Button(role: .destructive) { recorder.stop() } label: { Label("Stop", systemImage: "stop") }
                }
                Spacer()
                Button { Task { await transcribe() } } label: { Label("Transkrip", systemImage: "text.bubble") }
                    .disabled(recorder.fileURL == nil || busy)
            }
        }
        .padding().background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var levelMeter: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(recorder.levels.suffix(80).indices, id: \.self) { i in
                let v = recorder.levels.suffix(80)[i]
                Capsule().fill(Color.accentColor.opacity(0.7))
                    .frame(width: 3, height: max(2, v * 40))
            }
            if recorder.levels.isEmpty { Text("—").foregroundStyle(.secondary).font(.caption) }
        }
        .frame(height: 42)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { replay.isPlaying ? replay.pause() : replay.play() } label: {
                    Image(systemName: replay.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.title2)
                }
                Text(AudioRecorder.formatted(replay.position)).monospacedDigit().font(.caption)
                Slider(value: Binding(
                    get: { replay.position },
                    set: { replay.seek(to: $0) }
                ), in: 0...max(replay.duration, 1))
                Text(AudioRecorder.formatted(replay.duration)).monospacedDigit().font(.caption)
            }
        }
        .padding().background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transkrip").font(.headline)
            ForEach(segments) { s in
                HStack(alignment: .top, spacing: 8) {
                    Text(AudioRecorder.formatted(s.start)).font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                        .onTapGesture { replay.seek(to: s.start) }
                    Text(s.text).font(.callout)
                }
            }
            Button { Task { await summarize() } } label: { Label("Buat catatan rapat", systemImage: "list.bullet.rectangle") }
                .buttonStyle(.bordered).disabled(busy)
        }
        .padding().background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catatan rapat").font(.headline)
            Text(summary).textSelection(.enabled)
            Button { UIPasteboard.general.string = summary } label: { Label("Salin", systemImage: "doc.on.doc") }
                .buttonStyle(.bordered)
        }
        .padding().background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func transcribe() async {
        guard let url = recorder.fileURL else { return }
        busy = true; errorText = nil
        do { segments = try await AIAssistant.shared.transcribe(audioURL: url) }
        catch { errorText = error.localizedDescription }
        busy = false
    }

    private func summarize() async {
        busy = true; errorText = nil
        do { summary = try await AIAssistant.shared.meetingNotes(from: segments) }
        catch { errorText = error.localizedDescription }
        busy = false
    }
}
