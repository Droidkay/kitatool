import Foundation
import AppKit

enum MusicSource: String, CaseIterable {
    case music = "Music"
    case spotify = "Spotify"

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
}

struct Track: Equatable {
    var source: MusicSource
    var title: String
    var artist: String
    var position: Double      // seconds, at the moment of polling
    var duration: Double      // seconds
    var playing: Bool
    var polledAt: Date

    var id: String { "\(source.rawValue)|\(title)|\(artist)" }

    func elapsed(at now: Date) -> Double {
        let e = position + (playing ? now.timeIntervalSince(polledAt) : 0)
        return min(max(e, 0), duration > 0 ? duration : e)
    }
}

enum MusicBridge {
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result
    }

    static func query(_ s: MusicSource) -> Track? {
        let src: String
        switch s {
        case .music:
            src = """
            tell application "Music"
              if player state is stopped then return {}
              set t to current track
              return {name of t, artist of t, (player position as integer), (duration of t as integer), (player state as string)}
            end tell
            """
        case .spotify:
            src = """
            tell application "Spotify"
              if player state is stopped then return {}
              return {name of current track, artist of current track, (player position as integer), (duration of current track), (player state as string)}
            end tell
            """
        }
        guard let r = run(src), r.numberOfItems >= 5,
              let title = r.atIndex(1)?.stringValue,
              let artist = r.atIndex(2)?.stringValue,
              let state = r.atIndex(5)?.stringValue else { return nil }
        let pos = Double(r.atIndex(3)?.int32Value ?? 0)
        var dur = Double(r.atIndex(4)?.int32Value ?? 0)
        if s == .spotify { dur /= 1000 }   // Spotify reports milliseconds
        return Track(source: s, title: title, artist: artist, position: pos, duration: dur,
                     playing: state.lowercased().contains("playing"), polledAt: Date())
    }

    @MainActor
    static func artwork(for s: MusicSource) async -> NSImage? {
        switch s {
        case .music:
            let src = """
            tell application "Music"
              try
                return data of artwork 1 of current track
              on error
                return missing value
              end try
            end tell
            """
            guard let r = run(src) else { return nil }
            let data = r.data
            return data.isEmpty ? nil : NSImage(data: data)
        case .spotify:
            let src = """
            tell application "Spotify"
              return artwork url of current track
            end tell
            """
            guard let urlString = run(src)?.stringValue, let url = URL(string: urlString) else { return nil }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: data)
        }
    }

    static func command(_ s: MusicSource, _ cmd: String) {
        _ = run("tell application \"\(s.rawValue)\" to \(cmd)")
    }
}
