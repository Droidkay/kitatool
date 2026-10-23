import AppKit
import ServiceManagement

// Notch Player: turns the MacBook notch into a little Dynamic Island.
// Menu-bar-only app (no Dock icon). Hover the notch to open it.

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = IslandState()
    var island: IslandController!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        island = IslandController(state: state)
        island.show()
        setupMenu()
        state.nowPlaying.start()
        state.battery.start()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.state.show(.welcome, seconds: 4) }
        }
    }

    @objc func screensChanged() {
        island.reposition()
    }

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Notch Player")
            b.image?.isTemplate = true
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let m = NSMenu()
        m.addItem(withTitle: "Notch Player", action: nil, keyEquivalent: "").isEnabled = false
        m.addItem(.separator())
        let timer = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for mins in [5, 10, 15, 25, 45, 60] {
            let i = NSMenuItem(title: "\(mins) minutes", action: #selector(startTimer(_:)), keyEquivalent: "")
            i.tag = mins
            i.target = self
            sub.addItem(i)
        }
        sub.addItem(.separator())
        let stop = NSMenuItem(title: "Stop timer", action: #selector(stopTimer), keyEquivalent: "")
        stop.target = self
        sub.addItem(stop)
        timer.submenu = sub
        m.addItem(timer)

        let hide = NSMenuItem(title: state.hidden ? "Show the island" : "Hide the island", action: #selector(toggleHidden), keyEquivalent: "h")
        hide.target = self
        m.addItem(hide)

        let charge = NSMenuItem(title: "Show charging", action: #selector(toggleCharging), keyEquivalent: "")
        charge.target = self
        charge.state = state.showCharging ? .on : .off
        m.addItem(charge)

        let login = NSMenuItem(title: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)

        m.addItem(.separator())
        let about = NSMenuItem(title: "About Notch Player", action: #selector(aboutApp), keyEquivalent: "")
        about.target = self
        m.addItem(about)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.addItem(quit)
        statusItem.menu = m
    }

    @objc func startTimer(_ sender: NSMenuItem) {
        state.timer.start(minutes: sender.tag)
        state.show(.timerStarted, seconds: 2.5)
    }

    @objc func stopTimer() {
        state.timer.reset()
    }

    @objc func toggleHidden() {
        state.hidden.toggle()
        island.applyHidden()
        rebuildMenu()
    }

    @objc func toggleCharging() {
        state.showCharging.toggle()
        UserDefaults.standard.set(state.showCharging, forKey: "showCharging")
        rebuildMenu()
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change this"
            a.informativeText = "Move Notch Player to your Applications folder first, then try again.\n\n\(error.localizedDescription)"
            a.runModal()
        }
        rebuildMenu()
    }

    @objc func aboutApp() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Notch Player 1.0"
        a.informativeText = "Turns your MacBook notch into a mini music player and timer.\n\nHover the notch to open it. Works with Spotify and Apple Music.\n\nby DroidKay"
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
