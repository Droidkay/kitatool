import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox

@main
struct KitaClipsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipStore!
    private var panel: PanelController!
    private var statusItem: NSStatusItem?
    private let hotKey = HotKey()
    private var subs = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy at a time (login + manual open won't double up).
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        LoginItem.enableOnFirstRun()

        store = ClipStore()
        panel = PanelController(store: store)
        store.start()

        buildStatusItem()
        let p = panel
        hotKey.action = { p?.toggle() }
        hotKey.register(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey))

        store.$paused
            .receive(on: RunLoop.main)
            .sink { [weak self] paused in
                let s = self
                MainActor.assumeIsolated { s?.updateIcon(paused: paused) }
            }
            .store(in: &subs)

        if !UserDefaults.standard.bool(forKey: "welcomeShown") {
            UserDefaults.standard.set(true, forKey: "welcomeShown")
            panel.show()
        }
    }

    /// Opening the app again from Applications or Spotlight shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.show()
        return false
    }

    // MARK: menu bar icon

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(statusClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateIcon(paused: false)
    }

    private func updateIcon(paused: Bool) {
        let name = paused ? "pause.circle" : "doc.on.clipboard"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Kita Clips")
        img?.isTemplate = true
        statusItem?.button?.image = img
    }

    @objc private func statusClicked(_ sender: Any?) {
        let ev = NSApp.currentEvent
        if ev?.type == .rightMouseUp || ev?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            panel.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(item("Open Kita Clips  (⌃⌥V)", #selector(openPanel)))
        menu.addItem(.separator())
        let pause = item(store.paused ? "Resume Saving" : "Pause Saving", #selector(togglePause))
        menu.addItem(pause)
        let login = item("Open at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        let paste = item("Paste Straight Into App", #selector(togglePaste))
        paste.state = store.pasteDirectly ? .on : .off
        menu.addItem(paste)
        menu.addItem(.separator())
        menu.addItem(item("Quit Kita Clips", #selector(quit)))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func openPanel() { panel.show() }
    @objc private func togglePause() { store.setPaused(!store.paused) }
    @objc private func toggleLogin() { LoginItem.isEnabled ? LoginItem.disable() : LoginItem.enable() }
    @objc private func togglePaste() {
        store.pasteDirectly.toggle()
        if store.pasteDirectly && !Paster.trusted { Paster.askForPermission() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
