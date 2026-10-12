import Foundation
import AVFoundation

/// Lecture recording with timestamps. Each spare stroke carries a tOffset, so
/// Note Replay can re-draw the page in the order it was written and keep it in
/// sync with the audio track.
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var levels: [CGFloat] = []
    @Published var lastError: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0
    private(set) var fileURL: URL?

    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { ok in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func start(notebookID: UUID, pageID: UUID?) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            lastError = "Tidak bisa mengaktifkan mikrofon: \(error.localizedDescription)"
            return
        }
        let dir = DocumentStore.shared.bundleURL(for: notebookID).appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            r.delegate = self
            r.record()
            recorder = r
            fileURL = url
            startedAt = Date()
            accumulated = 0
            isRecording = true
            isPaused = false
            startTimer()
        } catch {
            lastError = "Gagal merekam: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard let r = recorder, isRecording else { return }
        r.pause()
        isPaused = true
        if let s = startedAt { accumulated += Date().timeIntervalSince(s) }
        startedAt = nil
    }

    func resume() {
        guard let r = recorder, isRecording else { return }
        r.record()
        isPaused = false
        startedAt = Date()
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate(); timer = nil
        isRecording = false
        isPaused = false
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder else { return }
            r.updateMeters()
            let total = self.accumulated + (self.startedAt.map { Date().timeIntervalSince($0) } ?? 0)
            self.elapsed = total
            let power = CGFloat(r.averagePower(forChannel: 0))
            let norm = max(0, min(1, (power + 60) / 60))
            self.levels.append(norm)
            if self.levels.count > 120 { self.levels.removeFirst() }
        }
    }

    static func formatted(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
