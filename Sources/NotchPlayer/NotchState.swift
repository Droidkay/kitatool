import SwiftUI
import AppKit
import CoreImage
import EventKit
import IOKit.ps
import CoreAudio

// MARK: - Battery

struct BatteryInfo: Equatable {
    var level: Int
    var charging: Bool

    static func read() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let maxCap = d[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { continue }
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return BatteryInfo(level: cur * 100 / maxCap, charging: charging || onAC)
        }
        return nil
    }
}

// MARK: - Geometry

struct NotchGeometry {
    var notchW: CGFloat = 190
    var notchH: CGFloat = 32
    var hasNotch = false
    var screenFrame: NSRect = .zero

    @MainActor
    init(screen: NSScreen) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchW = screen.frame.width - l.width - r.width
            notchH = screen.safeAreaInsets.top
            hasNotch = true
        } else {
            // External / non-notch display: a virtual notch hanging from the top edge.
            notchW = 160
            let bar = screen.frame.maxY - screen.visibleFrame.maxY
            notchH = max(28, min(bar, 40))
        }
    }

    @MainActor
    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        return NotchGeometry(screen: screen)
    }
}

// MARK: - Small models

enum NotchPage: Int, CaseIterable, Identifiable {
    case music, calendar, timer, shelf
    var id: Int { rawValue }
    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .timer: return "timer"
        case .shelf: return "tray.full"
        }
    }
}

enum NotchPeek: Equatable {
    case none
    case track
    case charging(Int)
    case lowBattery(Int)
    case timerDone
    case event(String, Int)   // title, minutes until
    case volume(Double, Bool) // level 0...1, muted
    case robot(String)        // the companion robot says something
}

struct CalEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
}

func averageColor(of image: NSImage) -> Color {
    guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff) else { return .white }
    let extent = CIVector(x: ci.extent.origin.x, y: ci.extent.origin.y,
                          z: ci.extent.size.width, w: ci.extent.size.height)
    guard let f = CIFilter(name: "CIAreaAverage",
                           parameters: [kCIInputImageKey: ci, kCIInputExtentKey: extent]),
          let out = f.outputImage else { return .white }
    var px = [UInt8](repeating: 0, count: 4)
    CIContext().render(out, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    let ns = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                     blue: CGFloat(px[2]) / 255, alpha: 1)
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ns.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    if s < 0.1 { return .white }
    return Color(hue: Double(h), saturation: Double(max(s, 0.5)), brightness: Double(max(b, 0.85)))
}

// MARK: - State

@MainActor
final class NotchState: ObservableObject {
    @Published var page: NotchPage = .music
    @Published var peek: NotchPeek = .none
    @Published var now = Date()
    @Published var track: Track?
    @Published var artwork: NSImage?
    @Published var accent: Color = .white
    @Published var battery: BatteryInfo?

    @Published var events: [CalEvent] = []
    @Published var calendarAllowed = false
    @Published var shelf: [URL] = []

    @Published var showIdleInfo: Bool {
        didSet { UserDefaults.standard.set(showIdleInfo, forKey: "showIdleInfo") }
    }

    // Timer
    @Published var timerTotal = 0
    @Published var timerRemaining = 0
    @Published var timerRunning = false
    @Published var timerFinished = false
    private var timerEnd = Date()

    private var ticker: Timer?
    private var tickCount = 0
    private var lastTrackID: String?
    private var lastPlaying = false
    private var peekTask: Task<Void, Never>?
    private var notifiedEvents = Set<String>()
    private var lowBatteryShown = false
    private let eventStore = EKEventStore()

    let flankW: CGFloat = 68
    let ear: CGFloat = 9

    @Published var hudEnabled: Bool {
        didSet { UserDefaults.standard.set(hudEnabled, forKey: "hudEnabled") }
    }
    @Published var peeksEnabled: Bool {
        didSet { UserDefaults.standard.set(peeksEnabled, forKey: "peeksEnabled") }
    }
    @Published var robotEnabled: Bool {
        didSet { UserDefaults.standard.set(robotEnabled, forKey: "robotEnabled") }
    }

    // Companion robot
    let robot: RobotBrain
    private var activeSeconds = 0
    private var fullChargeShown = false

    init() {
        let d = UserDefaults.standard
        showIdleInfo = d.object(forKey: "showIdleInfo") as? Bool ?? false
        hudEnabled = d.object(forKey: "hudEnabled") as? Bool ?? true
        peeksEnabled = d.object(forKey: "peeksEnabled") as? Bool ?? true
        robotEnabled = d.object(forKey: "robotEnabled") as? Bool ?? true
        robot = RobotBrain()
    }

    // MARK: layout

    var timerActive: Bool { timerRunning || timerFinished }
    var compactVisible: Bool { timerActive || track != nil || showIdleInfo || robotEnabled }

    // MARK: lifecycle

    func start() {
        battery = BatteryInfo.read()
        lastWasCharging = battery?.charging ?? false
        pollMusic()
        requestCalendar()
        startVolumeWatch()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.robotSay(NotchState.robotGreeting(), seconds: 4)
        }
    }

    // MARK: companion robot

    func robotSay(_ text: String, seconds: Double = 4) {
        guard robotEnabled else { return }
        showPeek(.robot(text), seconds: seconds)
    }

    private func robotTick() {
        let idle = robot.idleSeconds
        if idle < 120 {
            activeSeconds += 1
        } else if idle > 300 {
            activeSeconds = 0
        }
        if activeSeconds >= 3600 {
            activeSeconds = 0
            robotSay("An hour in. Time to stretch 🙆", seconds: 5)
        }
    }

    private var lastWasCharging = false

    private func tick() {
        now = Date()
        tickCount += 1

        if tickCount % 5 == 0 { refreshBattery() }
        if tickCount % 60 == 0 { loadEvents() }
        if tickCount % 15 == 0 { checkUpcomingEvent() }
        pollMusic()
        if robotEnabled { robotTick() }

        if timerRunning {
            timerRemaining = max(0, Int(timerEnd.timeIntervalSinceNow.rounded(.up)))
            if timerRemaining == 0 {
                timerRunning = false
                timerFinished = true
                NSSound(named: "Glass")?.play()
                showPeek(.timerDone, seconds: 6)
                Task {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    self.timerFinished = false
                }
            }
        }
    }

    // MARK: peeks

    func showPeek(_ p: NotchPeek, seconds: Double) {
        if case .volume = p {
            guard hudEnabled else { return }
        } else {
            guard peeksEnabled else { return }
        }
        peek = p
        peekTask?.cancel()
        peekTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            self.peek = .none
        }
    }

    func cancelPeek() {
        peekTask?.cancel()
        peek = .none
    }

    // MARK: battery

    private func refreshBattery() {
        guard let b = BatteryInfo.read() else { return }
        if b.charging && !lastWasCharging { showPeek(.charging(b.level), seconds: 3.5) }
        if !b.charging && b.level <= 20 && !lowBatteryShown {
            lowBatteryShown = true
            showPeek(.lowBattery(b.level), seconds: 4)
        }
        if b.level > 25 { lowBatteryShown = false }
        if b.charging && b.level >= 100 && !fullChargeShown {
            fullChargeShown = true
            robotSay("All charged up! 🔋")
        }
        if b.level < 95 { fullChargeShown = false }
        lastWasCharging = b.charging
        battery = b
    }

    // MARK: music

    func pollMusic() {
        var best: Track?
        for s in MusicSource.allCases where s.isRunning {
            guard let t = MusicBridge.query(s) else { continue }
            if best == nil || (t.playing && best?.playing == false) { best = t }
        }
        guard let t = best else {
            track = nil
            artwork = nil
            accent = .white
            lastTrackID = nil
            lastPlaying = false
            return
        }
        track = t
        if t.id != lastTrackID {
            let firstTrack = lastTrackID == nil
            lastTrackID = t.id
            artwork = nil
            let source = t.source
            let id = t.id
            if t.playing && !firstTrack { showPeek(.track, seconds: 3.5) }
            Task {
                let img = await MusicBridge.artwork(for: source)
                if self.lastTrackID == id {
                    self.artwork = img
                    self.accent = img.map { averageColor(of: $0) } ?? .white
                }
            }
        } else if t.playing && !lastPlaying {
            showPeek(.track, seconds: 2.5)
        }
        lastPlaying = t.playing
    }

    func togglePlay() {
        guard let t = track else { return }
        MusicBridge.command(t.source, "playpause")
        pollMusic()
    }

    func next() {
        guard let t = track else { return }
        MusicBridge.command(t.source, "next track")
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.pollMusic()
        }
    }

    func previous() {
        guard let t = track else { return }
        MusicBridge.command(t.source, "previous track")
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.pollMusic()
        }
    }

    func seek(fraction: Double) {
        guard let t = track, t.duration > 0 else { return }
        let seconds = Int(max(0, min(1, fraction)) * t.duration)
        MusicBridge.command(t.source, "set player position to \(seconds)")
        pollMusic()
    }

    // MARK: calendar

    func requestCalendar() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            calendarAllowed = true
            loadEvents()
            return
        }
        Task {
            let ok = (try? await self.eventStore.requestFullAccessToEvents()) ?? false
            self.calendarAllowed = ok
            if ok { self.loadEvents() }
        }
    }

    func loadEvents() {
        guard calendarAllowed else { return }
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 3, to: start) else { return }
        let pred = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let list = eventStore.events(matching: pred)
            .filter { $0.endDate > start }
            .sorted { $0.startDate < $1.startDate }
        events = list.prefix(8).map { ev in
            CalEvent(
                id: (ev.eventIdentifier ?? ev.title ?? "") + "\(ev.startDate.timeIntervalSince1970)",
                title: ev.title ?? "Event",
                start: ev.startDate, end: ev.endDate, allDay: ev.isAllDay,
                color: Color(cgColor: ev.calendar.cgColor))
        }
    }

    private func checkUpcomingEvent() {
        for ev in events where !ev.allDay && !notifiedEvents.contains(ev.id) {
            let mins = Int(ev.start.timeIntervalSinceNow / 60)
            if mins >= 0 && mins <= 5 {
                notifiedEvents.insert(ev.id)
                showPeek(.event(ev.title, mins), seconds: 5)
                break
            }
        }
    }

    // MARK: shelf

    func addToShelf(_ urls: [URL]) {
        for u in urls where !shelf.contains(u) {
            shelf.insert(u, at: 0)
        }
        if shelf.count > 14 { shelf = Array(shelf.prefix(14)) }
    }

    func removeFromShelf(_ url: URL) {
        shelf.removeAll { $0 == url }
    }

    // MARK: volume HUD

    private var volumeDevice: AudioObjectID = 0
    private var lastVolume: Double = -1
    private var lastMuted = false

    private func startVolumeWatch() {
        attachVolume()
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in self?.attachVolume() }
        }
    }

    private func attachVolume() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        guard err == noErr, dev != 0, dev != volumeDevice else { return }
        volumeDevice = dev

        let read = readVolume()
        lastVolume = read.0
        lastMuted = read.1

        let selectors: [AudioObjectPropertySelector] = [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute]
        for sel in selectors {
            for el: UInt32 in [0, 1] {
                var a = AudioObjectPropertyAddress(
                    mSelector: sel, mScope: kAudioDevicePropertyScopeOutput, mElement: el)
                guard AudioObjectHasProperty(dev, &a) else { continue }
                AudioObjectAddPropertyListenerBlock(dev, &a, DispatchQueue.main) { [weak self] _, _ in
                    Task { @MainActor in self?.volumeChanged() }
                }
            }
        }
    }

    private func readVolume() -> (Double, Bool) {
        var vol: Double = 0
        for el: UInt32 in [0, 1] {
            var a = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput, mElement: el)
            guard AudioObjectHasProperty(volumeDevice, &a) else { continue }
            var v = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(volumeDevice, &a, 0, nil, &size, &v) == noErr {
                vol = Double(v)
                break
            }
        }
        var muted = false
        for el: UInt32 in [0, 1] {
            var a = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput, mElement: el)
            guard AudioObjectHasProperty(volumeDevice, &a) else { continue }
            var m = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(volumeDevice, &a, 0, nil, &size, &m) == noErr {
                muted = m != 0
                break
            }
        }
        return (vol, muted)
    }

    private func volumeChanged() {
        let (v, m) = readVolume()
        if abs(v - lastVolume) < 0.001 && m == lastMuted { return }
        lastVolume = v
        lastMuted = m
        showPeek(.volume(v, m), seconds: 1.8)
    }

    // MARK: pages

    func nextPage(_ delta: Int) {
        let all = NotchPage.allCases
        let i = (page.rawValue + delta + all.count) % all.count
        page = all[i]
    }

    // MARK: timer

    func startTimer(minutes: Int) {
        timerTotal = minutes * 60
        timerRemaining = timerTotal
        timerEnd = Date().addingTimeInterval(Double(timerTotal))
        timerRunning = true
        timerFinished = false
    }

    func toggleTimer() {
        if timerRunning {
            timerRunning = false
        } else if timerRemaining > 0 {
            timerEnd = Date().addingTimeInterval(Double(timerRemaining))
            timerRunning = true
        }
    }

    func resetTimer() {
        timerRunning = false
        timerFinished = false
        timerRemaining = 0
        timerTotal = 0
    }
}
