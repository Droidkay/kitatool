import SwiftUI
import AppKit

// MARK: - Companion robot that lives in the notch

enum RobotMood: Equatable {
    case idle, curious, happy, dancing, focused, celebrate, charging, tired, sleeping, surprised, love
}

/// Physical things the robot does.
enum RobotAct: Equatable {
    case idle, look, walk, run, moonwalk, hop, jump, spin, wave, stretch, yawn, peek, dance, fall, celebrate, sleep, flip, bounce
}

/// The robot's body and behaviour: where it is, which way it faces, what it's doing.
@MainActor
final class RobotBrain: ObservableObject {
    @Published var lookX: CGFloat = 0
    @Published var lookY: CGFloat = 0
    @Published var near = false
    @Published var reaction: RobotMood?

    /// -1 = left of the notch, +1 = right of the notch. Around 0 it is hidden behind the notch.
    @Published private(set) var pos: CGFloat = -1
    @Published private(set) var facing: CGFloat = 1
    @Published private(set) var act: RobotAct = .idle
    @Published private(set) var actStart = Date()

    var base: RobotMood = .idle
    var lastActivity = Date()
    var enabled = true

    private var actEnd = Date()
    private var queue: [(RobotAct, Double, CGFloat?)] = []
    private var reactionTask: Task<Void, Never>?
    private var timer: Timer?
    private var lastGreet = Date.distantPast
    private var lastAct: RobotAct = .idle

    var idleSeconds: TimeInterval { Date().timeIntervalSince(lastActivity) }
    var side: CGFloat { pos >= 0 ? 1 : -1 }
    var busy: Bool { Date() < actEnd }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            let me = self
            Task { @MainActor in me?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: input

    func cursorMoved(_ p: NSPoint) {
        let wasAsleep = idleSeconds > 120
        lastActivity = Date()
        if wasAsleep {
            reactNow(.surprised, seconds: 1.4)
            force([(.jump, 0.7, nil), (.stretch, 1.6, nil), (.wave, 1.4, nil)])
        }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main else { return }
        let f = screen.frame
        let x = max(-1, min(1, (p.x - f.midX) / (f.width / 2)))
        let y = max(0, min(1, (f.maxY - p.y) / max(1, f.height) * 2.2))
        if abs(x - lookX) > 0.04 { lookX = x }
        if abs(y - lookY) > 0.04 { lookY = y }
        let isNear = abs(p.x - f.midX) < 300 && (f.maxY - p.y) < 140
        if isNear != near {
            near = isNear
            if isNear && Date().timeIntervalSince(lastGreet) > 25 && canMove {
                lastGreet = Date()
                let cursorSide: CGFloat = p.x < f.midX ? -1 : 1
                if cursorSide != side {
                    force([(.run, 1.3, cursorSide), (.wave, 1.6, nil)])
                } else {
                    force([(.wave, 1.8, nil)])
                }
            }
        }
    }

    /// A quick feeling, with a matching move.
    func react(_ mood: RobotMood, seconds: Double) {
        reactNow(mood, seconds: seconds)
        switch mood {
        case .surprised: force([(.jump, 0.7, nil)])
        case .love: force([(.hop, 1.4, nil)])
        case .celebrate: force([(.celebrate, 1.8, nil), (.spin, 0.9, nil)])
        case .happy: force([(.bounce, 1.0, nil)])
        case .tired: force([(.yawn, 2.0, nil)])
        default: break
        }
    }

    private func reactNow(_ mood: RobotMood, seconds: Double) {
        reaction = mood
        reactionTask?.cancel()
        reactionTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            self.reaction = nil
        }
    }

    /// Shows off every move (used to record the demo).
    func showOff() {
        force([(.walk, 3.4, 1), (.wave, 1.8, nil), (.peek, 3.2, nil), (.jump, 0.7, nil), (.spin, 0.9, nil),
               (.run, 1.3, -1), (.hop, 1.6, nil), (.stretch, 1.8, nil), (.fall, 2.6, nil),
               (.moonwalk, 3.6, 1), (.dance, 3.0, nil), (.yawn, 2.2, nil), (.celebrate, 1.8, nil)])
    }

    private var canMove: Bool { base != .sleeping && base != .celebrate }

    // MARK: behaviour

    private func force(_ acts: [(RobotAct, Double, CGFloat?)]) {
        queue = acts
        actEnd = .distantPast
        step()
    }

    private func step() {
        guard enabled else { return }
        if busy { return }
        if !queue.isEmpty {
            let (a, d, target) = queue.removeFirst()
            perform(a, d, to: target)
            return
        }
        chooseNext()
    }

    private func perform(_ a: RobotAct, _ duration: Double, to target: CGFloat? = nil) {
        lastAct = a
        act = a
        actStart = Date()
        actEnd = Date().addingTimeInterval(duration)
        if let target, target != pos {
            let dir: CGFloat = target > pos ? 1 : -1
            facing = a == .moonwalk ? -dir : dir
            let curve: Animation = a == .walk || a == .moonwalk ? .linear(duration: duration) : .easeInOut(duration: duration)
            withAnimation(curve) { pos = target }
        } else if a == .flip || (a == .look && Bool.random()) {
            facing = -facing
        }
    }

    private func pick(_ options: [(RobotAct, Int)]) -> RobotAct {
        let total = options.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0..<max(1, total))
        for (a, w) in options {
            if r < w { return a }
            r -= w
        }
        return options.first?.0 ?? .idle
    }

    private func chooseNext() {
        let other = -side
        // Rest between big moves so it feels calm, not frantic.
        let restFirst = lastAct != .idle && lastAct != .look && lastAct != .sleep && lastAct != .dance && Bool.random()

        switch base {
        case .sleeping:
            perform(Int.random(in: 0..<8) == 0 ? .flip : .sleep, Double.random(in: 4...8))
        case .celebrate:
            perform(Bool.random() ? .celebrate : .spin, Bool.random() ? 1.8 : 0.9)
        case .dancing:
            let a = pick([(.dance, 60), (.moonwalk, 12), (.spin, 10), (.hop, 10), (.bounce, 8)])
            switch a {
            case .moonwalk: perform(.moonwalk, 3.6, to: other)
            case .spin: perform(.spin, 0.9)
            case .hop: perform(.hop, 1.6)
            case .bounce: perform(.bounce, 1.2)
            default: perform(.dance, Double.random(in: 4...7))
            }
        case .focused:
            let a = pick([(.idle, 55), (.look, 20), (.walk, 12), (.stretch, 13)])
            switch a {
            case .walk: perform(.walk, 4.5, to: other)
            case .stretch: perform(.stretch, 1.8)
            case .look: perform(.look, 3)
            default: perform(.idle, Double.random(in: 4...8))
            }
        case .tired:
            let a = pick([(.idle, 45), (.yawn, 30), (.walk, 25)])
            switch a {
            case .yawn: perform(.yawn, 2.2)
            case .walk: perform(.walk, 6, to: other)
            default: perform(.idle, Double.random(in: 4...7))
            }
        case .charging:
            perform(pick([(.idle, 50), (.bounce, 30), (.hop, 20)]), Double.random(in: 1.2...3))
        default:
            if restFirst {
                perform(pick([(.idle, 70), (.look, 30)]), Double.random(in: 2.5...5))
                return
            }
            let hour = Calendar.current.component(.hour, from: Date())
            let late = hour >= 22 || hour < 6
            let a = pick([
                (.idle, 18), (.look, 14), (.walk, 18), (.run, 5), (.peek, 10), (.hop, 6), (.wave, 5),
                (.spin, 4), (.stretch, 5), (.yawn, late ? 8 : 2), (.fall, 2), (.moonwalk, 3), (.dance, 3), (.bounce, 5)
            ])
            switch a {
            case .walk: perform(.walk, Double.random(in: 3.2...4.2), to: other)
            case .run: perform(.run, 1.3, to: other)
            case .moonwalk: perform(.moonwalk, 3.6, to: other)
            case .peek: perform(.peek, 3.2)
            case .hop: perform(.hop, 1.6)
            case .wave: perform(.wave, 1.8)
            case .spin: perform(.spin, 0.9)
            case .stretch: perform(.stretch, 1.8)
            case .yawn: perform(.yawn, 2.2)
            case .fall: perform(.fall, 2.6)
            case .dance: perform(.dance, 3.5)
            case .bounce: perform(.bounce, 1.2)
            case .look: perform(.look, 3.5)
            default: perform(.idle, Double.random(in: 3...6))
            }
        }
    }
}

extension NotchState {
    /// What the robot feels, from what the Mac is doing.
    var robotBaseMood: RobotMood {
        if timerFinished { return .celebrate }
        if case .charging = peek { return .charging }
        if case .robot = peek { return .happy }
        if case .checkIn = peek { return .curious }
        if case .notification = peek { return .surprised }
        if buddy?.breathingUntil != nil { return .focused }
        if let t = track, t.playing { return .dancing }
        if timerRunning { return .focused }
        if let b = battery, !b.charging, b.level <= 20 { return .tired }
        if now.timeIntervalSince(robot.lastActivity) > 120 { return .sleeping }
        return .idle
    }

    static func robotGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let part: String
        if hour < 5 { part = "Up late" }
        else if hour < 12 { part = "Good morning" }
        else if hour < 17 { part = "Good afternoon" }
        else { part = "Good evening" }
        return (name.isEmpty ? part : "\(part), \(name)") + (hour >= 5 && hour < 17 ? " ☀️" : " 🌙")
    }
}

// MARK: - Stage: the robot roams the whole idle notch

/// Spans the idle island. The robot walks between the left and right sides
/// and disappears behind the notch in the middle.
struct RobotStage: View {
    @ObservedObject var brain: RobotBrain
    let base: RobotMood
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    let notchW: CGFloat
    let flankW: CGFloat
    let ear: CGFloat

    var body: some View {
        let leftC = ear + flankW / 2
        let rightC = width - ear - flankW / 2
        let x = leftC + (brain.pos + 1) / 2 * (rightC - leftC)
        let gapStart = ear + flankW
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { ctx in
            let phase = ctx.date.timeIntervalSince(brain.actStart)
            RobotFace(brain: brain, base: base, accent: accent)
                .offset(x: peekOffset(phase))
                .position(x: x, y: height / 2)
        }
        .frame(width: width, height: height)
        .mask(
            HStack(spacing: 0) {
                Rectangle().frame(width: gapStart + 2)
                Color.clear.frame(width: max(0, notchW - 4))
                Rectangle()
            }
        )
    }

    /// Slides part-way behind the notch edge and peeks out.
    private func peekOffset(_ phase: Double) -> CGFloat {
        guard brain.act == .peek else { return 0 }
        let towardNotch: CGFloat = brain.pos < 0 ? 1 : -1
        let d = flankW / 2 + 6
        let p = phase / 3.2
        let amount: Double
        if p < 0.2 { amount = p / 0.2 }
        else if p < 0.75 { amount = 0.75 + 0.25 * sin((p - 0.2) * 22) }   // bobbing in and out
        else { amount = max(0, 1 - (p - 0.75) / 0.25) }
        return towardNotch * d * CGFloat(amount)
    }
}

// MARK: - Face / body

struct RobotFace: View {
    @ObservedObject var brain: RobotBrain
    let base: RobotMood
    let accent: Color

    private var mood: RobotMood {
        if let r = brain.reaction { return r }
        if base == .idle && brain.near { return .curious }
        return base
    }

    var body: some View {
        let m = mood
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { ctx in
            RobotDrawing(mood: m,
                         act: brain.act,
                         phase: ctx.date.timeIntervalSince(brain.actStart),
                         t: ctx.date.timeIntervalSinceReferenceDate,
                         facing: brain.facing,
                         lookX: brain.lookX,
                         lookY: brain.lookY,
                         accent: accent)
        }
        .frame(width: 40, height: 30)
    }
}

/// Pose for one frame.
private struct Pose {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var tilt: Double = 0
    var spinY: Double = 0
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var armL: Double = 20        // degrees; 0 = hanging down, 180 = straight up
    var armR: Double = 20
    var stepL: CGFloat = 0       // foot lift
    var stepR: CGFloat = 0
    var eyeDX: CGFloat? = nil
    var mouthOpen: CGFloat = 0   // 0 = smile line, 1 = wide "O"
    var dizzy = false
    var closed = false
}

struct RobotDrawing: View {
    let mood: RobotMood
    let act: RobotAct
    let phase: Double
    let t: Double
    let facing: CGFloat
    let lookX: CGFloat
    let lookY: CGFloat
    let accent: Color

    private static let cyan = Color(red: 0.35, green: 0.95, blue: 1)
    private static let pink = Color(red: 1, green: 0.42, blue: 0.62)

    private var eyeColor: Color {
        switch mood {
        case .dancing: return accent == .white ? RobotDrawing.cyan : accent
        case .love: return RobotDrawing.pink
        case .charging: return .green
        case .tired: return Color(red: 1, green: 0.55, blue: 0.3)
        case .focused: return .orange
        default: return RobotDrawing.cyan
        }
    }

    private var pose: Pose {
        var p = Pose()
        let ph = phase
        switch act {
        case .walk, .moonwalk:
            let s = sin(ph * 11)
            p.stepL = max(0, CGFloat(s)) * 2.2
            p.stepR = max(0, CGFloat(-s)) * 2.2
            p.dy = -CGFloat(abs(s)) * 1.2
            p.tilt = Double(facing) * (act == .moonwalk ? -3 : 5)
            p.armL = 20 + s * 30
            p.armR = 20 - s * 30
            p.eyeDX = facing * 2
        case .run:
            let s = sin(ph * 20)
            p.stepL = max(0, CGFloat(s)) * 3
            p.stepR = max(0, CGFloat(-s)) * 3
            p.dy = -CGFloat(abs(s)) * 2
            p.tilt = Double(facing) * 11
            p.armL = 60 + s * 50
            p.armR = 60 - s * 50
            p.eyeDX = facing * 2.4
            p.mouthOpen = 0.4
        case .hop:
            let s = abs(sin(ph * 7.5))
            p.dy = -CGFloat(s) * 5
            p.sy = s < 0.15 ? 0.9 : 1.04
            p.sx = s < 0.15 ? 1.08 : 0.98
            p.armL = 90 + s * 60
            p.armR = 90 + s * 60
        case .bounce:
            let s = sin(ph * 12)
            p.sy = 1 + CGFloat(s) * 0.07
            p.sx = 1 - CGFloat(s) * 0.06
            p.tilt = s * 6
            p.armL = 40 + s * 40
            p.armR = 40 - s * 40
        case .jump:
            let q = min(1, ph / 0.7)
            p.dy = -CGFloat(4 * 7 * q * (1 - q))
            if q < 0.12 || q > 0.9 { p.sy = 0.86; p.sx = 1.1 } else { p.sy = 1.06; p.sx = 0.96 }
            p.armL = 160
            p.armR = 160
            p.mouthOpen = 1
        case .spin:
            p.spinY = min(1, ph / 0.9) * 360
            p.dy = -CGFloat(sin(min(1, ph / 0.9) * .pi)) * 3
            p.armL = 100
            p.armR = 100
        case .wave:
            p.armR = 150 + sin(ph * 13) * 28
            p.armL = 15
            p.tilt = sin(ph * 6.5) * 5
            p.mouthOpen = 0.2
        case .stretch:
            let q = sin(min(1, ph / 1.8) * .pi)
            p.armL = 20 + q * 155
            p.armR = 20 + q * 155
            p.sy = 1 + CGFloat(q) * 0.12
            p.sx = 1 - CGFloat(q) * 0.05
            p.closed = q > 0.6
            p.mouthOpen = CGFloat(q) * 0.6
        case .yawn:
            let q = sin(min(1, ph / 2.2) * .pi)
            p.mouthOpen = CGFloat(q)
            p.closed = q > 0.4
            p.tilt = -q * 8
            p.armL = 20 + q * 60
            p.armR = 20
        case .look:
            p.eyeDX = ph.truncatingRemainder(dividingBy: 3.5) < 1.6 ? -2.4 : 2.4
            p.tilt = Double(p.eyeDX ?? 0) * 2
        case .peek:
            p.tilt = Double(-(facing)) * 0 + (phase < 0.6 ? 0 : sin(ph * 5) * 10)
            p.eyeDX = 0
        case .dance:
            let s = sin(ph * .pi * 2)
            p.tilt = s * 10
            p.dy = -CGFloat(abs(s)) * 2.5
            p.armL = 120 + s * 40
            p.armR = 120 - s * 40
            p.stepL = max(0, CGFloat(s)) * 2
            p.stepR = max(0, CGFloat(-s)) * 2
        case .celebrate:
            let s = abs(sin(ph * 7))
            p.dy = -CGFloat(s) * 6
            p.armL = 165
            p.armR = 165 + sin(ph * 14) * 15
            p.mouthOpen = 0.8
        case .fall:
            let q = ph / 2.6
            let dir = Double(facing)
            if q < 0.18 { p.tilt = dir * 90 * (q / 0.18); p.mouthOpen = 1 }
            else if q < 0.7 { p.tilt = dir * 90; p.dizzy = true; p.dy = 2 }
            else if q < 0.85 { p.tilt = dir * 90 * (1 - (q - 0.7) / 0.15) }
            else { p.dy = -CGFloat(sin((q - 0.85) / 0.15 * .pi)) * 4; p.armL = 140; p.armR = 140 }
        case .sleep:
            p.tilt = -10
            p.closed = true
        case .flip:
            p.tilt = sin(min(1, ph / 1.0) * .pi) * 15
            p.closed = true
        case .idle:
            p.dy = CGFloat(sin(t * 2)) * 0.5
            p.tilt = Double(lookX) * 6
            p.armL = 18 + sin(t * 1.7) * 4
            p.armR = 18 - sin(t * 1.7) * 4
        }
        if mood == .sleeping && act != .fall { p.closed = true; p.tilt = -10 }
        return p
    }

    private var blink: CGFloat {
        let a = t.truncatingRemainder(dividingBy: 4.3)
        if a < 0.12 { return 0.15 }
        let b = t.truncatingRemainder(dividingBy: 11.7)
        if b > 0.25 && b < 0.35 { return 0.15 }
        return 1
    }

    var body: some View {
        let p = pose
        ZStack {
            extras
            VStack(spacing: 0) {
                antenna
                ZStack {
                    arm(angle: p.armL, left: true)
                    arm(angle: p.armR, left: false)
                    head(p)
                }
                .frame(width: 32, height: 17)
                feet(p)
            }
            .scaleEffect(x: p.sx, y: p.sy, anchor: .bottom)
            .rotation3DEffect(.degrees(p.spinY), axis: (x: 0, y: 1, z: 0))
            .rotationEffect(.degrees(p.tilt), anchor: .bottom)
            .offset(x: p.dx, y: p.dy)
        }
    }

    private var antenna: some View {
        let glow: Color = mood == .charging ? .green : eyeColor
        let speed: Double = act == .dance || act == .run ? .pi * 3 : 2.2
        let pulse: Double = 0.55 + 0.45 * abs(sin(t * speed))
        let sway = act == .run || act == .walk ? sin(phase * 11) * 14 : (act == .jump ? -12 : 0)
        return VStack(spacing: 0) {
            Circle()
                .fill(glow)
                .frame(width: 4, height: 4)
                .shadow(color: glow.opacity(0.9), radius: 3)
                .opacity(pulse)
            Rectangle().fill(Color(white: 0.75)).frame(width: 1.3, height: 2.5)
        }
        .rotationEffect(.degrees(sway), anchor: .bottom)
    }

    private func arm(angle: Double, left: Bool) -> some View {
        Capsule()
            .fill(Color(white: 0.78))
            .frame(width: 2.6, height: 7)
            .offset(y: 3.5)
            .rotationEffect(.degrees(left ? angle : -angle), anchor: .top)
            .offset(x: left ? -12.5 : 12.5, y: -1)
    }

    private func head(_ p: Pose) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: 23, height: 17)
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(Color(white: 0.06))
                .frame(width: 18.5, height: 11.5)
            eyes(p)
                .frame(width: 18, height: 11)
                .clipped()
            if mood == .happy || mood == .love || mood == .celebrate || act == .celebrate {
                HStack(spacing: 16) {
                    Circle().fill(RobotDrawing.pink.opacity(0.65)).frame(width: 2.8, height: 2.8)
                    Circle().fill(RobotDrawing.pink.opacity(0.65)).frame(width: 2.8, height: 2.8)
                }
                .offset(y: 4)
            }
        }
    }

    private func eyes(_ p: Pose) -> some View {
        let tracking = act == .idle && (mood == .idle || mood == .curious || mood == .focused)
        let dx: CGFloat = p.eyeDX ?? (tracking ? lookX * 2.2 : 0)
        let dy: CGFloat = tracking ? lookY * 1.3 - 0.6 : -0.8
        let m: RobotMood = p.closed ? .sleeping : (p.dizzy ? .surprised : mood)
        return VStack(spacing: 1) {
            HStack(spacing: 4.5) {
                RobotEye(mood: m, open: blink, color: eyeColor, left: true, dizzy: p.dizzy, t: t)
                RobotEye(mood: m, open: blink, color: eyeColor, left: false, dizzy: p.dizzy, t: t)
            }
            mouth(p)
        }
        .offset(x: dx, y: dy)
    }

    @ViewBuilder
    private func mouth(_ p: Pose) -> some View {
        if p.mouthOpen > 0.15 {
            Ellipse()
                .fill(eyeColor.opacity(0.9))
                .frame(width: 2.5 + 2.5 * p.mouthOpen, height: 1.2 + 2.6 * p.mouthOpen)
        } else if mood == .tired || mood == .sleeping {
            Capsule().fill(eyeColor.opacity(0.6)).frame(width: 3, height: 0.9)
        } else {
            HappyEye()
                .stroke(eyeColor.opacity(0.85), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: 4, height: 1.4)
                .rotationEffect(.degrees(180))
        }
    }

    private func feet(_ p: Pose) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(Color(white: 0.62)).frame(width: 5, height: 2.4).offset(y: -p.stepL)
            Capsule().fill(Color(white: 0.62)).frame(width: 5, height: 2.4).offset(y: -p.stepR)
        }
        .frame(height: 3)
    }

    @ViewBuilder
    private var extras: some View {
        if act == .fall && phase > 0.5 && phase < 1.9 {
            FloatingGlyph(text: "✦", t: t, period: 0.8, x: 10, color: .yellow)
            FloatingGlyph(text: "✦", t: t + 0.4, period: 0.8, x: -10, color: .yellow)
        } else if act == .wave {
            FloatingGlyph(text: "hi!", t: phase, period: 1.8, x: 14, color: .white)
        } else {
            switch mood {
            case .dancing:
                FloatingGlyph(text: "♪", t: t, period: 1.6, x: 16, color: eyeColor)
                FloatingGlyph(text: "♫", t: t + 0.8, period: 1.6, x: -16, color: eyeColor)
            case .sleeping:
                FloatingGlyph(text: "z", t: t, period: 2.4, x: 14, color: .white)
                FloatingGlyph(text: "Z", t: t + 1.2, period: 2.4, x: 17, color: .white)
            case .celebrate:
                FloatingGlyph(text: "✦", t: t, period: 1.0, x: 16, color: .yellow)
                FloatingGlyph(text: "✦", t: t + 0.5, period: 1.0, x: -16, color: .orange)
            case .love:
                FloatingGlyph(text: "♥", t: t, period: 1.8, x: 16, color: RobotDrawing.pink)
            case .charging:
                FloatingGlyph(text: "⚡︎", t: t, period: 1.4, x: 16, color: .green)
            default:
                EmptyView()
            }
        }
    }
}

struct RobotEye: View {
    let mood: RobotMood
    let open: CGFloat
    let color: Color
    let left: Bool
    var dizzy = false
    var t: Double = 0

    var body: some View {
        Group {
            if dizzy {
                Image(systemName: "xmark")
                    .font(.system(size: 4.5, weight: .heavy))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(t * 200))
            } else {
                switch mood {
                case .happy, .dancing, .celebrate, .charging:
                    HappyEye()
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 4.5, height: 2.6)
                case .love:
                    Image(systemName: "heart.fill")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(color)
                case .sleeping:
                    Capsule().fill(color.opacity(0.7)).frame(width: 4.5, height: 1.2)
                case .focused:
                    Capsule().fill(color).frame(width: 4.5, height: 2)
                case .tired:
                    Capsule().fill(color)
                        .frame(width: 4.5, height: 2.4)
                        .rotationEffect(.degrees(left ? 14 : -14))
                case .surprised:
                    Circle().stroke(color, lineWidth: 1.3).frame(width: 5, height: 5)
                case .idle, .curious:
                    Capsule().fill(color)
                        .frame(width: 3.6, height: max(1.2, (mood == .curious ? 6 : 5.2) * open))
                }
            }
        }
        .frame(width: 5.5, height: 6)
        .shadow(color: color.opacity(0.8), radius: 2)
    }
}

/// A "^" smiling eye.
struct HappyEye: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                       control: CGPoint(x: r.midX, y: r.minY - r.height))
        return p
    }
}

struct FloatingGlyph: View {
    let text: String
    let t: Double
    let period: Double
    let x: CGFloat
    let color: Color

    var body: some View {
        let p = CGFloat(t.truncatingRemainder(dividingBy: period) / period)
        let fade: CGFloat = p < 0.2 ? p * 5 : (1 - p) * 1.25
        return Text(text)
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .offset(x: x + sin(p * 6) * 1.5, y: 2 - p * 11)
            .opacity(Double(fade))
    }
}
