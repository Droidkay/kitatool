import SwiftUI
import AppKit
import EventKit
import UniformTypeIdentifiers

// MARK: - Shape (flat top that blends into the notch, rounded bottom)

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = topRadius
        let br = bottomRadius
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Helpers

private let clockFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm"
    return f
}()

private let eventTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f
}()

private let weekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE"
    return f
}()

private let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d"
    return f
}()

func mmss(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
}

private func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Root

struct NotchRoot: View {
    @ObservedObject var s: ScreenState

    var body: some View {
        let size = s.islandSize
        let bottom: CGFloat = s.expanded ? 32 : (s.peek != .none ? 24 : 14)
        let spring = Animation.spring(response: 0.46, dampingFraction: 0.74)

        ZStack(alignment: .top) {
            NotchShape(topRadius: s.topRadius, bottomRadius: bottom)
                .fill(Color.black)

            if s.expanded {
                ExpandedContent(s: s)
                    .transition(.opacity)
            } else if s.peek != .none {
                PeekContent(s: s)
                    .transition(.opacity)
            } else {
                IdleContent(s: s)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(NotchShape(topRadius: s.topRadius, bottomRadius: bottom))
        .shadow(color: .black.opacity(s.expanded ? 0.45 : 0), radius: 16, y: 8)
        .animation(spring, value: s.expanded)
        .animation(spring, value: s.peek)
        .animation(spring, value: s.compactVisible)
        .opacity(s.visible ? 1 : 0)
        .animation(spring, value: s.visible)
        .frame(width: s.panelSize.width, height: s.panelSize.height, alignment: .top)
    }
}

// MARK: - Shared small pieces

struct ArtworkThumb: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct EqualizerBars: View {
    let playing: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    let phase = Double(i)
                    let h: Double = playing ? 4 + 12 * abs(sin(t * (2.6 + phase * 1.1) + phase * 1.7)) : 3
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: h)
                }
            }
            .frame(height: 18)
        }
    }
}

struct BatteryBadge: View {
    let info: BatteryInfo
    var showPercent = true

    private var symbol: String {
        switch info.level {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }

    private var tint: Color {
        if info.charging { return .green }
        return info.level <= 20 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 3) {
            if showPercent {
                Text("\(info.level)%")
                    .font(rounded(11, .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(tint)
                if info.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.black.opacity(0.85))
                        .offset(x: -1)
                }
            }
        }
    }
}

// MARK: - Idle (compact live activity)

struct IdleContent: View {
    @ObservedObject var s: ScreenState

    var body: some View {
        ZStack {
            if s.robotEnabled {
                RobotSides(s: s, brain: s.robot, left: AnyView(left), right: AnyView(right))
                RobotStage(brain: s.robot, base: s.robotBaseMood, accent: s.accent,
                           width: s.idleSize.width, height: s.geometry.notchH,
                           notchW: s.geometry.notchW, flankW: s.flankW, ear: s.ear)
            } else {
                HStack(spacing: 0) {
                    left.frame(width: s.flankW, alignment: .center)
                    Spacer(minLength: 0)
                    right.frame(width: s.flankW, alignment: .center)
                }
                .padding(.horizontal, s.ear)
            }
        }
        .frame(width: s.idleSize.width, height: s.geometry.notchH)
        .opacity(s.compactVisible ? 1 : 0)
    }

    @ViewBuilder
    private var left: some View {
        if s.timerActive {
            Image(systemName: s.timerFinished ? "bell.fill" : "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
        } else if let t = s.track {
            ArtworkThumb(image: s.artwork, size: 22, radius: 6)
                .opacity(t.playing ? 1 : 0.55)
        } else if s.showIdleInfo {
            Text(clockFormatter.string(from: s.now))
                .font(rounded(13, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var right: some View {
        if s.timerActive {
            Text(s.timerFinished ? "Done" : mmss(s.timerRemaining))
                .font(rounded(12, .semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .lineLimit(1)
                .fixedSize()
        } else if let t = s.track {
            EqualizerBars(playing: t.playing, color: s.accent)
        } else if s.showIdleInfo && s.robotEnabled {
            Text(clockFormatter.string(from: s.now))
                .font(rounded(12, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        } else if s.showIdleInfo, let b = s.battery {
            BatteryBadge(info: b, showPercent: false)
        }
    }
}

/// The normal left/right content, which steps aside wherever the robot is standing.
struct RobotSides: View {
    @ObservedObject var s: ScreenState
    @ObservedObject var brain: RobotBrain
    let left: AnyView
    let right: AnyView

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: s.flankW, alignment: .center)
                .opacity(brain.pos < -0.3 ? 0 : 1)
                .scaleEffect(brain.pos < -0.3 ? 0.6 : 1)
            Spacer(minLength: 0)
            right.frame(width: s.flankW, alignment: .center)
                .opacity(brain.pos > 0.3 ? 0 : 1)
                .scaleEffect(brain.pos > 0.3 ? 0.6 : 1)
        }
        .padding(.horizontal, s.ear)
        .animation(.easeInOut(duration: 0.6), value: brain.pos)
    }
}

// MARK: - Peek (short-lived banner)

struct PeekContent: View {
    @ObservedObject var s: ScreenState

    private struct Info {
        var symbol: String
        var tint: Color
        var title: String
        var subtitle: String
        var useArtwork = false
        var bar: Double? = nil
        var useRobot = false
    }

    private var info: Info {
        switch s.peek {
        case .track:
            return Info(symbol: "music.note", tint: s.accent,
                        title: s.track?.title ?? "Now Playing",
                        subtitle: s.track?.artist ?? "", useArtwork: true)
        case .charging(let l):
            return Info(symbol: "bolt.fill", tint: .green, title: "Charging", subtitle: "\(l)%")
        case .lowBattery(let l):
            return Info(symbol: "battery.25", tint: .red, title: "Low Battery", subtitle: "\(l)% remaining")
        case .timerDone:
            return Info(symbol: "bell.fill", tint: .orange, title: "Timer Done", subtitle: "Time's up")
        case .event(let title, let mins):
            return Info(symbol: "calendar", tint: .red, title: title,
                        subtitle: mins <= 0 ? "Starting now" : "In \(mins) min")
        case .volume(let level, let muted):
            let sym = muted ? "speaker.slash.fill"
                : level < 0.01 ? "speaker.fill"
                : level < 0.34 ? "speaker.wave.1.fill"
                : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
            return Info(symbol: sym, tint: .white, title: "", subtitle: "", bar: muted ? 0 : level)
        case .robot(let message):
            return Info(symbol: "face.smiling", tint: .cyan, title: message, subtitle: "", useRobot: true)
        case .checkIn(let message):
            return Info(symbol: "face.smiling", tint: .cyan, title: message, subtitle: "", useRobot: true)
        case .notification(let n):
            return Info(symbol: "bell.fill", tint: .white, title: n.title, subtitle: n.body)
        case .copied(let text):
            return Info(symbol: "doc.on.clipboard.fill", tint: .green, title: "Copied", subtitle: text)
        case .none:
            return Info(symbol: "circle", tint: .white, title: "", subtitle: "")
        }
    }

    var body: some View {
        if case .notification(let n) = s.peek {
            NotificationBanner(s: s, note: n)
        } else if case .checkIn(let text) = s.peek {
            CheckInBanner(s: s, text: text)
        } else {
            standard
        }
    }

    private var standard: some View {
        let i = info
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    if i.useRobot {
                        RobotFace(brain: s.robot, base: .happy, accent: s.accent)
                    } else if i.useArtwork {
                        ArtworkThumb(image: s.artwork, size: 22, radius: 6)
                    } else {
                        Image(systemName: i.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(i.tint)
                    }
                }
                .frame(width: s.flankW)
                Spacer(minLength: 0)
                Group {
                    if i.useArtwork, let t = s.track {
                        EqualizerBars(playing: t.playing, color: s.accent)
                    } else if case .charging = s.peek, let b = s.battery {
                        BatteryBadge(info: b, showPercent: false)
                    } else if case .volume(let lv, let muted) = s.peek {
                        Text(muted ? "Muted" : "\(Int((lv * 100).rounded()))%")
                            .font(rounded(12, .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(width: s.flankW)
            }
            .padding(.horizontal, s.ear)
            .frame(height: s.geometry.notchH)

            VStack(spacing: 1) {
                if let b = i.bar {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule().fill(Color.white)
                                .frame(width: max(0, geo.size.width * CGFloat(b)))
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 8)
                    .animation(.easeOut(duration: 0.12), value: b)
                }
                if !i.title.isEmpty {
                    Text(i.title)
                        .font(rounded(13, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if !i.subtitle.isEmpty {
                    Text(i.subtitle)
                        .font(rounded(11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 38, alignment: .top)
        }
    }
}

// MARK: - Expanded

struct ExpandedContent: View {
    @ObservedObject var s: ScreenState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 1) {
                    ForEach(NotchPage.allCases) { p in
                        Button {
                            s.page = p
                        } label: {
                            Image(systemName: p.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(s.page == p ? Color.black : Color.white.opacity(0.7))
                                .frame(width: 21, height: 22)
                                .overlay(alignment: .topTrailing) {
                                    if p == .alerts && !s.notes.isEmpty && s.page != .alerts {
                                        Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: -2, y: 2)
                                    }
                                }
                                .background(
                                    Capsule().fill(s.page == p ? Color.white : Color.white.opacity(0.0)))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: s.geometry.notchW)

                HStack(spacing: 8) {
                    if let b = s.battery { BatteryBadge(info: b) }
                    Text(clockFormatter.string(from: s.now))
                        .font(rounded(12, .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(height: s.geometry.notchH)

            Group {
                switch s.page {
                case .music: MusicPane(s: s)
                case .buddy: BuddyPane(s: s, buddy: s.core.buddy)
                case .alerts: AlertsPane(s: s)
                case .clips: ClipsPane(link: s.core.clipsLink)
                case .calendar: CalendarPane(s: s)
                case .timer: TimerPane(s: s)
                case .shelf: ShelfPane(s: s)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(s.page)
            .transition(.opacity)
        }
        .background(
            RadialGradient(colors: [s.accent.opacity(s.page == .music && s.track != nil ? 0.28 : 0), .clear],
                           center: .bottomLeading, startRadius: 10, endRadius: 320)
        )
    }
}

// MARK: - Music

struct MusicPane: View {
    @ObservedObject var s: ScreenState

    var body: some View {
        if let t = s.track {
            HStack(spacing: 14) {
                ArtworkThumb(image: s.artwork, size: 92, radius: 16)
                    .shadow(color: s.accent.opacity(0.45), radius: 12, y: 4)

                VStack(alignment: .leading, spacing: 0) {
                    Text(t.title)
                        .font(rounded(15, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(t.artist)
                        .font(rounded(12, .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .padding(.top, 1)
                    Spacer(minLength: 4)
                    SeekBar(track: t, accent: s.accent) { s.seek(fraction: $0) }
                    Spacer(minLength: 4)
                    HStack(spacing: 26) {
                        Button { s.previous() } label: {
                            Image(systemName: "backward.fill").font(.system(size: 16))
                        }
                        Button { s.togglePlay() } label: {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 34, height: 34)
                                Image(systemName: t.playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.black)
                                    .offset(x: t.playing ? 0 : 1)
                            }
                        }
                        Button { s.next() } label: {
                            Image(systemName: "forward.fill").font(.system(size: 16))
                        }
                    }
                    .buttonStyle(PressStyle())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(spacing: 14) {
                ArtworkThumb(image: nil, size: 72, radius: 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing playing")
                        .font(rounded(15, .bold))
                        .foregroundStyle(.white)
                    Text("Play something in Music or Spotify")
                        .font(rounded(12))
                        .foregroundStyle(.white.opacity(0.55))
                    HStack(spacing: 8) {
                        launchChip("Music", "com.apple.Music")
                        launchChip("Spotify", "com.spotify.client")
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func launchChip(_ title: String, _ bundleID: String) -> some View {
        Button {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text("Open \(title)")
                .font(rounded(11, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(PressStyle())
    }
}

struct SeekBar: View {
    let track: Track
    let accent: Color
    let onSeek: (Double) -> Void

    @Local private var drag: Double? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let elapsed = track.elapsed(at: ctx.date)
            let natural = track.duration > 0 ? elapsed / track.duration : 0
            let frac = drag ?? natural
            HStack(spacing: 7) {
                Text(mmss(Int(frac * track.duration)))
                    .font(rounded(10, .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 30, alignment: .leading)
                bar(frac)
                Text("-" + mmss(max(0, Int(track.duration - frac * track.duration))))
                    .font(rounded(10, .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private func bar(_ frac: Double) -> some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                    .frame(height: drag != nil ? 7 : 4)
                Capsule().fill(accent)
                    .frame(width: max(0, min(w, w * CGFloat(frac))), height: drag != nil ? 7 : 4)
            }
            .frame(width: w, height: geo.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        drag = min(1, max(0, Double(v.location.x / w)))
                    }
                    .onEnded { v in
                        let f = min(1, max(0, Double(v.location.x / w)))
                        onSeek(f)
                        drag = nil
                    }
            )
            .animation(.easeOut(duration: 0.15), value: drag != nil)
        }
        .frame(height: 16)
    }
}

// MARK: - Calendar

struct CalendarPane: View {
    @ObservedObject var s: ScreenState

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        return weekdayFormatter.string(from: d)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Text(weekdayFormatter.string(from: s.now).uppercased())
                    .font(rounded(11, .bold))
                    .foregroundStyle(.red)
                Text(dayFormatter.string(from: s.now))
                    .font(rounded(40, .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 92)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.09)))

            if !s.calendarAllowed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Show your schedule")
                        .font(rounded(14, .bold))
                        .foregroundStyle(.white)
                    Text("Allow calendar access to see upcoming events here.")
                        .font(rounded(11))
                        .foregroundStyle(.white.opacity(0.55))
                    Button {
                        if EKEventStore.authorizationStatus(for: .event) == .denied,
                           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        } else {
                            s.requestCalendar()
                        }
                    } label: {
                        Text("Allow Access")
                            .font(rounded(11, .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(PressStyle())
                }
                Spacer(minLength: 0)
            } else if s.events.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("All clear")
                        .font(rounded(14, .bold))
                        .foregroundStyle(.white)
                    Text("No events in the next 3 days")
                        .font(rounded(11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 24)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(s.events.prefix(3))) { ev in
                        HStack(spacing: 8) {
                            Capsule().fill(ev.color).frame(width: 3, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ev.title)
                                    .font(rounded(12, .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(ev.allDay
                                     ? "\(dayLabel(ev.start)) · All day"
                                     : "\(dayLabel(ev.start)) · \(eventTimeFormatter.string(from: ev.start))")
                                    .font(rounded(10))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Timer

struct TimerPane: View {
    @ObservedObject var s: ScreenState

    private var progress: Double {
        s.timerTotal > 0 ? Double(s.timerRemaining) / Double(s.timerTotal) : 0
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: s.timerTotal > 0 ? CGFloat(progress) : 0)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.9), value: s.timerRemaining)
                Text(s.timerTotal > 0 ? mmss(s.timerRemaining) : "0:00")
                    .font(rounded(18, .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach([1, 5, 10, 25, 45], id: \.self) { m in
                        Button { s.startTimer(minutes: m) } label: {
                            Text("\(m)m")
                                .font(rounded(11, .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 26)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                HStack(spacing: 8) {
                    Button { s.toggleTimer() } label: {
                        Text(s.timerRunning ? "Pause" : (s.timerRemaining > 0 ? "Resume" : "Start"))
                            .font(rounded(12, .bold))
                            .foregroundStyle(.black)
                            .frame(width: 78, height: 30)
                            .background(Capsule().fill(Color.orange))
                    }
                    .buttonStyle(PressStyle())
                    .opacity(s.timerRemaining > 0 ? 1 : 0.4)

                    Button { s.resetTimer() } label: {
                        Text("Reset")
                            .font(rounded(12, .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 66, height: 30)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shelf (drop files here)

struct ShelfPane: View {
    @ObservedObject var s: ScreenState
    @Local private var targeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(targeted ? Color.white : Color.white.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(targeted ? 0.12 : 0.04)))

            if s.shelf.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .medium))
                    Text("Drop files here to keep them handy")
                        .font(rounded(12, .medium))
                }
                .foregroundStyle(.white.opacity(0.6))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(s.shelf, id: \.self) { url in
                            ShelfItem(url: url, onRemove: { s.removeFromShelf(url) })
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL? = nil
                    if let d = item as? Data {
                        url = URL(dataRepresentation: d, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    }
                    if let url {
                        Task { @MainActor in s.addToShelf([url]) }
                    }
                }
            }
            return true
        }
    }
}

struct ShelfItem: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(url.lastPathComponent)
                .font(rounded(10))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Remove from Shelf", action: onRemove)
        }
    }
}
