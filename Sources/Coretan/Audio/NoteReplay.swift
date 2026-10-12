import Foundation

/// Reconstructs a page over time: strokes appear in the order they were drawn,
/// driven either by a playback clock or by scrubbing a timeline.
///
/// The mapping is stroke.tOffset (ms since that stroke's own start is not
/// enough) so each stroke also records when it was committed. That commit time
/// is stored alongside the audio offset in `StrokeTiming`.
struct StrokeTiming: Codable, Equatable {
    var strokeID: UUID
    /// Milliseconds from recording start at which the stroke was committed.
    var audioOffset: Int32
}

final class NoteReplay: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var position: TimeInterval = 0
    @Published private(set) var visibleStrokeIDs: Set<UUID> = []

    private var timings: [StrokeTiming] = []
    private var player: AVAudioPlayback?
    private var ticker: Timer?
    private(set) var duration: TimeInterval = 0

    func load(strokes: [InkStroke], timings: [StrokeTiming], audioURL: URL?) {
        self.timings = timings.sorted { $0.audioOffset < $1.audioOffset }
        self.duration = TimeInterval((timings.map(\.audioOffset).max() ?? 0)) / 1000.0
        if let audioURL {
            player = AVAudioPlayback(url: audioURL)
            duration = max(duration, player?.duration ?? 0)
        }
        recompute(at: 0)
    }

    func play() {
        isPlaying = true
        player?.play()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.position = self.player?.currentTime ?? (self.position + 1.0/30.0)
            self.recompute(at: self.position)
            if self.position >= self.duration { self.stop() }
        }
    }

    func pause() {
        isPlaying = false
        player?.pause()
        ticker?.invalidate(); ticker = nil
    }

    func stop() {
        isPlaying = false
        player?.pause()
        player?.seek(to: 0)
        position = 0
        ticker?.invalidate(); ticker = nil
        recompute(at: 0)
    }

    /// Jump to a moment; used by timeline scrubbing and by tapping a stroke.
    func seek(to t: TimeInterval) {
        position = t
        player?.seek(to: t)
        recompute(at: t)
    }

    /// Time of the stroke under a tap, for "tap ink to hear that moment".
    func offset(forStroke id: UUID) -> TimeInterval? {
        timings.first { $0.strokeID == id }.map { TimeInterval($0.audioOffset) / 1000 }
    }

    private func recompute(at t: TimeInterval) {
        let ms = Int32(t * 1000)
        // strokes drawn within the last 1.2s render with a fade-in feel
        let window: Int32 = 1200
        visibleStrokeIDs = Set(timings.filter { $0.audioOffset <= ms + window }.map(\.strokeID))
    }
}

/// Thin AVAudioPlayer wrapper so NoteReplay stays testable without AVFoundation.
final class AVAudioPlayback {
    private let player: AVAudioPlayer?
    init(url: URL) { player = try? AVAudioPlayer(contentsOf: url) }
    var duration: TimeInterval { player?.duration ?? 0 }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    func play() { player?.play() }
    func pause() { player?.pause() }
    func seek(to t: TimeInterval) { player?.currentTime = t }
}
