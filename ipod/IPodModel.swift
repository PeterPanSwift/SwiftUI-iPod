import SwiftUI
import Observation

enum WheelButton {
    case menu, previous, next, playPause
}

enum SongFilter: Hashable {
    case all
    case playlist(String)
    case artist(String)
    case album(String)
}

enum Screen: Hashable {
    case main, playlists, browse, artists, albums, songs(SongFilter), settings, about, contrast, nowPlaying
}

struct Page: Equatable {
    var screen: Screen
    var selection = 0
    var top = 0
}

enum RowAction {
    case push(Screen)
    case play([Song], index: Int)
    case cycleShuffle, cycleRepeat, cycleBacklightTimer, toggleClicker
}

struct MenuRow: Identifiable {
    let id: String
    let title: String
    var value: String?
    var chevron = false
    let action: RowAction
}

enum NowPlayingMode {
    case progress, volume, scrub
}

enum BacklightTimer: CaseIterable {
    case off, two, five, ten, twenty, always

    var seconds: Double? {
        switch self {
        case .two: 2
        case .five: 5
        case .ten: 10
        case .twenty: 20
        case .off, .always: nil
        }
    }

    var label: String {
        switch self {
        case .off: "Off"
        case .always: "Always On"
        default: "\(Int(seconds!)) Seconds"
        }
    }
}

/// Everything the 1st‑generation iPod firmware keeps track of: the menu stack,
/// settings, backlight and sleep state. The wheel and buttons call into `rotate`, `select` and `press`.
@Observable
final class IPodModel {
    static let visibleRows = 6
    static let playlistName = "My Favorites"

    let player = AudioPlayer()
    @ObservationIgnored private let clicker = ClickSound()

    private(set) var songs: [Song] = []
    private(set) var stack: [Page] = [Page(screen: .main)]
    private(set) var navigatingForward = true
    private(set) var nowPlayingMode: NowPlayingMode = .progress
    private(set) var isBacklightOn = false
    private(set) var isAsleep = false
    /// Bumped on every click so the view can fire a matching haptic.
    private(set) var clickCount = 0

    private(set) var shuffle = false
    private(set) var backlightTimer: BacklightTimer = .off
    private(set) var clickerOn = true
    private(set) var contrast = 0.6

    @ObservationIgnored private var backlightTask: Task<Void, Never>?
    @ObservationIgnored private var modeTask: Task<Void, Never>?

    var page: Page { stack[stack.count - 1] }

    func load() async {
        songs = await Song.loadBundled()
    }

    // MARK: - Menus

    func title(for screen: Screen) -> String {
        switch screen {
        case .main: "iPod"
        case .playlists: "Playlists"
        case .browse: "Browse"
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs(.all): "Songs"
        case .songs(.playlist(let name)), .songs(.artist(let name)), .songs(.album(let name)): name
        case .settings: "Settings"
        case .about: "About"
        case .contrast: "Contrast"
        case .nowPlaying: "Now Playing"
        }
    }

    func rows(for screen: Screen) -> [MenuRow] {
        switch screen {
        case .main:
            var rows = [
                MenuRow(id: "playlists", title: "Playlists", chevron: true, action: .push(.playlists)),
                MenuRow(id: "browse", title: "Browse", chevron: true, action: .push(.browse)),
                MenuRow(id: "settings", title: "Settings", chevron: true, action: .push(.settings)),
                MenuRow(id: "about", title: "About", chevron: true, action: .push(.about)),
            ]
            if player.current != nil {
                rows.append(MenuRow(id: "nowPlaying", title: "Now Playing", chevron: true, action: .push(.nowPlaying)))
            }
            return rows
        case .playlists:
            return [MenuRow(id: Self.playlistName, title: Self.playlistName, chevron: true,
                            action: .push(.songs(.playlist(Self.playlistName))))]
        case .browse:
            return [
                MenuRow(id: "artists", title: "Artists", chevron: true, action: .push(.artists)),
                MenuRow(id: "albums", title: "Albums", chevron: true, action: .push(.albums)),
                MenuRow(id: "songs", title: "Songs", chevron: true, action: .push(.songs(.all))),
            ]
        case .artists:
            return unique(songs.map(\.artist)).map {
                MenuRow(id: $0, title: $0, chevron: true, action: .push(.songs(.artist($0))))
            }
        case .albums:
            return unique(songs.map(\.album)).map {
                MenuRow(id: $0, title: $0, chevron: true, action: .push(.songs(.album($0))))
            }
        case .songs(let filter):
            let list = songs(for: filter)
            return list.enumerated().map { index, song in
                MenuRow(id: song.id, title: song.title, action: .play(list, index: index))
            }
        case .settings:
            return [
                MenuRow(id: "shuffle", title: "Shuffle", value: shuffle ? "Songs" : "Off", action: .cycleShuffle),
                MenuRow(id: "repeat", title: "Repeat", value: player.repeatMode.label, action: .cycleRepeat),
                MenuRow(id: "backlight", title: "Backlight Timer", value: backlightTimer.label, action: .cycleBacklightTimer),
                MenuRow(id: "contrast", title: "Contrast", chevron: true, action: .push(.contrast)),
                MenuRow(id: "clicker", title: "Clicker", value: clickerOn ? "On" : "Off", action: .toggleClicker),
            ]
        case .about, .contrast, .nowPlaying:
            return []
        }
    }

    private func songs(for filter: SongFilter) -> [Song] {
        switch filter {
        case .all, .playlist: songs
        case .artist(let artist): songs.filter { $0.artist == artist }
        case .album(let album): songs.filter { $0.album == album }
        }
    }

    private func unique(_ names: [String]) -> [String] {
        Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Input

    func rotate(_ steps: Int) {
        guard wake() else { return }
        switch page.screen {
        case .nowPlaying:
            guard player.current != nil else { return }
            if nowPlayingMode == .scrub {
                player.seek(by: Double(steps) * 3)
                showNowPlaying(.scrub, for: 3)
                click()
            } else {
                let volume = min(max(player.volume + Double(steps) / 20, 0), 1)
                showNowPlaying(.volume, for: 2)
                guard volume != player.volume else { return }
                player.volume = volume
                click()
            }
        case .contrast:
            let value = min(max(contrast + Double(steps) / 20, 0), 1)
            guard value != contrast else { return }
            contrast = value
            click()
        case .about:
            break
        default:
            let count = rows(for: page.screen).count
            guard count > 0 else { return }
            var current = page
            let selection = min(max(current.selection + steps, 0), count - 1)
            guard selection != current.selection else { return }
            current.selection = selection
            if selection < current.top {
                current.top = selection
            } else if selection >= current.top + Self.visibleRows {
                current.top = selection - Self.visibleRows + 1
            }
            stack[stack.count - 1] = current
            click()
        }
    }

    func select() {
        guard wake() else { return }
        switch page.screen {
        case .nowPlaying:
            guard player.current != nil else { return }
            click()
            if nowPlayingMode == .scrub {
                showNowPlaying(.progress, for: nil)
            } else {
                showNowPlaying(.scrub, for: 3)
            }
        case .about, .contrast:
            break
        default:
            let rows = rows(for: page.screen)
            guard rows.indices.contains(page.selection) else { return }
            click()
            perform(rows[page.selection].action)
        }
    }

    func press(_ button: WheelButton) {
        guard wake() else { return }
        click()
        switch button {
        case .menu:
            guard stack.count > 1 else { return }
            navigate(forward: false) {
                self.stack.removeLast()
                self.nowPlayingMode = .progress
            }
        case .playPause:
            if player.current == nil {
                guard !songs.isEmpty else { return }
                player.play(songs, startAt: shuffle ? Int.random(in: songs.indices) : 0, shuffle: shuffle)
                push(.nowPlaying)
            } else {
                player.togglePlayPause()
            }
        case .next:
            player.next()
        case .previous:
            player.previous()
        }
    }

    /// Holding MENU toggles the backlight; holding PLAY puts the iPod to sleep — same as the original.
    func longPress(_ button: WheelButton) {
        switch button {
        case .menu:
            isAsleep = false
            backlightTask?.cancel()
            isBacklightOn.toggle()
        case .playPause:
            player.pause()
            backlightTask?.cancel()
            isBacklightOn = false
            isAsleep = true
        default:
            break
        }
    }

    // MARK: - Helpers

    private func perform(_ action: RowAction) {
        switch action {
        case .push(let screen):
            push(screen)
        case .play(let list, let index):
            player.play(list, startAt: index, shuffle: shuffle)
            push(.nowPlaying)
        case .cycleShuffle:
            shuffle.toggle()
        case .cycleRepeat:
            player.repeatMode = next(after: player.repeatMode)
        case .cycleBacklightTimer:
            backlightTimer = next(after: backlightTimer)
            if backlightTimer == .off {
                backlightTask?.cancel()
                isBacklightOn = false
            } else {
                lightUp()
            }
        case .toggleClicker:
            clickerOn.toggle()
        }
    }

    private func next<T: CaseIterable & Equatable>(after value: T) -> T {
        let all = Array(T.allCases)
        let index = all.firstIndex(of: value)!
        return all[(index + 1) % all.count]
    }

    private func push(_ screen: Screen) {
        guard page.screen != screen else { return }
        navigate(forward: true) {
            self.stack.append(Page(screen: screen))
        }
    }

    /// Sets the slide direction in its own update before changing the page,
    /// so the outgoing screen leaves in the matching direction.
    private func navigate(forward: Bool, _ change: @escaping () -> Void) {
        let animated = { withAnimation(.easeInOut(duration: 0.22)) { change() } }
        if navigatingForward == forward {
            animated()
        } else {
            navigatingForward = forward
            DispatchQueue.main.async(execute: animated)
        }
    }

    private func showNowPlaying(_ mode: NowPlayingMode, for seconds: Double?) {
        nowPlayingMode = mode
        modeTask?.cancel()
        guard let seconds else { return }
        modeTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            nowPlayingMode = .progress
        }
    }

    /// Returns false when the input was consumed waking the iPod from sleep.
    private func wake() -> Bool {
        defer { lightUp() }
        guard isAsleep else { return true }
        isAsleep = false
        return false
    }

    private func lightUp() {
        switch backlightTimer {
        case .off:
            break
        case .always:
            backlightTask?.cancel()
            isBacklightOn = true
        default:
            isBacklightOn = true
            backlightTask?.cancel()
            backlightTask = Task {
                try? await Task.sleep(for: .seconds(backlightTimer.seconds ?? 0))
                guard !Task.isCancelled else { return }
                isBacklightOn = false
            }
        }
    }

    private func click() {
        guard clickerOn else { return }
        clicker.play()
        clickCount += 1
    }
}
