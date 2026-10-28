import SwiftUI
import AppKit

private func rf(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

private let noteTime: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f
}()

func noteAgo(_ d: Date) -> String {
    let s = Int(Date().timeIntervalSince(d))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m ago" }
    return noteTime.string(from: d)
}

// MARK: - iPhone-style notification banner from the notch

struct NotificationBanner: View {
    @ObservedObject var s: ScreenState
    let note: NotchNote

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                appIcon(size: 20)
                    .frame(width: s.flankW)
                Spacer(minLength: 0)
                Text("now")
                    .font(rf(11, .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: s.flankW)
            }
            .padding(.horizontal, s.ear)
            .frame(height: s.geometry.notchH)

            HStack(alignment: .center, spacing: 12) {
                appIcon(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(note.title.isEmpty ? note.appName : note.title)
                            .font(rf(13, .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !note.title.isEmpty && note.title != note.appName {
                            Text(note.appName)
                                .font(rf(10, .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    Text(note.subtitle.isEmpty ? note.body : "\(note.subtitle) · \(note.body)")
                        .font(rf(12))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func appIcon(size: CGFloat) -> some View {
        if let img = NotificationReader.icon(for: note.bundle) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "bell.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.25).fill(Color.blue))
        }
    }
}

// MARK: - Robot check-in banner

struct CheckInBanner: View {
    @ObservedObject var s: ScreenState
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RobotFace(brain: s.robot, base: .curious, accent: s.accent)
                    .frame(width: s.flankW)
                Spacer(minLength: 0)
                Text("hover")
                    .font(rf(10, .semibold))
                    .foregroundStyle(.cyan.opacity(0.8))
                    .frame(width: s.flankW)
            }
            .padding(.horizontal, s.ear)
            .frame(height: s.geometry.notchH)

            Text(text)
                .font(rf(12.5, .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 4)
        }
    }
}

// MARK: - Buddy page

struct BuddyPane: View {
    @ObservedObject var s: ScreenState
    @ObservedObject var buddy: Companion

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Button { buddy.poke() } label: {
                    RobotFace(brain: s.robot, base: s.robotBaseMood, accent: s.accent)
                        .scaleEffect(2.1)
                        .frame(width: 92, height: 70)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(PressStyle())
                .help("Tap me")
                Text(Companion.hm(buddy.activeToday) + " today")
                    .font(rf(10, .medium))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    Text("☕\(buddy.breaksToday)")
                    Text("💧\(buddy.waterToday)")
                    Text("🎯\(buddy.focusToday)")
                }
                .font(rf(10, .semibold))
                .foregroundStyle(.white.opacity(0.75))
            }
            .frame(width: 96)

            VStack(alignment: .leading, spacing: 8) {
                if let until = buddy.breathingUntil {
                    BreathingView(until: until)
                } else {
                    chat
                }
                bottomRow
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    if buddy.lines.isEmpty {
                        bubble(BuddyLine(fromBuddy: true, text: "Hi \(buddy.name)! I'm your notch buddy 🤖 Tap me, or let me know how you're doing."))
                    }
                    ForEach(buddy.lines) { line in
                        bubble(line).id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .onAppear { if let last = buddy.lines.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            .onChange(of: buddy.lines) { lines in
                if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private func bubble(_ line: BuddyLine) -> some View {
        HStack {
            if !line.fromBuddy { Spacer(minLength: 40) }
            Text(line.text)
                .font(rf(11.5, .medium))
                .foregroundStyle(line.fromBuddy ? Color.white : Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(line.fromBuddy ? Color.white.opacity(0.12) : Color.cyan))
                .fixedSize(horizontal: false, vertical: true)
            if line.fromBuddy { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bottomRow: some View {
        if buddy.asking {
            HStack(spacing: 6) {
                ForEach(BuddyMood.allCases, id: \.self) { m in
                    chip("\(m.emoji) \(m.title)", strong: true) { buddy.answer(m) }
                }
            }
        } else {
            HStack(spacing: 6) {
                chip("💧 Water") { buddy.drinkWater() }
                chip("☕ Break") { buddy.takeBreak() }
                chip("🎯 Focus") { buddy.startFocus() }
                chip("🌿 Breathe") { buddy.breathe() }
                chip("💬") { buddy.checkIn() }
            }
        }
    }

    private func chip(_ title: String, strong: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(rf(11, .semibold))
                .foregroundStyle(strong ? Color.black : Color.white)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(strong ? Color.white : Color.white.opacity(0.14)))
        }
        .buttonStyle(PressStyle())
    }
}

struct BreathingView: View {
    let until: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { ctx in
            let left = max(0, until.timeIntervalSince(ctx.date))
            let t = (60 - left).truncatingRemainder(dividingBy: 12)
            let phase: (String, CGFloat) = t < 4 ? ("Breathe in", 0.55 + 0.45 * CGFloat(t / 4))
                : t < 8 ? ("Hold", 1)
                : ("Breathe out", 1 - 0.45 * CGFloat((t - 8) / 4))
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.cyan.opacity(0.9), Color.teal.opacity(0.25)],
                                             center: .center, startRadius: 2, endRadius: 40))
                        .frame(width: 74, height: 74)
                        .scaleEffect(phase.1)
                        .shadow(color: .cyan.opacity(0.6), radius: 12)
                }
                .frame(width: 80, height: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.0)
                        .font(rf(17, .bold))
                        .foregroundStyle(.white)
                    Text("\(Int(left.rounded(.up)))s left")
                        .font(rf(11, .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Notifications page

struct AlertsPane: View {
    @ObservedObject var s: ScreenState

    var body: some View {
        if s.notesStatus == .needsAccess || s.notesStatus == .notFound {
            HStack(spacing: 14) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.red, .white)
                    .frame(width: 70, height: 70)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Show notifications in the notch")
                        .font(rf(14, .bold)).foregroundStyle(.white)
                    Text("Turn on Notch Player in Full Disk Access, then quit and reopen it. macOS only lets apps see notifications this way.")
                        .font(rf(11)).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    Button { NotificationReader.openFullDiskAccessSettings() } label: {
                        Text("Open Full Disk Access")
                            .font(rf(11, .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(PressStyle())
                }
                Spacer(minLength: 0)
            }
        } else if s.notes.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "bell.slash").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
                Text("No new notifications").font(rf(13, .semibold)).foregroundStyle(.white.opacity(0.7))
                Text("New ones drop down from the notch like on iPhone.")
                    .font(rf(11)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                HStack {
                    Text("Notifications").font(rf(12, .bold)).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Button("Clear") { s.core.clearNotes() }
                        .buttonStyle(.plain)
                        .font(rf(11, .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(s.notes) { n in
                            Button { open(n) } label: { row(n) }
                                .buttonStyle(PressStyle())
                        }
                    }
                }
            }
        }
    }

    private func row(_ n: NotchNote) -> some View {
        HStack(spacing: 10) {
            if let img = NotificationReader.icon(for: n.bundle) {
                Image(nsImage: img).resizable().frame(width: 28, height: 28)
            } else {
                Image(systemName: "bell.fill").foregroundStyle(.white).frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(n.title.isEmpty ? n.appName : n.title)
                        .font(rf(12, .bold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(noteAgo(n.date)).font(rf(10)).foregroundStyle(.white.opacity(0.45))
                }
                Text(n.body).font(rf(11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func open(_ n: NotchNote) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: n.bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
