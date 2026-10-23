import SwiftUI
import AppKit

/// The notch shape: flat top that tucks into the screen edge, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let t = topRadius, b = min(bottomRadius, r.height / 2)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// macOS frosted blur of whatever is behind the window.
struct Frost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// The island's surface: Apple Liquid Glass (macOS 26+), frosted glass, or black.
struct IslandSurface<S: Shape>: View {
    let shape: S
    let style: GlassStyle
    /// Fades to solid black (used when a notch island is closed, so it matches the camera notch).
    let black: Bool
    let expanded: Bool

    var body: some View {
        ZStack {
            glass
            shape.fill(Color.black).opacity(black || style == .black ? 1 : 0)
        }
        .shadow(color: .black.opacity(expanded ? 0.4 : 0.22), radius: expanded ? 22 : 8, y: expanded ? 10 : 3)
    }

    @ViewBuilder var glass: some View {
        if style == .liquid, LiquidGlass<S>.available {
            LiquidGlass(shape: shape)
        } else if style != .black {
            ZStack {
                Frost().clipShape(shape)
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.black.opacity(0.28)], startPoint: .top, endPoint: .bottom))
                // glassy rim: bright on top, faint at the sides, a soft bounce at the bottom
                shape.stroke(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.06), Color.white.opacity(0.22)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 1)
                // inner sheen
                shape.fill(RadialGradient(colors: [Color.white.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 220))
                    .blendMode(.plusLighter)
            }
        }
    }
}

/// Apple's own Liquid Glass. Only built when the Mac's tools are new enough (Xcode 26).
struct LiquidGlass<S: Shape>: View {
    let shape: S

    static var available: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(Color.black.opacity(0.30)), in: shape)
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }
}

struct IslandView: View {
    @ObservedObject var hub: Hub
    @ObservedObject var island: Island
    @ObservedObject var np: NowPlaying
    @ObservedObject var timer: TimerModel

    init(hub: Hub, island: Island) {
        self.hub = hub
        self.island = island
        self.np = hub.nowPlaying
        self.timer = hub.timer
    }

    var body: some View {
        let size = island.shapeSize
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                surface
                content
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipped()
            }
            .frame(width: size.width, height: size.height)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: size)
            .padding(.top, island.floating ? Island.floatTop : 0)
            Spacer(minLength: 0)
        }
        .frame(width: IslandController.panelSize.width, height: IslandController.panelSize.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder var surface: some View {
        if island.floating {
            IslandSurface(shape: RoundedRectangle(cornerRadius: island.expanded ? 30 : 17, style: .continuous),
                          style: hub.glass, black: false, expanded: island.expanded)
        } else {
            IslandSurface(shape: NotchShape(topRadius: island.expanded ? 14 : 6, bottomRadius: island.expanded ? 30 : 11),
                          style: hub.glass, black: !island.expanded, expanded: island.expanded)
        }
    }

    @ViewBuilder var content: some View {
        let side: CGFloat = island.floating ? (island.expanded ? 18 : 12) : (island.expanded ? 24 : 12)
        if island.expanded {
            ExpandedView(hub: hub, island: island, np: np, timer: timer)
                .padding(.horizontal, side)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).animation(.easeOut(duration: 0.25).delay(0.08)),
                                        removal: .opacity.animation(.easeIn(duration: 0.1))))
        } else if island.floating {
            PillView(hub: hub, np: np, timer: timer)
                .padding(.horizontal, side)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        } else {
            NotchWings(hub: hub, island: island, np: np, timer: timer)
                .padding(.horizontal, side)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        }
    }
}

// MARK: - closed, MacBook screen (things sit either side of the camera notch)

struct NotchWings: View {
    @ObservedObject var hub: Hub
    @ObservedObject var island: Island
    @ObservedObject var np: NowPlaying
    @ObservedObject var timer: TimerModel

    var body: some View {
        HStack(spacing: 0) {
            FlashLeft(hub: hub, np: np, timer: timer).frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: max(0, island.notchSize.width - 8))
            FlashRight(hub: hub, np: np, timer: timer, showTitle: false).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: island.notchSize.height)
    }
}

// MARK: - closed, other screens (a floating pill)

struct PillView: View {
    @ObservedObject var hub: Hub
    @ObservedObject var np: NowPlaying
    @ObservedObject var timer: TimerModel

    var body: some View {
        HStack(spacing: 8) {
            FlashLeft(hub: hub, np: np, timer: timer)
            FlashRight(hub: hub, np: np, timer: timer, showTitle: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 34)
    }
}

struct FlashLeft: View {
    @ObservedObject var hub: Hub
    @ObservedObject var np: NowPlaying
    @ObservedObject var timer: TimerModel

    var body: some View {
        if let f = hub.flash {
            switch f {
            case .welcome: Text("👋").font(.system(size: 15))
            case .timerStarted, .timerDone: Image(systemName: "timer").foregroundColor(.orange).font(.system(size: 13, weight: .semibold))
            case .charging(_, let plugged):
                Image(systemName: plugged ? "bolt.fill" : "powerplug").foregroundColor(plugged ? .green : .white.opacity(0.8))
                    .font(.system(size: 12, weight: .semibold))
            }
        } else if np.track != nil && np.isPlaying {
            Artwork(image: np.artwork, size: 22, radius: 6)
        } else if timer.isRunning || timer.isPaused {
            Image(systemName: timer.isPaused ? "pause.fill" : "timer").foregroundColor(.orange).font(.system(size: 13, weight: .semibold))
        } else {
            Clock(show: hub.showClock)
        }
    }
}

struct FlashRight: View {
    @ObservedObject var hub: Hub
    @ObservedObject var np: NowPlaying
    @ObservedObject var timer: TimerModel
    /// The floating pill has room for the song name.
    let showTitle: Bool

    var body: some View {
        if let f = hub.flash {
            switch f {
            case .welcome: Text("hover me").font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white.opacity(0.9))
            case .timerStarted: Text(TimerModel.format(timer.remaining)).font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundColor(.orange)
            case .timerDone: Text("time's up ✨").font(.system(size: 12.5, weight: .semibold)).foregroundColor(.orange)
            case .charging(let pct, let plugged):
                Text("\(pct)%").font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundColor(plugged ? .green : .white)
            }
        } else {
            HStack(spacing: 8) {
                let busy = timer.isRunning || timer.isPaused
                let playing = np.track != nil && np.isPlaying
                if playing && showTitle && !busy {
                    Text(np.track?.title ?? "").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.92))
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                if busy {
                    Text(TimerModel.format(timer.remaining))
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundColor(timer.isPaused ? .white.opacity(0.6) : .orange)
                    if playing && showTitle { Spacer(minLength: 0) }
                }
                if playing {
                    Equalizer(color: .green, playing: true).frame(width: 16, height: 12)
                } else if showTitle && !busy {
                    BatteryBadge(battery: hub.battery, show: hub.showClock)
                }
            }
        }
    }
}

struct Clock: View {
    let show: Bool

    var body: some View {
        if show {
            TimelineView(.everyMinute) { ctx in
                Text(Clock.fmt.string(from: ctx.date))
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white.opacity(0.92))
            }
        } else {
            Circle().fill(Color.white.opacity(0.35)).frame(width: 6, height: 6)
        }
    }

    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()
}

struct BatteryBadge: View {
    @ObservedObject var battery: Battery
    let show: Bool

    var body: some View {
        if show && battery.hasBattery {
            HStack(spacing: 3) {
                if battery.plugged {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold)).foregroundColor(.green)
                }
                Text("\(battery.percent)%").font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - open

struct ExpandedView: View {
    @ObservedObject var hub: Hub
    @ObservedObject var island: Island
    @ObservedObject var np: NowPlaying
    @ObservedObject var timer: TimerModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TabButton(icon: "music.note", on: hub.tab == .music) { hub.tab = .music }
                TabButton(icon: "timer", on: hub.tab == .timer) { hub.tab = .timer }
                Spacer()
                if hub.flash == .timerDone {
                    Text("time's up ✨").font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                } else if timer.isRunning || timer.isPaused, hub.tab == .music {
                    Text(TimerModel.format(timer.remaining)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundColor(.orange)
                } else if np.isPlaying, hub.tab == .timer {
                    Equalizer(color: .green, playing: true).frame(width: 14, height: 10)
                } else if island.floating {
                    Clock(show: hub.showClock)
                }
            }
            .frame(height: island.floating ? 38 : island.notchSize.height)

            Group {
                if hub.tab == .music { MusicPanel(np: np) } else { TimerPanel(timer: timer, done: hub.flash == .timerDone) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 14)
        }
    }
}
