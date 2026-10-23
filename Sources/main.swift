import AppKit
import ServiceManagement

// Notch Player: turns the top of your screens into a little Dynamic Island.
// On the MacBook screen it grows out of the camera notch; on other monitors it floats as a glass pill.
// Menu-bar-only app (no Dock icon). Hover the island to open it.

final class AppDelegate: NSObject, NSApplicationDelegate {
    let hub = Hub()
    var islands: [IslandController] = []
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        hub.onExpandAll = { [weak self] on in self?.islands.forEach { $0.island.setExpanded(on) } }
        buildIslands()
        setupMenu()
        hub.nowPlaying.start()
        hub.battery.start()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !UserDefaults.standard.bool(forKey: "welcomed2") {
            UserDefaults.standard.set(true, forKey: "welcomed2")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.hub.show(.welcome, seconds: 4) }
        }
    }

    /// Screens that should have an island, based on the setting.
    func wantedScreens() -> [NSScreen] {
        let all = NSScreen.screens
        switch hub.screens {
        case .all:
            return all
        case .builtIn:
            if let s = all.first(where: { $0.safeAreaInsets.top > 0 || CGDisplayIsBuiltin(IslandController.displayID($0)) != 0 }) { return [s] }
            return [NSScreen.main ?? all[0]]
        case .main:
            // the screen with the menu bar
            return [all.first ?? NSScreen.main!]
        }
    }

    func buildIslands() {
        islands.forEach { $0.close() }
        islands = wantedScreens().map { IslandController(hub: hub, screen: $0) }
        islands.forEach { $0.show() }
    }

    @objc func screensChanged() {
        // screens plugged in, unplugged, rearranged or resized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.buildIslands() }
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
        m.addItem(.separator())

        let look = NSMenuItem(title: "Look", action: nil, keyEquivalent: "")
        let lookMenu = NSMenu()
        for (i, g) in GlassStyle.allCases.enumerated() {
            var title = g.title
            if g == .liquid && !GlassStyle.liquidAvailable { title += " (needs macOS 26)" }
            let it = NSMenuItem(title: title, action: #selector(pickGlass(_:)), keyEquivalent: "")
            it.tag = i
            it.target = self
            it.state = hub.glass == g ? .on : .off
            lookMenu.addItem(it)
        }
        look.submenu = lookMenu
        m.addItem(look)

        let where_ = NSMenuItem(title: "Show on", action: nil, keyEquivalent: "")
        let whereMenu = NSMenu()
        for (i, s) in ScreenChoice.allCases.enumerated() {
            let it = NSMenuItem(title: s.title, action: #selector(pickScreens(_:)), keyEquivalent: "")
            it.tag = i
            it.target = self
            it.state = hub.screens == s ? .on : .off
            whereMenu.addItem(it)
        }
        where_.submenu = whereMenu
        m.addItem(where_)

        let clock = NSMenuItem(title: "Show clock and battery", action: #selector(toggleClock), keyEquivalent: "")
        clock.target = self
        clock.state = hub.showClock ? .on : .off
        m.addItem(clock)

        let charge = NSMenuItem(title: "Show charging", action: #selector(toggleCharging), keyEquivalent: "")
        charge.target = self
        charge.state = hub.showCharging ? .on : .off
        m.addItem(charge)

        let hide = NSMenuItem(title: hub.hidden ? "Show the island" : "Hide the island", action: #selector(toggleHidden), keyEquivalent: "h")
        hide.target = self
        m.addItem(hide)

        let login = NSMenuItem(title: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)

        m.addItem(.separator())
        let about = NSMenuItem(title: "About Notch Player", action: #selector(aboutApp), keyEquivalent: "")
        about.target = self
        m.addItem(about)
        m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = m
    }

    @objc func startTimer(_ sender: NSMenuItem) {
        hub.timer.start(minutes: sender.tag)
        hub.show(.timerStarted, seconds: 2.5)
    }

    @objc func stopTimer() {
        hub.timer.reset()
    }

    @objc func pickGlass(_ sender: NSMenuItem) {
        hub.setGlass(GlassStyle.allCases[sender.tag])
        rebuildMenu()
    }

    @objc func pickScreens(_ sender: NSMenuItem) {
        hub.screens = ScreenChoice.allCases[sender.tag]
        UserDefaults.standard.set(hub.screens.rawValue, forKey: "screens")
        buildIslands()
        rebuildMenu()
    }

    @objc func toggleClock() {
        hub.showClock.toggle()
        UserDefaults.standard.set(hub.showClock, forKey: "showClock")
        rebuildMenu()
    }

    @objc func toggleHidden() {
        hub.hidden.toggle()
        islands.forEach { $0.applyHidden() }
        rebuildMenu()
    }

    @objc func toggleCharging() {
        hub.showCharging.toggle()
        UserDefaults.standard.set(hub.showCharging, forKey: "showCharging")
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
        a.messageText = "Notch Player 1.1"
        a.informativeText = "A Dynamic Island for your Mac: music and a timer at the top of every screen.\n\nHover the island to open it. Works with Spotify and Apple Music.\n\nby DroidKay"
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
