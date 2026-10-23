import Foundation

/// A simple countdown timer: start, pause, add a minute, reset.
final class TimerModel: ObservableObject {
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var endsAt: Date?
    @Published private(set) var pausedLeft: TimeInterval?
    var onFinish: (() -> Void)?
    private var tick: Timer?

    var isRunning: Bool { endsAt != nil }
    var isPaused: Bool { pausedLeft != nil }

    var remaining: TimeInterval {
        if let e = endsAt { return max(0, e.timeIntervalSinceNow) }
        if let p = pausedLeft { return p }
        return 0
    }

    var progress: Double {
        total > 0 ? 1 - remaining / total : 0
    }

    func start(minutes: Int) {
        total = TimeInterval(minutes * 60)
        endsAt = Date().addingTimeInterval(total)
        pausedLeft = nil
        schedule()
    }

    func pauseResume() {
        if let e = endsAt {
            pausedLeft = max(0, e.timeIntervalSinceNow)
            endsAt = nil
            tick?.invalidate()
        } else if let p = pausedLeft {
            endsAt = Date().addingTimeInterval(p)
            pausedLeft = nil
            schedule()
        }
    }

    func addMinute() {
        if let e = endsAt {
            endsAt = e.addingTimeInterval(60)
            total += 60
        } else if let p = pausedLeft {
            pausedLeft = p + 60
            total += 60
        } else {
            start(minutes: 1)
        }
    }

    func reset() {
        tick?.invalidate()
        endsAt = nil
        pausedLeft = nil
        total = 0
    }

    private func schedule() {
        tick?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, let e = self.endsAt else { return }
            self.objectWillChange.send()
            if e.timeIntervalSinceNow <= 0 {
                self.reset()
                self.onFinish?()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    static func format(_ s: TimeInterval) -> String {
        let n = Int(s.rounded(.up))
        let h = n / 3600, m = (n % 3600) / 60, sec = n % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
