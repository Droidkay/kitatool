import AppKit
import SwiftUI

// Thumbnail Lab: YouTube thumbnails from your own templates, with the face kept clear of text.

/// `ThumbnailLab --samples <folder> [person.png]` renders every template to PNG (used to check the design).
func renderSamples(_ args: [String]) -> Never {
    let out = URL(fileURLWithPath: args.count > 2 ? args[2] : "samples")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let person = args.count > 3 ? args[3] : nil
    if let p = person { ImageStore.shared.analyseNow(p) }
    var date = DateComponents()
    date.year = 2026; date.month = 10; date.day = 24
    for t in Template.allCases {
        var d = t.make()
        d.date = Calendar.current.date(from: date) ?? Date()
        d.subject.imagePath = person
        var (cg, lay) = Renderer.render(d)
        let before = Checks.run(d, layout: lay, plate: Renderer.render(d, drawText: false).0)
        print("\(t.title): " + before.map { "[\($0.level)] \($0.text)" }.joined(separator: " | "))
        if let c = cg { try? AppModel.encode(c).0.write(to: out.appendingPathComponent("\(t.rawValue).png")) }
        // the mirrored and bolder options, and keep-off-face
        for (name, v) in Layouts.variations(d).dropFirst() {
            if let c = Renderer.render(v).0 { try? AppModel.encode(c).0.write(to: out.appendingPathComponent("\(t.rawValue)-\(name.lowercased().replacingOccurrences(of: " ", with: "-")).png")) }
        }
        let moved = Layouts.keepOffFace(Layouts.mirrored(d), layout: Renderer.render(Layouts.mirrored(d)).1)
        (cg, lay) = Renderer.render(moved)
        if let c = cg { try? AppModel.encode(c).0.write(to: out.appendingPathComponent("\(t.rawValue)-mirrored-keepoff.png")) }
    }
    print("samples written to \(out.path)")
    exit(0)
}

if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--samples" {
    renderSamples(CommandLine.arguments)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = AppModel()

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Thumbnail Lab"
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 1180, height: 760)
        window.contentView = NSHostingView(rootView: ContentView(m: model))
        window.center()
        window.setFrameAutosaveName("main")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        buildMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Thumbnail Lab", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Thumbnail Lab", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Thumbnail Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Choose Photo…", action: #selector(choosePhoto), keyEquivalent: "o").target = self
        file.addItem(withTitle: "Export…", action: #selector(exportIt), keyEquivalent: "e").target = self
        fileItem.submenu = file
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc func choosePhoto() { model.choosePicture(background: false) }
    @objc func exportIt() { model.export() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
