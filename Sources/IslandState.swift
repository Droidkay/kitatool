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

/// Everything the island shows. The controller and the SwiftUI view both read this.
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var hasNotch = true
    @Published var flash: Flash?
    @Published var tab: Tab = .music
    @Published var hidden = false
    var hoverPending = false
    /// Keeps the island open (e.g. while the "time's up" message shows).
    var pinned = false
    var showCharging = UserDefaults.standard.object(forKey: "showCharging") as? Bool ?? true

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

    /// Size of the black shape right now (used for animation and the mouse hot area).
    var shapeSize: CGSize {
        let n = notchSize
        if expanded { return CGSize(width: 460, height: n.height + 132) }
        if let f = flash {
            switch f {
            case .welcome, .timerDone: return CGSize(width: n.width + 220, height: n.height)
            case .timerStarted, .charging: return CGSize(width: n.width + 150, height: n.height)
            }
        }
        let wing = wingWidth
        return CGSize(width: n.width + wing * 2, height: n.height)
    }

    /// Width of each side "wing" next to the notch when closed.
    var wingWidth: CGFloat {
        if timer.isRunning || timer.isPaused { return 62 }
        if nowPlaying.track != nil && nowPlaying.isPlaying { return 38 }
        return hasNotch ? 0 : 10
    }

    func setExpanded(_ on: Bool) {
        if on {
            // open on the tab that matters right now
            if timer.isRunning && !nowPlaying.isPlaying { tab = .timer }
            else if nowPlaying.track != nil { tab = .music }
        }
        withAnimation(.spring(response: 0.42, dampingFraction: on ? 0.78 : 0.9)) {
            expanded = on
        }
        if on { nowPlaying.refreshSoon() }
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
        setExpanded(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.pinned = false
            self?.setExpanded(false)
        }
    }
}
