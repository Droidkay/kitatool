import Foundation
import IOKit.ps

/// Tells the island when the charger is plugged in or out.
final class Battery: ObservableObject {
    @Published private(set) var percent = 100
    @Published private(set) var plugged = false
    /// False on desktop Macs (iMac, Mac mini, Mac Studio).
    @Published private(set) var hasBattery = false
    var onChange: ((Int, Bool) -> Void)?
    private var source: CFRunLoopSource?
    private var started = false

    func start() {
        read(notify: false)
        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let s = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx = ctx else { return }
            let me = Unmanaged<Battery>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.read(notify: true) }
        }, ctx)?.takeRetainedValue() {
            source = s
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
        }
        started = true
    }

    private func read(notify: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            let isPlugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let changed = isPlugged != plugged
            hasBattery = true
            percent = pct
            plugged = isPlugged
            if notify && changed { onChange?(pct, isPlugged) }
            return
        }
    }
}
