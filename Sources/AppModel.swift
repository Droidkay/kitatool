import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The thumbnail being edited, its picture, the checks and the four options.
final class AppModel: ObservableObject {
    @Published var design: Design { didSet { if design != oldValue { scheduleRender(); scheduleAutosave() } } }
    @Published private(set) var image: NSImage?
    @Published private(set) var layout = Layout()
    @Published private(set) var checks: [Check] = []
    @Published private(set) var options: [(String, NSImage, Design)] = []
    @Published var selected: UUID?
    @Published var presets: [String] = []
    @Published var status: String = ""
    private var renderWork: DispatchWorkItem?
    private var optionsWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?

    static let folder: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Thumbnail Lab")
        try? FileManager.default.createDirectory(at: u.appendingPathComponent("Presets"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: u.appendingPathComponent("Pictures"), withIntermediateDirectories: true)
        return u
    }()

    init() {
        if let data = try? Data(contentsOf: AppModel.folder.appendingPathComponent("last.json")),
           let d = try? JSONDecoder().decode(Design.self, from: data) {
            design = d
        } else {
            design = Template.psalm.make()
        }
        ImageStore.shared.onReady = { [weak self] in self?.renderNow() }
        loadPresets()
        renderNow()
    }

    var selectedIndex: Int? { design.blocks.firstIndex { $0.id == selected } }

    // MARK: rendering

    func scheduleRender() {
        renderWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.renderNow(options: false) }
        renderWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: w)
        optionsWork?.cancel()
        let o = DispatchWorkItem { [weak self] in self?.renderOptions() }
        optionsWork = o
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: o)
    }

    func renderNow(options: Bool = true) {
        let (cg, lay) = Renderer.render(design)
        if let cg = cg { image = NSImage(cgImage: cg, size: NSSize(width: Design.W, height: Design.H)) }
        layout = lay
        let plate = Renderer.render(design, drawText: false).0
        checks = Checks.run(design, layout: lay, plate: plate)
        if options { renderOptions() }
    }

    func renderOptions() {
        options = Layouts.variations(design).compactMap { name, d in
            guard let cg = Renderer.render(d).0 else { return nil }
            return (name, NSImage(cgImage: cg, size: NSSize(width: Design.W, height: Design.H)), d)
        }
    }

    // MARK: actions

    func use(_ t: Template) {
        design = t.make(keeping: design)
        selected = nil
    }

    func keepOffFace() {
        design = Layouts.keepOffFace(design, layout: layout)
        status = layout.faceRect.isNull ? "Moved the text away from the person." : "Moved the text away from the face."
    }

    /// Copies a picture into the app's folder so presets keep working if the original moves.
    func importPicture(_ url: URL) -> String? {
        let dest = AppModel.folder.appendingPathComponent("Pictures").appendingPathComponent(UUID().uuidString + "." + (url.pathExtension.isEmpty ? "png" : url.pathExtension))
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest.path
        } catch {
            return url.path
        }
    }

    func setPerson(_ url: URL) {
        guard let p = importPicture(url) else { return }
        design.subject.imagePath = p
        status = "Finding the face and lifting the person off the background…"
    }

    func setBackgroundPicture(_ url: URL) {
        guard let p = importPicture(url) else { return }
        design.background.imagePath = p
        design.background.kind = .image
        if design.background.darken < 0.25 { design.background.darken = 0.35 }
    }

    func choosePicture(background: Bool) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        p.message = background ? "Choose a background picture" : "Choose a photo of the person"
        if p.runModal() == .OK, let u = p.url {
            if background { setBackgroundPicture(u) } else { setPerson(u) }
        }
    }

    func addText() {
        let b = TextBlock(name: "Text \(design.blocks.count + 1)", text: "NEW [TEXT]", x: 60, y: 300, w: 520, h: 140, maxSize: 90)
        design.blocks.append(b)
        selected = b.id
    }

    func deleteSelected() {
        guard let i = selectedIndex else { return }
        design.blocks.remove(at: i)
        selected = nil
    }

    // MARK: export

    /// PNG, or JPEG if the PNG would be over YouTube's 2 MB limit.
    static func encode(_ cg: CGImage) -> (Data, String) {
        let rep = NSBitmapImageRep(cgImage: cg)
        if let png = rep.representation(using: .png, properties: [:]), png.count < 2_000_000 { return (png, "png") }
        var q = 0.92
        while q > 0.5 {
            if let j = rep.representation(using: .jpeg, properties: [.compressionFactor: q]), j.count < 2_000_000 { return (j, "jpg") }
            q -= 0.07
        }
        return (rep.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) ?? Data(), "jpg")
    }

    func export() {
        guard let cg = Renderer.render(design).0 else { return }
        let (data, ext) = AppModel.encode(cg)
        let p = NSSavePanel()
        p.nameFieldStringValue = fileName() + "." + ext
        p.allowedContentTypes = [ext == "png" ? .png : .jpeg]
        if p.runModal() == .OK, let u = p.url {
            do {
                try data.write(to: u)
                status = "Saved \(u.lastPathComponent) (\(data.count / 1024) KB)"
                NSWorkspace.shared.activateFileViewerSelecting([u])
            } catch {
                status = "Couldn't save: \(error.localizedDescription)"
            }
        }
    }

    var hasDate: Bool { design.blocks.contains { $0.dateFormat != nil } }

    /// One thumbnail for each of the next 7 days, only the date changing.
    func exportWeek() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Save 7 here"
        p.message = "Choose a folder for this week's thumbnails"
        guard p.runModal() == .OK, let dir = p.url else { return }
        var d = design
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd EEEE"
        for i in 0..<7 {
            d.date = cal.date(byAdding: .day, value: i, to: design.date) ?? design.date
            guard let cg = Renderer.render(d).0 else { continue }
            let (data, ext) = AppModel.encode(cg)
            try? data.write(to: dir.appendingPathComponent("\(f.string(from: d.date)).\(ext)"))
        }
        status = "Saved 7 thumbnails to \(dir.lastPathComponent)"
        NSWorkspace.shared.open(dir)
    }

    func copyToClipboard() {
        guard let cg = Renderer.render(design).0 else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: cg, size: NSSize(width: Design.W, height: Design.H))])
        status = "Copied. Paste it into YouTube Studio or CapCut."
    }

    func fileName() -> String {
        let t = design.blocks.first { $0.name == "Title" }.map { Renderer.lines(of: $0, date: design.date).joined(separator: " ") } ?? "thumbnail"
        let clean = t.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
        return String(clean.prefix(50)).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
    }

    // MARK: presets (your own templates)

    func loadPresets() {
        let dir = AppModel.folder.appendingPathComponent("Presets")
        presets = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    func savePreset(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let data = try? JSONEncoder().encode(design) else { return }
        try? data.write(to: AppModel.folder.appendingPathComponent("Presets").appendingPathComponent(n.replacingOccurrences(of: "/", with: "-") + ".json"))
        loadPresets()
        status = "Saved \"\(n)\" to My templates"
    }

    func openPreset(_ name: String) {
        let u = AppModel.folder.appendingPathComponent("Presets").appendingPathComponent(name + ".json")
        guard let data = try? Data(contentsOf: u), var d = try? JSONDecoder().decode(Design.self, from: data) else { return }
        d.date = design.date
        design = d
        selected = nil
    }

    func deletePreset(_ name: String) {
        try? FileManager.default.removeItem(at: AppModel.folder.appendingPathComponent("Presets").appendingPathComponent(name + ".json"))
        loadPresets()
    }

    private func scheduleAutosave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, let data = try? JSONEncoder().encode(self.design) else { return }
            try? data.write(to: AppModel.folder.appendingPathComponent("last.json"))
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
    }
}
