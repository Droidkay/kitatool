import SwiftUI
import AppKit
import ServiceManagement

@main
struct NotchPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One panel + one ScreenState per display.
@MainActor
final class ScreenController {
    let screen: NSScreen
    let state: ScreenState
    let panel: NotchPanel
    var collapseTask: Task<Void, Never>?

    init(core: NotchState, screen: NSScreen) {
        self.screen = screen
        let st = ScreenState(core: core, screen: screen)
        state = st
        let p = NotchPanel(
            contentRect: NSRect(origin: .zero, size: st.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false
        p.ignoresMouseEvents = true
        p.contentView = NSHostingView(rootView: NotchRoot(s: st))
        panel = p
        position()
        p.orderFrontRegardless()
    }

    func position() {
        let g = state.geometry
        let size = state.panelSize
        let origin = NSPoint(
            x: g.screenFrame.midX - size.width / 2,
            y: g.screenFrame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func isOverIdle() -> Bool {
        hitRect(for: state.idleSize, pad: 4).contains(NSEvent.mouseLocation)
    }

    func close() {
        collapseTask?.cancel()
        panel.orderOut(nil)
    }

    private func hitRect(for size: CGSize, pad: CGFloat) -> NSRect {
        let g = state.geometry
        return NSRect(
            x: g.screenFrame.midX - size.width / 2 - pad,
            y: g.screenFrame.maxY - size.height - pad,
            width: size.width + 2 * pad,
            height: size.height + 2 * pad + 30)   // extends above the screen edge
    }

    func mouseMoved(dragging: Bool) {
        let p = NSEvent.mouseLocation
        if dragging && !state.expanded {
            // Dragging files toward the notch opens the shelf.
            let hasFiles = NSPasteboard(name: .drag).canReadObject(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            if hasFiles && hitRect(for: state.idleSize, pad: 30).contains(p) {
                state.page = .shelf
                setExpanded(true)
            }
            return
        }
        if state.expanded {
            if hitRect(for: state.expandedSize, pad: 14).contains(p) {
                collapseTask?.cancel()
                collapseTask = nil
            } else if collapseTask == nil {
                collapseTask = Task {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    if Task.isCancelled { return }
                    self.setExpanded(false)
                    self.collapseTask = nil
                }
            }
        } else if hitRect(for: state.peek != .none ? state.peekSize : state.idleSize, pad: 2).contains(p) {
            setExpanded(true)
        }
    }

    func setExpanded(_ value: Bool) {
        guard state.expanded != value else { return }
        if value {
            switch state.peek {
            case .notification: state.page = .alerts
            case .checkIn, .robot: state.page = .buddy
            default: break
            }
            state.cancelPeek()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        state.expanded = value
        panel.ignoresMouseEvents = !value
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let core = NotchState()
    private var controllers: [ScreenController] = []
    private var monitors: [Any] = []
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LoginItem.enableOnFirstRun()
        rebuildScreens()
        buildStatusItem()
        installMonitors()
        core.start()
        if CommandLine.arguments.contains("--demo") { runDemo() }
        if CommandLine.arguments.contains("--notes-test") { runNotesTest() }
        if CommandLine.arguments.contains("--clips-demo") {
            core.buddy.checkInMinutes = 0
            let c = core
            let ctrls = { [weak self] in self?.controllers ?? [] }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                c.page = .clips
                for ctl in ctrls() { ctl.setExpanded(true) }
            }
        }
        if CommandLine.arguments.contains("--moves") {
            core.buddy.checkInMinutes = 0
            let r = core.robot
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                r.lastActivity = Date()
                r.showOff()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            let me = self
            Task { @MainActor in me?.rebuildScreens() }
        }
    }

    // MARK: test helpers (used by the build machine)

    private func runDemo() {
        let c = core
        let ctrls = { [weak self] in self?.controllers ?? [] }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            c.buddy.checkIn()
            try? await Task.sleep(nanoseconds: 11_000_000_000)
            c.showPeek(.notification(NotchNote(id: 1, bundle: "com.apple.MobileSMS", appName: "Messages",
                                               title: "Mum", subtitle: "", body: "Have you eaten? Call me when you're free 🙏🏾",
                                               date: Date())), seconds: 6)
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            c.page = .buddy
            for ctl in ctrls() { ctl.setExpanded(true) }
            c.buddy.answer(.stressed)
        }
    }

    private func runNotesTest() {
        let r = NotificationReader()
        print("paths:", NotificationReader.candidatePaths())
        Task { @MainActor in
            for _ in 0..<12 {
                let n = r.poll()
                print("status:", r.status, "db:", r.dbPath ?? "-", "new:", n.map { "\($0.appName): \($0.title) / \($0.body)" })
                fflush(stdout)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func rebuildScreens() {
        for c in controllers { c.close() }
        controllers = NSScreen.screens.map { ScreenController(core: core, screen: $0) }
    }

    // MARK: hover tracking

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            Task { @MainActor in self?.mouseMoved(dragging: dragging) }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] event in
            Task { @MainActor in self?.scrolled(event) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] event in
            Task { @MainActor in self?.scrolled(event) }
            return event
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            Task { @MainActor in self?.mouseMoved(dragging: false) }
            return event
        }) { monitors.append(m) }
    }

    private func mouseMoved(dragging: Bool) {
        if core.robotEnabled { core.robot.cursorMoved(NSEvent.mouseLocation) }
        for c in controllers { c.mouseMoved(dragging: dragging) }
    }

    // MARK: swipe gestures

    private var swipeAccum: CGFloat = 0
    private var swipeFired = false

    /// Horizontal two-finger swipe: switches pages when open, skips tracks when hovering the closed notch.
    private func scrolled(_ event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin {
            swipeAccum = 0
            swipeFired = false
        }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        swipeAccum += event.scrollingDeltaX
        if event.phase == .ended || event.phase == .cancelled {
            swipeAccum = 0
            swipeFired = false
            return
        }
        guard !swipeFired, abs(swipeAccum) > 40 else { return }
        let direction = swipeAccum < 0 ? 1 : -1
        if controllers.contains(where: { $0.state.expanded }) {
            swipeFired = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                core.nextPage(direction)
            }
        } else if controllers.contains(where: { $0.isOverIdle() }), core.track != nil {
            swipeFired = true
            if direction > 0 { core.next() } else { core.previous() }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    // MARK: menu bar item (Quit / Launch at login)

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Notch Player")
        img?.isTemplate = true
        item.button?.image = img

        let menu = NSMenu()
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        let toggles: [(String, Int, Bool)] = [
            ("Show Clock When Idle", 1, core.showIdleInfo),
            ("Volume HUD", 2, core.hudEnabled),
            ("Banners (songs, charging, events)", 3, core.peeksEnabled),
            ("Companion Robot", 4, core.robotEnabled),
            ("App Notifications in the Notch", 5, core.notesEnabled),
            ("Bible Verses from the Robot", 6, core.buddy.verses),
            ("Show \"Copied\" in the Notch (Kita Clips)", 7, core.clipBanners)
        ]
        for (title, tag, on) in toggles {
            let item = NSMenuItem(title: title, action: #selector(toggleSetting(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = on ? .on : .off
            menu.addItem(item)
        }
        let checkMenu = NSMenu()
        for (title, mins) in [("Every 30 minutes", 30), ("Every hour", 60), ("Every 2 hours", 120), ("Off", 0)] {
            let i = NSMenuItem(title: title, action: #selector(setCheckIn(_:)), keyEquivalent: "")
            i.target = self
            i.tag = mins
            i.state = core.buddy.checkInMinutes == mins ? .on : .off
            checkMenu.addItem(i)
        }
        let checkItem = NSMenuItem(title: "Robot Check-ins", action: nil, keyEquivalent: "")
        checkItem.submenu = checkMenu
        menu.addItem(checkItem)
        let rename = NSMenuItem(title: "Change My Name…", action: #selector(changeName), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)
        let notifAccess = NSMenuItem(title: "Allow Notifications (Full Disk Access)…", action: #selector(openNotifAccess), keyEquivalent: "")
        notifAccess.target = self
        menu.addItem(notifAccess)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Notch Player", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        if LoginItem.isEnabled { LoginItem.disable() } else { LoginItem.enable() }
        sender.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func toggleSetting(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1: core.showIdleInfo.toggle(); sender.state = core.showIdleInfo ? .on : .off
        case 2: core.hudEnabled.toggle(); sender.state = core.hudEnabled ? .on : .off
        case 4: core.robotEnabled.toggle(); sender.state = core.robotEnabled ? .on : .off
        case 5: core.notesEnabled.toggle(); sender.state = core.notesEnabled ? .on : .off
        case 6: core.buddy.verses.toggle(); sender.state = core.buddy.verses ? .on : .off
        case 7: core.clipBanners.toggle(); sender.state = core.clipBanners ? .on : .off
        default: core.peeksEnabled.toggle(); sender.state = core.peeksEnabled ? .on : .off
        }
    }

    @objc private func setCheckIn(_ sender: NSMenuItem) {
        core.buddy.checkInMinutes = sender.tag
        sender.menu?.items.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
    }

    @objc private func openNotifAccess() {
        NotificationReader.openFullDiskAccessSettings()
    }

    @objc private func changeName() {
        let alert = NSAlert()
        alert.messageText = "What should the robot call you?"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = core.buddy.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let n = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !n.isEmpty { core.buddy.name = n }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
