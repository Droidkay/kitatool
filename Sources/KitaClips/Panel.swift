import AppKit
import SwiftUI
import Carbon.HIToolbox

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The floating Kita Clips window. It opens near the top of the screen your mouse is on,
/// so it always works even when the menu bar icon is hidden behind the notch.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let store: ClipStore
    private var panel: KeyPanel!
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private let size = NSSize(width: 640, height: 560)
    private var previousApp: NSRunningApplication?
    private var shownAt = Date.distantPast

    var isShown: Bool { panel.isVisible }

    init(store: ClipStore) {
        self.store = store
        super.init()
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        let me = self
        let root = ClipsView(store: store,
                             activate: { clip, alt in me.activate(clip, alt: alt) },
                             transform: { clip, t in me.transform(clip, t) },
                             close: { me.hide() })
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        panel = p
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        store.query = ""
        store.filter = .all
        store.resetSelection()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 40)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        shownAt = Date()
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        store.focusToken += 1
        installMonitors()
    }

    func hide(returnFocus: Bool = true) {
        guard panel.isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        if returnFocus, NSApp.isActive { previousApp?.activate() }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Ignore the brief focus shuffle right after opening.
        guard Date().timeIntervalSince(shownAt) > 0.4 else {
            let me = self
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                if me.panel.isVisible && !me.panel.isKeyWindow && !NSApp.isActive { me.hide(returnFocus: false) }
            }
            return
        }
        hide(returnFocus: false)
    }

    // MARK: actions

    /// Click or Return: copy, and paste into the app you were in if that's turned on.
    /// alt (Shift+Return / Option-click) does the opposite of the paste setting.
    func activate(_ clip: Clip, alt: Bool = false) {
        store.copyToPasteboard(clip)
        finish(paste: store.pasteDirectly != alt)
    }

    func transform(_ clip: Clip, _ t: TextTransform) {
        guard let text = clip.text else { return }
        store.copyToPasteboard(clip, overrideText: t.apply(text))
        finish(paste: store.pasteDirectly)
    }

    private func finish(paste: Bool) {
        hide(returnFocus: true)
        guard paste else { return }
        if Paster.trusted {
            Task {
                try? await Task.sleep(nanoseconds: 180_000_000)
                Paster.pasteNow()
            }
        } else {
            Paster.askForPermission()
        }
    }

    // MARK: keyboard

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let me = self
            Task { @MainActor in me?.hide(returnFocus: false) }
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        let cmd = e.modifierFlags.contains(.command)
        let shift = e.modifierFlags.contains(.shift)
        switch Int(e.keyCode) {
        case kVK_Escape:
            if !store.query.isEmpty { store.query = "" } else { hide() }
            return true
        case kVK_DownArrow:
            store.moveSelection(1); return true
        case kVK_UpArrow:
            store.moveSelection(-1); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let c = store.selected { activate(c, alt: shift) }
            return true
        case kVK_Tab:
            let all = ClipFilter.allCases
            let i = all.firstIndex(of: store.filter) ?? 0
            store.filter = all[(i + (shift ? all.count - 1 : 1)) % all.count]
            return true
        default:
            break
        }
        guard cmd else { return false }
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if let n = Int(ch), n >= 1, n <= 9 {
            let list = store.visible
            if n <= list.count { activate(list[n - 1], alt: shift) }
            return true
        }
        switch ch {
        case "p":
            if let c = store.selected { store.togglePin(c) }
            return true
        case "\u{7f}", "\u{8}":
            if let c = store.selected { store.delete(c) }
            return true
        default:
            if e.keyCode == UInt16(kVK_Delete) {
                if let c = store.selected { store.delete(c) }
                return true
            }
            return false
        }
    }
}
