import AppKit

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double   // seconds
    var artworkURL: String // Spotify gives a link; Music gives raw image data instead
    var player: Player
}

enum Player: String {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var name: String { self == .spotify ? "Spotify" : "Music" }
}

/// Reads what Spotify or Apple Music is playing (via AppleScript) and controls it.
/// Only talks to an app that's already open, so it never launches one by itself.
final class NowPlaying: ObservableObject {
    @Published var track: Track?
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    /// Position at `positionAt` (we count forward from there between checks).
    @Published var position: Double = 0
    @Published var positionAt = Date()
    @Published var needsPermission = false

    private var timer: Timer?
    private var artKey = ""
    private var scripts: [String: NSAppleScript] = [:]

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func refreshSoon() {
        DispatchQueue.main.async { self.refresh() }
    }

    var livePosition: Double {
        guard let t = track else { return 0 }
        let p = isPlaying ? position + Date().timeIntervalSince(positionAt) : position
        return min(max(0, p), t.duration > 0 ? t.duration : p)
    }

    private func running(_ p: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: p.rawValue).isEmpty
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let s = scripts[source] { script = s } else {
            guard let s = NSAppleScript(source: source) else { return nil }
            scripts[source] = s
            script = s
        }
        var err: NSDictionary?
        let out = script.executeAndReturnError(&err)
        if let e = err {
            // -1743: the person said no (or hasn't been asked) in Privacy → Automation
            if let code = e[NSAppleScript.errorNumber] as? Int, code == -1743 {
                DispatchQueue.main.async { self.needsPermission = true }
            }
            return nil
        }
        return out
    }

    func refresh() {
        // Prefer whichever app is actually playing.
        var best: (Track, Bool, Double)?
        for p in [Player.spotify, Player.music] where running(p) {
            if let r = read(p) {
                if r.1 { best = r; break }
                if best == nil { best = r }
            }
        }
        guard let found = best else {
            if track != nil { track = nil; artwork = nil; artKey = ""; isPlaying = false }
            return
        }
        let (t, playing, pos) = found
        needsPermission = false
        if track != t { track = t }
        if isPlaying != playing { isPlaying = playing }
        // only correct the clock when it's drifted, so the bar doesn't jitter
        if abs(livePosition - pos) > 1.2 || !playing {
            position = pos
            positionAt = Date()
        }
        loadArtwork(t)
    }

    private static let sep = "‖"

    private func read(_ p: Player) -> (Track, Bool, Double)? {
        let src: String
        if p == .spotify {
            src = """
            tell application id "com.spotify.client"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & "\(NowPlaying.sep)" & (name of t) & "\(NowPlaying.sep)" & (artist of t) & "\(NowPlaying.sep)" & (album of t) & "\(NowPlaying.sep)" & ((duration of t) / 1000) & "\(NowPlaying.sep)" & (player position) & "\(NowPlaying.sep)" & (artwork url of t)
            end tell
            """
        } else {
            src = """
            tell application id "com.apple.Music"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & "\(NowPlaying.sep)" & (name of t) & "\(NowPlaying.sep)" & (artist of t) & "\(NowPlaying.sep)" & (album of t) & "\(NowPlaying.sep)" & (duration of t) & "\(NowPlaying.sep)" & (player position) & "\(NowPlaying.sep)" & ""
            end tell
            """
        }
        guard let s = run(src)?.stringValue, s != "stopped" else { return nil }
        let parts = s.components(separatedBy: NowPlaying.sep)
        guard parts.count >= 7 else { return nil }
        let num: (String) -> Double = { Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let t = Track(title: parts[1], artist: parts[2], album: parts[3], duration: num(parts[4]), artworkURL: parts[6], player: p)
        return (t, parts[0] == "playing", num(parts[5]))
    }

    private func loadArtwork(_ t: Track) {
        let key = t.player.rawValue + t.title + t.album
        if key == artKey { return }
        artKey = key
        artwork = nil
        if t.player == .spotify, let url = URL(string: t.artworkURL), !t.artworkURL.isEmpty {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let d = data, let img = NSImage(data: d) else { return }
                DispatchQueue.main.async { if self.artKey == key { self.artwork = img } }
            }.resume()
        } else if t.player == .music {
            let src = "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
            if let d = run(src)?.data, let img = NSImage(data: d) { artwork = img }
        }
    }

    // MARK: controls

    private func send(_ command: String) {
        var target = track?.player
        if target == nil { target = [Player.spotify, Player.music].first(where: { running($0) }) }
        guard let p = target else { return }
        _ = run("tell application id \"\(p.rawValue)\" to \(command)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.refresh() }
    }

    func playPause() {
        isPlaying.toggle()
        position = livePosition
        positionAt = Date()
        send("playpause")
    }

    func next() { send("next track") }

    func previous() {
        // like phones: restart the song first, go back if already near the start
        if livePosition > 4 { seek(to: 0) } else { send("previous track") }
    }

    func seek(to seconds: Double) {
        position = seconds
        positionAt = Date()
        send("set player position to \(String(format: "%.1f", seconds).replacingOccurrences(of: ",", with: "."))")
    }

    func open(_ p: Player) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.rawValue) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    static func installed(_ p: Player) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.rawValue) != nil
    }
}
