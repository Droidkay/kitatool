import AppKit
import SwiftUI

enum Flash: Equatable {
    case welcome
    case timerStarted
    case timerDone
    case charging(percent: Int, plugged: Bool)
}

enum Tab: String {
    case music, timer
}

/// How the island is drawn.
enum GlassStyle: String, CaseIterable {
    case liquid, frosted, black

    var title: String {
        switch self {
        case .liquid: return "Liquid Glass"
        case .frosted: return "Frosted glass"
        case .black: return "Black (classic)"
        }
    }

    static var defaultStyle: GlassStyle {
        if #available(macOS 26.0, *) { return .liquid }
        return .frosted
    }
}

/// Which screens get an island.
enum ScreenChoice: String, CaseIterable {
    case all, builtIn, main

    var title: String {
        switch self {
        case .all: return "All screens"
        case .builtIn: return "MacBook screen only"
        case .main: return "Main screen only"
        }
    }
}

/// Shared by every island: music, timer, battery, messages, settings.
final class Hub: ObservableObject {
    @Published var flash: Flash?
    @Published var tab: Tab = .music
    @Published var hidden = false
    @Published var glass: GlassStyle = GlassStyle(rawValue: UserDefaults.standard.string(forKey: "glass") ?? "") ?? GlassStyle.defaultStyle
    @Published var showClock = UserDefaults.standard.object(forKey: "showClock") as? Bool ?? true
    var screens: ScreenChoice = ScreenChoice(rawValue: UserDefaults.standard.string(forKey: "screens") ?? "") ?? .all
    var showCharging = UserDefaults.standard.object(forKey: "showCharging") as? Bool ?? true
    /// Keeps islands open (e.g. while "time's up" shows).
    var pinned = false
    /// Asks every island to open or close (used when the timer ends).
    var onExpandAll: ((Bool) -> Void)?

    let nowPlaying = NowPlaying()
    let timer = TimerModel()
    let battery = Battery()
    private var flashWork: DispatchWorkItem?

    init() {
        timer.onFinish = { [weak self] in self?.timerFinished() }
        battery.onChange = { [weak self] pct, plugged in
            guard let self = self, self.showCharging else { return }
            self.show(.charging(percent: pct, plugged: plugged), seconds: 3)
        }
    }

    func setGlass(_ g: GlassStyle) {
        glass = g
        UserDefaults.standard.set(g.rawValue, forKey: "glass")
    }

    func show(_ f: Flash, seconds: Double) {
        flashWork?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { flash = f }
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { self?.flash = nil }
        }
        flashWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func timerFinished() {
        NSSound(named: NSSound.Name("Glass"))?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSSound(named: NSSound.Name("Glass"))?.play() }
        pinned = true
        tab = .timer
        show(.timerDone, seconds: 6)
        onExpandAll?(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.pinned = false
            self?.onExpandAll?(false)
        }
    }
}

/// One island on one screen.
final class Island: ObservableObject {
    @Published var expanded = false
    @Published var notchSize = CGSize(width: 190, height: 32)
    /// Has a real camera notch (MacBook screen). Otherwise it's a floating glass pill.
    @Published var hasNotch = true
    var hoverPending = false
    let hub: Hub

    /// Gap between the top of the screen and a floating pill.
    static let floatTop: CGFloat = 6

    init(hub: Hub) {
        self.hub = hub
    }

    var floating: Bool { !hasNotch }

    /// Size of the island shape right now (used for the animation and the mouse area).
    var shapeSize: CGSize {
        let n = notchSize
        let np = hub.nowPlaying, t = hub.timer
        let busy = t.isRunning || t.isPaused
        let playing = np.track != nil && np.isPlaying
        if floating {
            let h: CGFloat = 34
            if expanded { return CGSize(width: 440, height: 172) }
            if let f = hub.flash {
                switch f {
                case .welcome, .timerDone: return CGSize(width: 250, height: h)
                case .timerStarted, .charging: return CGSize(width: 190, height: h)
                }
            }
            if busy && playing { return CGSize(width: 250, height: h) }
            if busy { return CGSize(width: 170, height: h) }
            if playing { return CGSize(width: 250, height: h) }
            return CGSize(width: hub.showClock ? 128 : 96, height: h)
        }
        if expanded { return CGSize(width: 460, height: n.height + 132) }
        if let f = hub.flash {
            switch f {
            case .welcome, .timerDone: return CGSize(width: n.width + 220, height: n.height)
            case .timerStarted, .charging: return CGSize(width: n.width + 150, height: n.height)
            }
        }
        let wing: CGFloat = busy ? 62 : (playing ? 38 : 0)
        return CGSize(width: n.width + wing * 2, height: n.height)
    }

    func setExpanded(_ on: Bool) {
        if on {
            if hub.timer.isRunning && !hub.nowPlaying.isPlaying { hub.tab = .timer }
            else if hub.nowPlaying.track != nil { hub.tab = .music }
        }
        withAnimation(.spring(response: 0.45, dampingFraction: on ? 0.74 : 0.88)) {
            expanded = on
        }
        if on { hub.nowPlaying.refreshSoon() }
    }
}
