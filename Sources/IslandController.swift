import AppKit
import SwiftUI

/// A borderless panel at the top of a screen, above the menu bar, on every Space.
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
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// One island on one screen: places the panel, watches the mouse, opens and closes it.
final class IslandController {
    static let panelSize = NSSize(width: 540, height: 280)
    let hub: Hub
    let island: Island
    let panel: IslandPanel
    private(set) var screenID: CGDirectDisplayID = 0
    private var timer: Timer?
    private var closeWork: DispatchWorkItem?

    init(hub: Hub, screen: NSScreen) {
        self.hub = hub
        island = Island(hub: hub)
        panel = IslandPanel(rect: NSRect(origin: .zero, size: IslandController.panelSize))
        let host = NSHostingView(rootView: IslandView(hub: hub, island: island))
        host.frame = NSRect(origin: .zero, size: IslandController.panelSize)
        panel.contentView = host
        place(on: screen)
    }

    static func displayID(_ s: NSScreen) -> CGDirectDisplayID {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    func show() {
        if !hub.hidden { panel.orderFrontRegardless() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.trackMouse() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func close() {
        timer?.invalidate()
        panel.orderOut(nil)
    }

    func applyHidden() {
        if hub.hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    func place(on screen: NSScreen) {
        screenID = IslandController.displayID(screen)
        let f = screen.frame
        if screen.safeAreaInsets.top > 0 {
            var notchW: CGFloat = 190
            if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
                notchW = f.width - l.width - r.width
            }
            island.notchSize = CGSize(width: notchW, height: screen.safeAreaInsets.top)
            island.hasNotch = true
        } else {
            island.notchSize = CGSize(width: 0, height: max(24, f.maxY - screen.visibleFrame.maxY))
            island.hasNotch = false
        }
        let size = IslandController.panelSize
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    /// Where the island is, in screen coordinates.
    private func hotRect() -> NSRect {
        let s = island.shapeSize
        let pf = panel.frame
        let pad: CGFloat = island.expanded ? 14 : 6
        let top = island.floating ? Island.floatTop : 0
        return NSRect(x: pf.midX - s.width / 2 - pad, y: pf.maxY - top - s.height - pad,
                      width: s.width + pad * 2, height: s.height + top + pad + 2)
    }

    private func trackMouse() {
        if hub.hidden { return }
        let p = NSEvent.mouseLocation
        let inside = hotRect().contains(p)
        panel.ignoresMouseEvents = !inside
        if inside {
            closeWork?.cancel()
            closeWork = nil
            if !island.expanded && !island.hoverPending {
                island.hoverPending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self = self else { return }
                    self.island.hoverPending = false
                    if self.hotRect().contains(NSEvent.mouseLocation) { self.island.setExpanded(true) }
                }
            }
        } else if island.expanded && closeWork == nil && !hub.pinned {
            let w = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.closeWork = nil
                if !self.hotRect().contains(NSEvent.mouseLocation) && !self.hub.pinned { self.island.setExpanded(false) }
            }
            closeWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
        }
    }
}
