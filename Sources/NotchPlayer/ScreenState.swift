import SwiftUI
import AppKit
import Combine

/// One of these exists per display. It owns the per-screen bits (geometry, expanded)
/// and forwards everything else to the single shared NotchState.
@MainActor @dynamicMemberLookup
final class ScreenState: ObservableObject {
    let core: NotchState
    @Published var expanded = false
    @Published var geometry: NotchGeometry
    private var sub: AnyCancellable?

    init(core: NotchState, screen: NSScreen) {
        self.core = core
        self.geometry = NotchGeometry(screen: screen)
        sub = core.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    subscript<T>(dynamicMember kp: KeyPath<NotchState, T>) -> T {
        core[keyPath: kp]
    }

    subscript<T>(dynamicMember kp: ReferenceWritableKeyPath<NotchState, T>) -> T {
        get { core[keyPath: kp] }
        set { core[keyPath: kp] = newValue }
    }

    // MARK: layout

    var topRadius: CGFloat {
        (core.compactVisible || expanded || core.peek != .none) ? core.ear : 0
    }

    var idleSize: CGSize {
        core.compactVisible
            ? CGSize(width: geometry.notchW + 2 * core.flankW + 2 * core.ear, height: geometry.notchH)
            : CGSize(width: geometry.notchW, height: geometry.notchH)
    }
    var peekSize: CGSize {
        if core.peek.isImportant {
            return CGSize(width: max(geometry.notchW + 2 * core.flankW + 2 * core.ear + 150, 440),
                          height: geometry.notchH + 62)
        }
        return CGSize(width: max(geometry.notchW + 2 * core.flankW + 2 * core.ear + 40, 340),
                      height: geometry.notchH + 42)
    }
    var expandedSize: CGSize {
        CGSize(width: 540, height: geometry.notchH + 150)
    }
    var panelSize: CGSize {
        CGSize(width: 590, height: geometry.notchH + 190)
    }
    var islandSize: CGSize {
        if expanded { return expandedSize }
        if core.peek != .none { return peekSize }
        return idleSize
    }

    /// Real notch is always black; a virtual one on an external display only shows when active.
    var visible: Bool {
        geometry.hasNotch || expanded || core.peek != .none || core.compactVisible
    }

    // MARK: forwarded actions

    func togglePlay() { core.togglePlay() }
    func next() { core.next() }
    func previous() { core.previous() }
    func seek(fraction: Double) { core.seek(fraction: fraction) }
    func requestCalendar() { core.requestCalendar() }
    func addToShelf(_ urls: [URL]) { core.addToShelf(urls) }
    func removeFromShelf(_ url: URL) { core.removeFromShelf(url) }
    func startTimer(minutes: Int) { core.startTimer(minutes: minutes) }
    func toggleTimer() { core.toggleTimer() }
    func resetTimer() { core.resetTimer() }
    func cancelPeek() { core.cancelPeek() }
}
