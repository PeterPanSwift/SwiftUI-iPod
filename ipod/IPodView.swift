import SwiftUI

/// The front face of a 2001 1st‑generation iPod: white acrylic over a stainless rim,
/// a 2" monochrome LCD and the mechanical scroll wheel ringed by four buttons.
struct IPodView: View {
    let model: IPodModel
    @FocusState private var isFocused: Bool

    /// Real device is 102 × 61.8 mm.
    private let aspect: CGFloat = 1.65

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 40, (geo.size.height - 40) / aspect, 440)
            device(width: max(width, 160))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(.upArrow) { model.rotate(-1); return .handled }
        .onKeyPress(.downArrow) { model.rotate(1); return .handled }
        .onKeyPress(.leftArrow) { model.press(.previous); return .handled }
        .onKeyPress(.rightArrow) { model.press(.next); return .handled }
        .onKeyPress(.return) { model.select(); return .handled }
        .onKeyPress(.space) { model.press(.playPause); return .handled }
        .onKeyPress(.escape) { model.press(.menu); return .handled }
        .onKeyPress(.delete) { model.press(.menu); return .handled }
    }

    private func device(width w: CGFloat) -> some View {
        let height = w * aspect
        let screenWidth = w * 0.655
        return ZStack(alignment: .top) {
            // Polished stainless steel rim peeking around the front.
            RoundedRectangle(cornerRadius: w * 0.13, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.93), Color(white: 0.62), Color(white: 0.88), Color(white: 0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))

            // White polycarbonate face under a clear acrylic layer.
            RoundedRectangle(cornerRadius: w * 0.115, style: .continuous)
                .fill(LinearGradient(
                    colors: [.white, Color(red: 0.965, green: 0.97, blue: 0.975), Color(red: 0.92, green: 0.925, blue: 0.935)],
                    startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: w * 0.115, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white, Color(white: 0.8)], startPoint: .top, endPoint: .bottom),
                                      lineWidth: w * 0.006)
                }
                .overlay(alignment: .top) {
                    // Soft reflection on the acrylic.
                    RoundedRectangle(cornerRadius: w * 0.1, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .frame(height: height * 0.3)
                        .padding(w * 0.012)
                        .blendMode(.screen)
                }
                .padding(w * 0.017)

            VStack(spacing: 0) {
                screen(width: screenWidth, deviceWidth: w)
                    .padding(.top, w * 0.135)
                Spacer(minLength: 0)
                WheelView(model: model, diameter: w * 0.78)
                    .padding(.bottom, w * 0.12)
            }
        }
        .frame(width: w, height: height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: w * 0.06, y: w * 0.04)
    }

    private func screen(width: CGFloat, deviceWidth w: CGFloat) -> some View {
        LCDView(model: model, u: width / 160)
            .frame(width: width, height: width * 0.8)
            .clipShape(RoundedRectangle(cornerRadius: w * 0.006))
            .overlay {
                // Glare across the protective window.
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.10), location: 0),
                    .init(color: .white.opacity(0.02), location: 0.45),
                    .init(color: .clear, location: 0.46),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
            }
            .padding(w * 0.018)
            .background {
                RoundedRectangle(cornerRadius: w * 0.022, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.42)], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: w * 0.022, style: .continuous)
                            .strokeBorder(Color(white: 0.78), lineWidth: w * 0.004)
                    }
            }
    }
}

// MARK: - Scroll wheel

struct WheelView: View {
    let model: IPodModel
    let diameter: CGFloat

    private enum Zone: Equatable {
        case center, wheel, button(WheelButton)
    }

    /// Fractions of the outer diameter.
    private let wheelRatio: CGFloat = 0.72
    private let centerRatio: CGFloat = 0.34
    /// One click every 15° of rotation.
    private let step = Double.pi / 12

    @State private var zone: Zone?
    @State private var lastAngle: Double?
    @State private var accumulated = 0.0
    @State private var longPressTask: Task<Void, Never>?
    @State private var longPressFired = false

    var body: some View {
        let d = diameter
        ZStack {
            // Outer ring holding the four buttons.
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.985), Color(white: 0.93)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color(white: 0.78), lineWidth: d * 0.006))
                .shadow(color: .black.opacity(0.08), radius: d * 0.01, y: d * 0.004)

            if case .button(let button) = zone {
                ButtonSegment(angle: angle(of: button), inner: wheelRatio / 2, outer: 0.5)
                    .fill(.black.opacity(0.07))
            }

            labels(d)

            // Mechanical wheel.
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.955), Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().fill(.black.opacity(zone == .wheel ? 0.03 : 0)))
                .overlay(Circle().strokeBorder(
                    LinearGradient(colors: [Color(white: 0.68), Color(white: 0.88)], startPoint: .top, endPoint: .bottom),
                    lineWidth: d * 0.008))
                .frame(width: d * wheelRatio, height: d * wheelRatio)

            // Center select button.
            Circle()
                .fill(LinearGradient(colors: [.white, Color(white: 0.94)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().fill(.black.opacity(zone == .center ? 0.07 : 0)))
                .overlay(Circle().strokeBorder(
                    LinearGradient(colors: [Color(white: 0.9), Color(white: 0.7)], startPoint: .top, endPoint: .bottom),
                    lineWidth: d * 0.007))
                .shadow(color: .black.opacity(0.12), radius: d * 0.012, y: d * 0.006)
                .frame(width: d * centerRatio, height: d * centerRatio)
        }
        .frame(width: d, height: d)
        .contentShape(Circle())
        .gesture(drag)
        .sensoryFeedback(.selection, trigger: model.clickCount)
    }

    private func labels(_ d: CGFloat) -> some View {
        let radius = d * (0.5 + wheelRatio / 2) / 2
        let color = Color(white: 0.6)
        let iconSize = d * 0.05
        return ZStack {
            Text("MENU")
                .font(.system(size: d * 0.05, weight: .semibold))
                .tracking(d * 0.004)
                .offset(y: -radius)
            Image(systemName: "backward.end.alt.fill")
                .font(.system(size: iconSize))
                .offset(x: -radius)
            Image(systemName: "forward.end.alt.fill")
                .font(.system(size: iconSize))
                .offset(x: radius)
            Image(systemName: "playpause.fill")
                .font(.system(size: iconSize))
                .offset(y: radius)
        }
        .foregroundStyle(color)
        .allowsHitTesting(false)
    }

    private func angle(of button: WheelButton) -> Angle {
        switch button {
        case .next: .degrees(0)
        case .playPause: .degrees(90)
        case .previous: .degrees(180)
        case .menu: .degrees(270)
        }
    }

    // MARK: Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if zone == nil { begin(at: value.startLocation) }
                switch zone {
                case .button:
                    // Sliding off a button turns the touch into a spin, which is friendlier on glass.
                    if hypot(value.translation.width, value.translation.height) > diameter * 0.08 {
                        longPressTask?.cancel()
                        zone = .wheel
                        lastAngle = polarAngle(of: value.location)
                    }
                case .wheel:
                    spin(to: value.location)
                default:
                    break
                }
            }
            .onEnded { _ in
                longPressTask?.cancel()
                if !longPressFired {
                    switch zone {
                    case .button(let button): model.press(button)
                    case .center: model.select()
                    default: break
                    }
                }
                zone = nil
                lastAngle = nil
                accumulated = 0
                longPressFired = false
            }
    }

    private func begin(at point: CGPoint) {
        let r = hypot(point.x - diameter / 2, point.y - diameter / 2) / diameter
        if r <= centerRatio / 2 {
            zone = .center
        } else if r <= wheelRatio / 2 {
            zone = .wheel
            lastAngle = polarAngle(of: point)
        } else {
            let degrees = polarAngle(of: point) * 180 / .pi
            let button: WheelButton = switch degrees {
            case -135 ..< -45: .menu
            case -45 ..< 45: .next
            case 45 ..< 135: .playPause
            default: .previous
            }
            zone = .button(button)
            if button == .menu || button == .playPause {
                longPressTask = Task {
                    try? await Task.sleep(for: .seconds(button == .menu ? 0.8 : 1.5))
                    guard !Task.isCancelled else { return }
                    longPressFired = true
                    model.longPress(button)
                }
            }
        }
    }

    private func spin(to point: CGPoint) {
        guard hypot(point.x - diameter / 2, point.y - diameter / 2) > diameter * 0.08 else { return }
        let angle = polarAngle(of: point)
        if let lastAngle {
            var delta = angle - lastAngle
            if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
            accumulated += delta
            while accumulated >= step {
                model.rotate(1)
                accumulated -= step
            }
            while accumulated <= -step {
                model.rotate(-1)
                accumulated += step
            }
        }
        lastAngle = angle
    }

    /// Angle in radians, 0 pointing right and increasing clockwise on screen.
    private func polarAngle(of point: CGPoint) -> Double {
        atan2(point.y - diameter / 2, point.x - diameter / 2)
    }
}

/// A 90° slice of the outer ring, used to show which button is held down.
private struct ButtonSegment: Shape {
    let angle: Angle
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let size = min(rect.width, rect.height)
        var path = Path()
        path.addArc(center: center, radius: size * outer, startAngle: angle - .degrees(45), endAngle: angle + .degrees(45), clockwise: false)
        path.addArc(center: center, radius: size * inner, startAngle: angle + .degrees(45), endAngle: angle - .degrees(45), clockwise: true)
        path.closeSubpath()
        return path
    }
}
