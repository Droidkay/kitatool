import AppKit
import SwiftUI

/// A borderless panel that sits over the notch, above the menu bar, on every Space.
final class IslandPanel: NSPanel {
    init(rect: NSRect) {
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Places the panel, watches the mouse, and opens/closes the island.
final class IslandController {
    static let panelSize = NSSize(width: 520, height: 260)
    let state: IslandState
    let panel: IslandPanel
    private var timer: Timer?
    private var closeWork: DispatchWorkItem?

    init(state: IslandState) {
        self.state = state
        panel = IslandPanel(rect: NSRect(origin: .zero, size: IslandController.panelSize))
        let host = NSHostingView(rootView: IslandView(state: state))
        host.frame = NSRect(origin: .zero, size: IslandController.panelSize)
        panel.contentView = host
        reposition()
    }

    func show() {
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.trackMouse() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func applyHidden() {
        if state.hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// The built-in screen (the one with a notch) if there is one, otherwise the main screen.
    static func notchScreen() -> NSScreen? {
        if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) { return s }
        return NSScreen.main ?? NSScreen.screens.first
    }

    func reposition() {
        guard let screen = IslandController.notchScreen() else { return }
        let f = screen.frame
        var notchW: CGFloat = 190, notchH: CGFloat = 32
        if screen.safeAreaInsets.top > 0 {
            notchH = screen.safeAreaInsets.top
            if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
                notchW = f.width - l.width - r.width
            }
        } else {
            notchH = max(24, f.maxY - screen.visibleFrame.maxY)
        }
        state.notchSize = CGSize(width: notchW, height: notchH)
        state.hasNotch = screen.safeAreaInsets.top > 0
        let size = IslandController.panelSize
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    /// Where the visible black shape is, in screen coordinates.
    private func hotRect() -> NSRect {
        let s = state.shapeSize
        let pf = panel.frame
        let pad: CGFloat = state.expanded ? 14 : 6
        return NSRect(x: pf.midX - s.width / 2 - pad, y: pf.maxY - s.height - pad, width: s.width + pad * 2, height: s.height + pad + 2)
    }

    private func trackMouse() {
        if state.hidden { return }
        let p = NSEvent.mouseLocation
        let inside = hotRect().contains(p)
        panel.ignoresMouseEvents = !inside
        if inside {
            closeWork?.cancel()
            closeWork = nil
            if !state.expanded && !state.hoverPending {
                state.hoverPending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self = self else { return }
                    self.state.hoverPending = false
                    if self.hotRect().contains(NSEvent.mouseLocation) { self.state.setExpanded(true) }
                }
            }
        } else if state.expanded && closeWork == nil && !state.pinned {
            let w = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.closeWork = nil
                if !self.hotRect().contains(NSEvent.mouseLocation) { self.state.setExpanded(false) }
            }
            closeWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
        }
    }
}
