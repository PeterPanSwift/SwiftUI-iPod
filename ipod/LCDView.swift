import SwiftUI

extension Color {
    static let lcdUnlit = Color(red: 0.63, green: 0.67, blue: 0.61)
    static let lcdLit = Color(red: 0.69, green: 0.82, blue: 0.87)
    static let lcdInk = Color(red: 0.09, green: 0.11, blue: 0.11)
}

/// The 160×128 monochrome screen. All measurements are in LCD pixels multiplied by `u`.
struct LCDView: View {
    let model: IPodModel
    let u: CGFloat

    private var background: Color { model.isBacklightOn ? .lcdLit : .lcdUnlit }
    private var ink: Color { Color.lcdInk.opacity(model.isAsleep ? 0 : 0.35 + 0.65 * model.contrast) }

    var body: some View {
        ZStack {
            background
            if !model.isAsleep {
                VStack(spacing: 0) {
                    TitleBar(model: model, u: u)
                    ZStack {
                        content(for: model.page)
                            .id(model.stack.count)
                            .transition(slide)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
            }
            PixelGrid(u: u)
            LinearGradient(colors: [.black.opacity(0.18), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08))
                .allowsHitTesting(false)
        }
        .foregroundStyle(ink)
        .environment(\.lcdBackground, background)
        .animation(.easeOut(duration: 0.12), value: model.isBacklightOn)
    }

    private var slide: AnyTransition {
        let forward = model.navigatingForward
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal: .move(edge: forward ? .leading : .trailing)
        )
    }

    @ViewBuilder
    private func content(for page: Page) -> some View {
        switch page.screen {
        case .nowPlaying: NowPlayingScreen(model: model, u: u)
        case .about: AboutScreen(songCount: model.songs.count, u: u)
        case .contrast: ContrastScreen(contrast: model.contrast, u: u)
        default: MenuScreen(rows: model.rows(for: page.screen), page: page, u: u)
        }
    }
}

extension EnvironmentValues {
    @Entry var lcdBackground: Color = .lcdUnlit
}

func lcdFont(_ size: CGFloat, _ u: CGFloat) -> Font {
    .system(size: size * u, weight: .bold)
}

private func timeString(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    return "\(total / 60):" + String(format: "%02d", total % 60)
}

// MARK: - Title bar

private struct TitleBar: View {
    let model: IPodModel
    let u: CGFloat

    var body: some View {
        ZStack {
            Text(model.title(for: model.page.screen))
                .font(lcdFont(11, u))
                .lineLimit(1)
                .padding(.horizontal, 20 * u)
            HStack {
                if model.player.current != nil {
                    Image(systemName: model.player.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 7 * u, weight: .black))
                }
                Spacer()
                Battery(u: u)
            }
            .padding(.horizontal, 5 * u)
        }
        .frame(height: 18 * u)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: max(1, u))
        }
    }
}

private struct Battery: View {
    let u: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: u)
                .strokeBorder(lineWidth: u)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .frame(width: 8 * u)
                        .padding(2 * u)
                }
                .frame(width: 14 * u, height: 7 * u)
            Rectangle().frame(width: 1.5 * u, height: 3 * u)
        }
    }
}

// MARK: - Screens

private struct MenuScreen: View {
    let rows: [MenuRow]
    let page: Page
    let u: CGFloat

    var body: some View {
        let top = min(page.top, max(rows.count - 1, 0))
        let visible = rows.isEmpty ? [] : Array(rows[top..<min(top + IPodModel.visibleRows, rows.count)])
        let selectedID = rows.indices.contains(page.selection) ? rows[page.selection].id : nil

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(visible) { row in
                    MenuRowView(row: row, isSelected: row.id == selectedID, u: u)
                }
                Spacer(minLength: 0)
            }
            if rows.count > IPodModel.visibleRows {
                ScrollBar(total: rows.count, top: top, u: u)
            }
        }
        .padding(.top, 1 * u)
    }
}

private struct MenuRowView: View {
    let row: MenuRow
    let isSelected: Bool
    let u: CGFloat
    @Environment(\.lcdBackground) private var background

    var body: some View {
        HStack(spacing: 4 * u) {
            Text(row.title)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let value = row.value {
                Text(value)
                    .lineLimit(1)
                    .fixedSize()
            }
            if row.chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8 * u, weight: .black))
            }
        }
        .font(lcdFont(11, u))
        .padding(.horizontal, 4 * u)
        .frame(height: 17.5 * u)
        .foregroundStyle(isSelected ? AnyShapeStyle(background) : AnyShapeStyle(.foreground))
        .background {
            if isSelected { Rectangle().fill(.foreground) }
        }
    }
}

private struct ScrollBar: View {
    let total: Int
    let top: Int
    let u: CGFloat

    var body: some View {
        GeometryReader { geo in
            let visible = CGFloat(IPodModel.visibleRows) / CGFloat(total)
            let height = max(geo.size.height * visible, 6 * u)
            let offset = (geo.size.height - height) * CGFloat(top) / CGFloat(total - IPodModel.visibleRows)
            ZStack(alignment: .top) {
                Rectangle().strokeBorder(lineWidth: u)
                Rectangle()
                    .frame(height: height)
                    .offset(y: offset)
            }
        }
        .frame(width: 6 * u)
        .padding(.trailing, 2 * u)
        .padding(.vertical, 2 * u)
    }
}

private struct NowPlayingScreen: View {
    let model: IPodModel
    let u: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let player = model.player
            if let song = player.current {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(player.index + 1) of \(player.queue.count)")
                        Spacer()
                    }
                    .font(lcdFont(9, u))
                    .padding(.top, 3 * u)

                    Spacer(minLength: 0)
                    VStack(spacing: 2 * u) {
                        Text(song.title).font(lcdFont(11, u))
                        Text(song.artist).font(lcdFont(10, u))
                        if song.album != Song.unknownAlbum {
                            Text(song.album).font(lcdFont(10, u))
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)

                    bar(player: player)
                        .padding(.bottom, 4 * u)
                }
                .padding(.horizontal, 7 * u)
            }
        }
    }

    @ViewBuilder
    private func bar(player: AudioPlayer) -> some View {
        let duration = max(player.duration, 0.1)
        let elapsed = player.currentTime
        switch model.nowPlayingMode {
        case .volume:
            HStack(spacing: 4 * u) {
                Image(systemName: "speaker.fill").font(.system(size: 7 * u))
                LCDBar(fraction: player.volume, segmented: true, u: u)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 7 * u))
            }
            .frame(height: 22 * u)
        case .progress, .scrub:
            VStack(spacing: 2 * u) {
                LCDBar(fraction: elapsed / duration, segmented: false, u: u)
                    .overlay(alignment: .leading) {
                        if model.nowPlayingMode == .scrub {
                            GeometryReader { geo in
                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 9 * u, weight: .black))
                                    .position(x: geo.size.width * min(elapsed / duration, 1), y: geo.size.height / 2)
                            }
                        }
                    }
                HStack {
                    Text(timeString(elapsed))
                    Spacer()
                    Text("-" + timeString(duration - elapsed))
                }
                .font(lcdFont(9, u))
                .monospacedDigit()
            }
        }
    }
}

private struct LCDBar: View {
    let fraction: Double
    let segmented: Bool
    let u: CGFloat

    var body: some View {
        GeometryReader { geo in
            let inner = geo.size.width - 4 * u
            ZStack(alignment: .leading) {
                Rectangle().strokeBorder(lineWidth: u)
                if segmented {
                    let count = 20
                    let filled = Int((fraction * Double(count)).rounded())
                    HStack(spacing: u) {
                        ForEach(0..<count, id: \.self) { index in
                            Rectangle().opacity(index < filled ? 1 : 0)
                        }
                    }
                    .padding(2 * u)
                } else {
                    Rectangle()
                        .frame(width: inner * min(max(fraction, 0), 1))
                        .padding(2 * u)
                }
            }
        }
        .frame(height: 8 * u)
    }
}

private struct AboutScreen: View {
    let songCount: Int
    let u: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text("iPod")
                .font(lcdFont(14, u))
                .frame(height: 22 * u)
            ForEach([("Songs", "\(songCount)"), ("Capacity", "4.6 GB"), ("Available", "4.5 GB"), ("Version", "1.0")], id: \.0) { item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text(item.1)
                }
                .font(lcdFont(10, u))
                .frame(height: 15 * u)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8 * u)
        .padding(.top, 4 * u)
    }
}

private struct ContrastScreen: View {
    let contrast: Double
    let u: CGFloat

    var body: some View {
        HStack(spacing: 5 * u) {
            Image(systemName: "circle.lefthalf.filled")
            LCDBar(fraction: contrast, segmented: true, u: u)
            Image(systemName: "circle.fill")
        }
        .font(.system(size: 9 * u, weight: .bold))
        .padding(.horizontal, 10 * u)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Glass & pixels

/// A faint dot‑matrix grid so the screen reads as a real LCD.
private struct PixelGrid: View {
    let u: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let step = 2 * u
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(.black.opacity(0.035)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}
