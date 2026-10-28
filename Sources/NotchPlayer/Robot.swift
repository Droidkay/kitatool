import SwiftUI
import AppKit

// MARK: - Companion robot ("Kit") that lives beside the notch

enum RobotMood: Equatable {
    case idle, curious, happy, dancing, focused, celebrate, charging, tired, sleeping, surprised, love
}

/// Fast-changing robot state (where it's looking, quick reactions), kept apart from
/// NotchState so cursor movement only redraws the robot.
@MainActor
final class RobotBrain: ObservableObject {
    @Published var lookX: CGFloat = 0
    @Published var lookY: CGFloat = 0
    @Published var near = false
    @Published var reaction: RobotMood?
    var lastActivity = Date()
    private var reactionTask: Task<Void, Never>?

    var idleSeconds: TimeInterval { Date().timeIntervalSince(lastActivity) }

    func cursorMoved(_ p: NSPoint) {
        let wasAsleep = idleSeconds > 120
        lastActivity = Date()
        if wasAsleep { react(.surprised, seconds: 1.4) }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main else { return }
        let f = screen.frame
        let x = max(-1, min(1, (p.x - f.midX) / (f.width / 2)))
        let y = max(0, min(1, (f.maxY - p.y) / max(1, f.height) * 2.2))
        if abs(x - lookX) > 0.04 { lookX = x }
        if abs(y - lookY) > 0.04 { lookY = y }
        let isNear = abs(p.x - f.midX) < 260 && (f.maxY - p.y) < 110
        if isNear != near { near = isNear }
    }

    func react(_ mood: RobotMood, seconds: Double) {
        reaction = mood
        reactionTask?.cancel()
        reactionTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            self.reaction = nil
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
        let emoji = hour >= 5 && hour < 17 ? " ☀️" : " 🌙"
        return (name.isEmpty ? part : "\(part), \(name)") + emoji
    }
}

// MARK: - Views

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
        let interval: Double = m == .sleeping ? 0.1 : 1.0 / 30
        return TimelineView(.animation(minimumInterval: interval, paused: false)) { ctx in
            RobotDrawing(mood: m,
                         t: ctx.date.timeIntervalSinceReferenceDate,
                         lookX: brain.lookX,
                         lookY: brain.lookY,
                         accent: accent)
        }
        .frame(width: 40, height: 28)
    }
}

struct RobotDrawing: View {
    let mood: RobotMood
    let t: Double
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

    private var bob: CGFloat {
        switch mood {
        case .dancing: return -CGFloat(abs(sin(t * Double.pi * 2))) * 2.5
        case .celebrate: return -CGFloat(abs(sin(t * 7))) * 4
        case .sleeping: return CGFloat(sin(t * 1.2)) * 0.6 + 1
        case .tired: return 1.2
        case .surprised: return -1.5
        default: return CGFloat(sin(t * 2)) * 0.5
        }
    }

    private var tilt: Double {
        switch mood {
        case .dancing: return sin(t * Double.pi * 2) * 9
        case .celebrate: return sin(t * 14) * 6
        case .sleeping: return -10
        case .tired: return 7
        case .curious: return Double(lookX) * 10 + 4
        case .idle, .focused: return Double(lookX) * 6
        default: return 0
        }
    }

    private var eyeOpen: CGFloat {
        let p = t.truncatingRemainder(dividingBy: 4.3)
        if p < 0.12 { return 0.15 }
        let q = t.truncatingRemainder(dividingBy: 11.7)
        if q > 0.25 && q < 0.35 { return 0.15 }
        return 1
    }

    var body: some View {
        ZStack {
            extras
            robot
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .offset(y: bob)
        }
    }

    private var robot: some View {
        VStack(spacing: 0) {
            antenna
            head
        }
    }

    private var antenna: some View {
        let glow: Color = mood == .charging ? .green : eyeColor
        let speed: Double = mood == .dancing ? Double.pi * 2 : 2.2
        let pulse: Double = 0.55 + 0.45 * abs(sin(t * speed))
        return VStack(spacing: 0) {
            Circle()
                .fill(glow)
                .frame(width: 4.5, height: 4.5)
                .shadow(color: glow.opacity(0.9), radius: 3)
                .opacity(pulse)
            Rectangle()
                .fill(Color(white: 0.75))
                .frame(width: 1.5, height: 3)
        }
    }

    private var head: some View {
        ZStack {
            HStack(spacing: 22) {
                Capsule().fill(Color(white: 0.6)).frame(width: 3, height: 8)
                Capsule().fill(Color(white: 0.6)).frame(width: 3, height: 8)
            }
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.7)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 24, height: 18)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(white: 0.06))
                .frame(width: 19, height: 12)
            eyes
                .frame(width: 19, height: 12)
                .clipped()
            if mood == .happy || mood == .love || mood == .celebrate {
                HStack(spacing: 17) {
                    Circle().fill(RobotDrawing.pink.opacity(0.6)).frame(width: 3, height: 3)
                    Circle().fill(RobotDrawing.pink.opacity(0.6)).frame(width: 3, height: 3)
                }
                .offset(y: 4.5)
            }
        }
        .frame(width: 30, height: 18)
    }

    private var eyes: some View {
        let tracking = mood == .idle || mood == .curious || mood == .focused || mood == .surprised
        let dx: CGFloat = tracking ? lookX * 2.2 : 0
        let dy: CGFloat = (mood == .idle || mood == .curious) ? lookY * 1.4 - 0.4 : 0
        return HStack(spacing: 5) {
            RobotEye(mood: mood, open: eyeOpen, color: eyeColor, left: true)
            RobotEye(mood: mood, open: eyeOpen, color: eyeColor, left: false)
        }
        .offset(x: dx, y: dy)
    }

    @ViewBuilder
    private var extras: some View {
        switch mood {
        case .dancing:
            FloatingGlyph(text: "♪", t: t, period: 1.6, x: 16, color: eyeColor)
            FloatingGlyph(text: "♫", t: t + 0.8, period: 1.6, x: -16, color: eyeColor)
        case .sleeping:
            FloatingGlyph(text: "z", t: t, period: 2.4, x: 15, color: .white)
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

struct RobotEye: View {
    let mood: RobotMood
    let open: CGFloat
    let color: Color
    let left: Bool

    var body: some View {
        Group {
            switch mood {
            case .happy, .dancing, .celebrate, .charging:
                HappyEye()
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 5, height: 3)
            case .love:
                Image(systemName: "heart.fill")
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundStyle(color)
            case .sleeping:
                Capsule().fill(color.opacity(0.7)).frame(width: 5, height: 1.3)
            case .focused:
                Capsule().fill(color).frame(width: 5, height: 2.2)
            case .tired:
                Capsule().fill(color)
                    .frame(width: 5, height: 2.6)
                    .rotationEffect(.degrees(left ? 14 : -14))
            case .surprised:
                Circle().stroke(color, lineWidth: 1.4).frame(width: 5.5, height: 5.5)
            case .idle, .curious:
                Capsule().fill(color)
                    .frame(width: 4, height: max(1.2, (mood == .curious ? 7 : 6) * open))
            }
        }
        .frame(width: 6, height: 7)
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
            .offset(x: x + sin(p * 6) * 1.5, y: 4 - p * 12)
            .opacity(Double(fade))
    }
}
