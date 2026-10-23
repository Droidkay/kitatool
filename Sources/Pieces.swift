import SwiftUI

struct TabButton: View {
    let icon: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(on ? .white : .white.opacity(hover ? 0.7 : 0.4))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(on ? 0.14 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct MusicPanel: View {
    @ObservedObject var np: NowPlaying

    var body: some View {
        if let t = np.track {
            HStack(alignment: .center, spacing: 14) {
                Artwork(image: np.artwork, size: 74, radius: 14)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(t.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                        Spacer(minLength: 4)
                        Equalizer(color: .green, playing: np.isPlaying).frame(width: 14, height: 11)
                    }
                    Text(t.artist).font(.system(size: 12)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                    ProgressRow(np: np)
                    HStack(spacing: 26) {
                        Spacer()
                        Control(icon: "backward.fill", size: 15) { np.previous() }
                        Control(icon: np.isPlaying ? "pause.fill" : "play.fill", size: 21) { np.playPause() }
                        Control(icon: "forward.fill", size: 15) { np.next() }
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.top, 6)
        } else if np.needsPermission {
            Empty(icon: "lock.fill", line: "Allow Notch Player to see your music",
                  buttons: [("Open Settings", { np.openPrivacySettings() })])
        } else {
            Empty(icon: "music.note", line: "Nothing playing", buttons: openButtons)
        }
    }

    private var openButtons: [(String, () -> Void)] {
        var b: [(String, () -> Void)] = []
        if NowPlaying.installed(.spotify) { b.append(("Open Spotify", { np.open(.spotify) })) }
        b.append(("Open Music", { np.open(.music) }))
        return b
    }
}

struct ProgressRow: View {
    @ObservedObject var np: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let dur = np.track?.duration ?? 0
            let pos = np.livePosition
            HStack(spacing: 8) {
                Text(TimerModel.format(pos)).font(.system(size: 10).monospacedDigit()).foregroundColor(.white.opacity(0.5))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white).frame(width: dur > 0 ? g.size.width * CGFloat(pos / dur) : 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { p in
                        if dur > 0 { np.seek(to: Double(p.x / g.size.width) * dur) }
                    }
                }
                .frame(height: 4)
                Text(dur > 0 ? "-" + TimerModel.format(max(0, dur - pos)) : "").font(.system(size: 10).monospacedDigit()).foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 4)
        }
    }
}

struct TimerPanel: View {
    @ObservedObject var timer: TimerModel
    let done: Bool

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(max(0.0001, 1 - timer.progress)))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: timer.progress)
                Text(done ? "done" : (timer.isRunning || timer.isPaused ? TimerModel.format(timer.remaining) : "0:00"))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundColor(done ? .orange : .white)
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach([5, 10, 25, 45], id: \.self) { m in
                        Chip(label: "\(m)m") { timer.start(minutes: m) }
                    }
                }
                HStack(spacing: 22) {
                    Control(icon: timer.isRunning ? "pause.fill" : "play.fill", size: 18) {
                        if timer.isRunning || timer.isPaused { timer.pauseResume() } else { timer.start(minutes: 25) }
                    }
                    Control(icon: "plus", size: 15) { timer.addMinute() }
                    Control(icon: "arrow.counterclockwise", size: 15) { timer.reset() }
                        .opacity(timer.isRunning || timer.isPaused ? 1 : 0.35)
                }
                .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

// MARK: - pieces

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(LinearGradient(colors: [Color(red: 0, green: 0.76, blue: 1), Color(red: 0.55, green: 0.36, blue: 1)],
                                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            if let img = image {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.4, weight: .semibold)).foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// Four bouncing bars while music plays.
struct Equalizer: View {
    let color: Color
    let playing: Bool

    static func level(_ i: Int, _ t: Double, _ playing: Bool) -> CGFloat {
        if !playing { return 0.25 }
        let speed: Double = 3.1 + Double(i) * 1.3
        let phase: Double = Double(i) * 1.7
        let wave: Double = abs(sin(t * speed + phase))
        return CGFloat(0.3 + 0.7 * wave)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !playing)) { ctx in
            bars(ctx.date.timeIntervalSinceReferenceDate)
        }
    }

    private func bars(_ t: Double) -> some View {
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: g.size.width * 0.12) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(height: max(2, g.size.height * Equalizer.level(i, t, playing)))
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
        }
    }
}

struct Control: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size + 18, height: size + 14)
                .background(Circle().fill(Color.white.opacity(hover ? 0.14 : 0)))
                .scaleEffect(hover ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct Chip: View {
    let label: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(hover ? 0.2 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct Empty: View {
    let icon: String
    let line: String
    let buttons: [(String, () -> Void)]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(.white.opacity(0.5))
                Text(line).font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.7))
            }
            HStack(spacing: 8) {
                ForEach(0..<buttons.count, id: \.self) { i in
                    Chip(label: buttons[i].0, action: buttons[i].1)
                }
            }
        }
        .padding(.top, 10)
    }
}
