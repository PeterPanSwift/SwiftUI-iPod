import AVFoundation
import Observation

enum RepeatMode: CaseIterable {
    case off, one, all

    var label: String {
        switch self {
        case .off: "Off"
        case .one: "One"
        case .all: "All"
        }
    }
}

@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var queue: [Song] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    var repeatMode: RepeatMode = .off
    var volume = 0.6 {
        didSet { engine?.volume = Float(volume) }
    }

    @ObservationIgnored private var engine: AVAudioPlayer?

    override init() {
        super.init()
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    var current: Song? { queue.indices.contains(index) ? queue[index] : nil }
    var currentTime: TimeInterval { engine?.currentTime ?? 0 }
    var duration: TimeInterval { engine?.duration ?? current?.duration ?? 0 }

    func play(_ songs: [Song], startAt start: Int, shuffle: Bool) {
        guard songs.indices.contains(start) else { return }
        if shuffle {
            var rest = songs
            let first = rest.remove(at: start)
            queue = [first] + rest.shuffled()
            load(0, autoplay: true)
        } else {
            queue = songs
            load(start, autoplay: true)
        }
    }

    func togglePlayPause() {
        guard let engine else { return }
        if engine.isPlaying {
            engine.pause()
            isPlaying = false
        } else {
            isPlaying = engine.play()
        }
    }

    func pause() {
        engine?.pause()
        isPlaying = false
    }

    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count {
            load(index + 1, autoplay: isPlaying)
        } else if repeatMode == .all {
            load(0, autoplay: isPlaying)
        }
    }

    /// Like the real iPod: restarts the song if it is past the first few seconds, otherwise goes back a track.
    func previous() {
        guard let engine else { return }
        if engine.currentTime > 3 || (index == 0 && repeatMode != .all) {
            engine.currentTime = 0
        } else {
            load(index > 0 ? index - 1 : queue.count - 1, autoplay: isPlaying)
        }
    }

    func seek(by seconds: TimeInterval) {
        guard let engine else { return }
        engine.currentTime = min(max(engine.currentTime + seconds, 0), engine.duration - 0.1)
    }

    private func load(_ newIndex: Int, autoplay: Bool) {
        engine?.stop()
        index = newIndex
        engine = try? AVAudioPlayer(contentsOf: queue[newIndex].url)
        engine?.delegate = self
        engine?.volume = Float(volume)
        engine?.prepareToPlay()
        isPlaying = autoplay && (engine?.play() ?? false)
    }

    private func trackFinished() {
        switch repeatMode {
        case .one:
            engine?.currentTime = 0
            isPlaying = engine?.play() ?? false
        case .all:
            load(index + 1 < queue.count ? index + 1 : 0, autoplay: true)
        case .off:
            if index + 1 < queue.count {
                load(index + 1, autoplay: true)
            } else {
                load(index, autoplay: false)
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.trackFinished() }
    }
}
