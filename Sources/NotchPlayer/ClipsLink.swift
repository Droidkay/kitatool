import SwiftUI
import AppKit

/// A clip from Kita Clips' history (only the fields the notch needs).
struct MiniClip: Decodable, Identifiable, Equatable {
    let id: UUID
    let kind: String
    var text: String?
    var imageFile: String?
    var filePaths: [String]?
    var lastUsed: Date
    var pinned: Bool?

    var fileURLs: [URL] { (filePaths ?? []).map { URL(fileURLWithPath: $0) } }
}

/// Reads Kita Clips' history so the notch can show your clipboard.
@MainActor
final class ClipsLink: ObservableObject {
    @Published private(set) var clips: [MiniClip] = []
    @Published private(set) var installed = false
    @Published var justCopied: UUID?

    private var lastModified: Date?
    private var suppressBannerUntil = Date.distantPast
    private var lastTopID: UUID?
    var onNewCopy: ((MiniClip) -> Void)?

    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KitaClips", isDirectory: true)
    private var historyURL: URL { ClipsLink.folder.appendingPathComponent("history.json") }

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.droidkay.kitaclips.changed"), object: nil, queue: .main
        ) { [weak self] _ in
            let me = self
            MainActor.assumeIsolated { me?.reload(force: true) }
        }
        reload(force: true)
    }

    var appInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.droidkay.kitaclips") != nil
    }

    /// Cheap check, called every second.
    func reload(force: Bool = false) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: historyURL.path)
        let mod = attrs?[.modificationDate] as? Date
        installed = mod != nil || appInstalled
        guard let mod else { clips = []; return }
        if !force, mod == lastModified { return }
        lastModified = mod
        guard let data = try? Data(contentsOf: historyURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let list = try? dec.decode([MiniClip].self, from: data) else { return }
        let sorted = list.sorted {
            let a = $0.pinned ?? false, b = $1.pinned ?? false
            if a != b { return a }
            return $0.lastUsed > $1.lastUsed
        }
        let newestByTime = list.max { $0.lastUsed < $1.lastUsed }
        clips = Array(sorted.prefix(30))
        if let top = newestByTime, top.id != lastTopID {
            let first = lastTopID == nil
            lastTopID = top.id
            if !first, Date() > suppressBannerUntil, Date().timeIntervalSince(top.lastUsed) < 10 {
                onNewCopy?(top)
            }
        }
    }

    /// Copy a clip back to the clipboard (Kita Clips then moves it to the top).
    func copy(_ c: MiniClip) {
        suppressBannerUntil = Date().addingTimeInterval(3)
        let pb = NSPasteboard.general
        pb.clearContents()
        switch c.kind {
        case "image":
            if let f = c.imageFile,
               let img = NSImage(contentsOf: ClipsLink.folder.appendingPathComponent("images").appendingPathComponent(f)) {
                pb.writeObjects([img])
            }
        case "file":
            pb.writeObjects(c.fileURLs as [NSURL])
        default:
            pb.setString(c.text ?? "", forType: .string)
        }
        justCopied = c.id
        let id = c.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if self.justCopied == id { self.justCopied = nil }
        }
    }

    /// Opens Kita Clips' full window (or launches it).
    func openKitaClips() {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.droidkay.kitaclips").isEmpty
        if running {
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.droidkay.kitaclips.show"), object: nil, userInfo: nil, deliverImmediately: true)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.droidkay.kitaclips") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func thumbnail(_ c: MiniClip) -> NSImage? {
        guard let f = c.imageFile else { return nil }
        return NSImage(contentsOf: ClipsLink.folder.appendingPathComponent("images").appendingPathComponent(f))
    }
}

// MARK: - Clips tab

private func rf(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

struct ClipsPane: View {
    @ObservedObject var link: ClipsLink

    var body: some View {
        if link.clips.isEmpty {
            HStack(spacing: 14) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 70, height: 70)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 6) {
                    Text(link.installed ? "Nothing copied yet" : "Your clipboard, in the notch")
                        .font(rf(14, .bold)).foregroundStyle(.white)
                    Text(link.installed ? "Copy something and it shows up here." : "Install and open Kita Clips, and everything you copy shows up here.")
                        .font(rf(11)).foregroundStyle(.white.opacity(0.6))
                    if link.appInstalled {
                        openButton
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Clipboard")
                        .font(rf(12, .bold)).foregroundStyle(.white.opacity(0.8))
                    Text("tap to copy")
                        .font(rf(10)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    openButton
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(link.clips) { c in
                            Button { link.copy(c) } label: { card(c) }
                                .buttonStyle(PressStyle())
                        }
                    }
                }
            }
        }
    }

    private var openButton: some View {
        Button { link.openKitaClips() } label: {
            Text("Open Kita Clips")
                .font(rf(10.5, .semibold)).foregroundStyle(.black)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(PressStyle())
    }

    private func card(_ c: MiniClip) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: symbol(c.kind))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint(c.kind))
                    if c.pinned == true {
                        Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
                preview(c)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 118, height: 82, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.09)))

            if link.justCopied == c.id {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.85))
                    .overlay(Label("Copied", systemImage: "checkmark").font(rf(12, .bold)).foregroundStyle(.white))
                    .frame(width: 118, height: 82)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: link.justCopied)
    }

    @ViewBuilder
    private func preview(_ c: MiniClip) -> some View {
        switch c.kind {
        case "image":
            if let img = link.thumbnail(c) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 102, height: 52).clipShape(RoundedRectangle(cornerRadius: 6))
            }
        case "file":
            HStack(spacing: 5) {
                if let u = c.fileURLs.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 22, height: 22)
                    Text(u.lastPathComponent).font(rf(10.5, .medium)).foregroundStyle(.white).lineLimit(2)
                }
            }
        case "code":
            Text(c.text ?? "").font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color(red: 0.8, green: 0.88, blue: 1)).lineLimit(4)
        case "link":
            Text(URL(string: c.text ?? "")?.host ?? (c.text ?? ""))
                .font(rf(11, .semibold)).foregroundStyle(Color(red: 0.45, green: 0.7, blue: 1)).lineLimit(3)
        default:
            Text(c.text ?? "").font(rf(11, .medium)).foregroundStyle(.white).lineLimit(4)
        }
    }

    private func symbol(_ k: String) -> String {
        switch k {
        case "link": return "link"
        case "email": return "envelope.fill"
        case "number": return "number"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "color": return "paintpalette.fill"
        case "image": return "photo.fill"
        case "file": return "doc.fill"
        default: return "text.alignleft"
        }
    }

    private func tint(_ k: String) -> Color {
        switch k {
        case "link": return Color(red: 0.3, green: 0.6, blue: 1)
        case "code": return Color(red: 0.7, green: 0.5, blue: 1)
        case "image": return .green
        case "file": return .yellow
        case "number": return .orange
        case "color": return .pink
        default: return Color(white: 0.75)
        }
    }
}
