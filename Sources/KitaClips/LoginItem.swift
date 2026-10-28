import Foundation
import ServiceManagement

/// Starts Kita Clips when you log in (after a restart).
/// Uses macOS's Login Items first; if that doesn't take (common for apps
/// without an Apple Developer signature), falls back to a LaunchAgent.
enum LoginItem {
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.droidkay.kitaclips.login.plist")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
            || FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func enable() {
        try? SMAppService.mainApp.register()
        if SMAppService.mainApp.status != .enabled {
            writeAgent()
        }
    }

    static func disable() {
        try? SMAppService.mainApp.unregister()
        try? FileManager.default.removeItem(at: agentURL)
    }

    /// Turns it on the first time the app runs. If you switch it off later, it stays off.
    static func enableOnFirstRun() {
        let key = "loginDefaultApplied"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        enable()
    }

    private static func writeAgent() {
        let plist: [String: Any] = [
            "Label": "com.droidkay.kitaclips.login",
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true
        ]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? FileManager.default.createDirectory(
            at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: agentURL)
    }
}
