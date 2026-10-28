import SwiftUI
import AppKit

private let relFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

func ago(_ d: Date) -> String {
    if Date().timeIntervalSince(d) < 10 { return "just now" }
    return relFormatter.localizedString(for: d, relativeTo: Date())
}

// MARK: - Root

struct ClipsView: View {
    @ObservedObject var store: ClipStore
    let activate: (Clip, Bool) -> Void
    let transform: (Clip, TextTransform) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.iconHidden {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "eye.slash.fill").foregroundStyle(.orange)
                    Text("Your menu bar is full, so the Kita Clips icon is hiding behind the notch. Open Kita Clips with ⌃⌥V or from the Clips tab in Notch Player. To make room, ⌘-drag other menu bar icons off the bar.")
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { store.iconHidden = false } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.14)))
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 640, height: 560)
        .background(.regularMaterial)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                SearchField(text: $store.query, focusToken: store.focusToken, placeholder: "Search clips")
                    .frame(height: 24)
                if store.paused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
                SettingsMenu(store: store)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ClipFilter.allCases) { f in
                        Button { store.filter = f } label: {
                            Text(f.title)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(store.filter == f ? Color.accentColor : Color.primary.opacity(0.07)))
                                .foregroundStyle(store.filter == f ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: list

    @ViewBuilder
    private var content: some View {
        let list = store.visible
        if list.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: store.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                Text(store.query.isEmpty ? "Copy something and it shows up here." : "No clips match \u{201C}\(store.query)\u{201D}")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, clip in
                            ClipCard(store: store, clip: clip, index: i,
                                     selected: store.selectedID == clip.id,
                                     activate: activate, transform: transform)
                                .id(clip.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: store.selectedID) { id in
                    if let id {
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                    }
                }
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 14) {
            Text("\(store.count) clips")
                .foregroundStyle(.secondary)
            if store.pasteDirectly && !Paster.trusted {
                Button("Allow pasting") { Paster.openAccessibilitySettings(); Paster.askForPermission() }
                    .buttonStyle(.link)
            }
            Spacer()
            Group {
                Text("↩ ") + Text(store.pasteDirectly ? "paste" : "copy")
                Text("⌘1–9 quick")
                Text("⌘P pin")
                Text("⌘⌫ delete")
                Text("⌃⌥V open")
            }
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// MARK: - Settings menu (gear)

struct SettingsMenu: View {
    @ObservedObject var store: ClipStore

    var body: some View {
        Menu {
            Toggle("Paste straight into the app", isOn: $store.pasteDirectly)
            Toggle("Save images", isOn: $store.captureImages)
            Toggle("Save copied files", isOn: $store.captureFiles)
            Toggle("Open at login", isOn: Binding(
                get: { LoginItem.isEnabled },
                set: { $0 ? LoginItem.enable() : LoginItem.disable() }))
            Divider()
            Menu("Keep up to") {
                ForEach([50, 100, 200, 500, 1000], id: \.self) { n in
                    Button { store.maxItems = n } label: {
                        Text(store.maxItems == n ? "✓ \(n) clips" : "\(n) clips")
                    }
                }
            }
            Menu("Delete after") {
                ForEach([(1, "1 day"), (7, "7 days"), (30, "30 days"), (90, "90 days"), (0, "Never")], id: \.0) { d, label in
                    Button { store.expiryDays = d } label: {
                        Text(store.expiryDays == d ? "✓ \(label)" : label)
                    }
                }
            }
            if store.paused {
                Button("Resume saving") { store.setPaused(false) }
            } else {
                Menu("Pause saving") {
                    Button("For 5 minutes") { store.setPaused(true, minutes: 5) }
                    Button("For 1 hour") { store.setPaused(true, minutes: 60) }
                    Button("Until I resume") { store.setPaused(true) }
                }
            }
            if !store.ignoredBundles.isEmpty {
                Menu("Ignored apps") {
                    ForEach(store.ignoredBundles, id: \.self) { b in
                        Button("Stop ignoring \(appName(b))") { store.stopIgnoring(b) }
                    }
                }
            }
            Divider()
            Button("Clear unpinned clips") { store.clearUnpinned() }
            Button("Show history folder") { NSWorkspace.shared.open(ClipStore.folder) }
            Divider()
            Button("Quit Kita Clips") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func appName(_ bundle: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundle
    }
}

// MARK: - Card

struct ClipCard: View {
    @ObservedObject var store: ClipStore
    let clip: Clip
    let index: Int
    let selected: Bool
    let activate: (Clip, Bool) -> Void
    let transform: (Clip, TextTransform) -> Void
    @Local private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 6) {
                preview
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(hover ? 0.07 : 0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onHover { h in
            hover = h
            if h { store.selectedID = clip.id }
        }
        .onTapGesture {
            activate(clip, NSEvent.modifierFlags.contains(.option))
        }
        .contextMenu { contextItems }
        .help(clip.text.map { String($0.prefix(600)) } ?? "")
    }

    private var badge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(clip.kind.tint.opacity(0.18))
            Image(systemName: clip.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(clip.kind.tint)
        }
        .frame(width: 30, height: 30)
    }

    @ViewBuilder
    private var preview: some View {
        switch clip.kind {
        case .image:
            if let f = clip.imageFile, let img = ThumbCache.shared.image(f) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 120, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text("Image missing").foregroundStyle(.secondary)
            }
        case .file:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(clip.fileURLs.prefix(3)), id: \.self) { u in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: u.path))
                            .resizable().frame(width: 18, height: 18)
                        Text(u.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    }
                }
                if clip.fileURLs.count > 3 {
                    Text("+\(clip.fileURLs.count - 3) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .code:
            Text(clip.text ?? "")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(red: 0.85, green: 0.9, blue: 1))
                .lineLimit(5)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.75)))
        case .link:
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(string: clip.text ?? "")?.host ?? "Link")
                    .font(.system(size: 13, weight: .semibold))
                Text(clip.text ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(2)
            }
        case .number:
            Text(clip.text ?? "")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .lineLimit(1)
        case .color:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorFromHex(clip.text ?? "") ?? .gray)
                    .frame(width: 34, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.2)))
                Text(clip.text ?? "").font(.system(size: 13, weight: .medium, design: .monospaced))
            }
        default:
            Text(clip.text ?? "")
                .font(.system(size: 13))
                .lineLimit(4)
        }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if let icon = AppIcons.icon(clip.sourceBundle) {
                Image(nsImage: icon).resizable().frame(width: 13, height: 13)
            }
            Text([clip.sourceApp, ago(clip.lastUsed), detail].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if clip.pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange)
            }
        }
    }

    private var detail: String? {
        switch clip.kind {
        case .image:
            if let w = clip.imageWidth, let h = clip.imageHeight { return "\(w)×\(h)" }
            return nil
        case .file:
            return clip.fileURLs.count == 1 ? nil : "\(clip.fileURLs.count) files"
        default:
            guard let t = clip.text else { return nil }
            let words = t.split { $0.isWhitespace || $0.isNewline }.count
            return words > 1 ? "\(words) words · \(t.count) chars" : "\(t.count) chars"
        }
    }

    @ViewBuilder
    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if hover || selected {
                HStack(spacing: 4) {
                    iconButton(clip.pinned ? "pin.slash" : "pin", "Pin") { store.togglePin(clip) }
                    if clip.kind == .link, let u = URL(string: clip.text ?? "") {
                        iconButton("arrow.up.right.square", "Open link") { NSWorkspace.shared.open(u) }
                    }
                    if clip.kind == .file {
                        iconButton("folder", "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(clip.fileURLs) }
                    }
                    iconButton("trash", "Delete") { store.delete(clip) }
                }
            }
        }
        .frame(minWidth: 30, alignment: .trailing)
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var contextItems: some View {
        Button("Copy") { activate(clip, store.pasteDirectly) }
        Button(store.pasteDirectly ? "Copy only" : "Copy and paste") { activate(clip, !store.pasteDirectly) }
        if clip.text != nil {
            Menu("Copy as") {
                ForEach(TextTransform.allCases) { t in
                    Button(t.title) { transform(clip, t) }
                }
            }
        }
        Divider()
        Button(clip.pinned ? "Unpin" : "Pin") { store.togglePin(clip) }
        if clip.kind == .link, let u = URL(string: clip.text ?? "") {
            Button("Open link") { NSWorkspace.shared.open(u) }
        }
        if clip.kind == .file {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(clip.fileURLs) }
        }
        if clip.kind == .image, let f = clip.imageFile {
            Button("Open image") { NSWorkspace.shared.open(ClipStore.imageURL(f)) }
        }
        if let app = clip.sourceApp, clip.sourceBundle?.isEmpty == false {
            Button("Stop saving from \(app)") { store.ignoreApp(of: clip) }
        }
        Divider()
        Button("Delete") { store.delete(clip) }
    }
}

// MARK: - Search field (AppKit, so it can be focused reliably)

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 16)
        f.placeholderString = placeholder
        f.delegate = context.coordinator
        f.cell?.lineBreakMode = .byTruncatingTail
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.text = $text
        if f.stringValue != text { f.stringValue = text }
        if context.coordinator.lastToken != focusToken {
            context.coordinator.lastToken = focusToken
            DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var lastToken = -1
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSTextField { text.wrappedValue = f.stringValue }
        }
    }
}
