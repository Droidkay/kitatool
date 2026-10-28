import SwiftUI
import AppKit

/// A line in the buddy chat.
struct BuddyLine: Identifiable, Equatable {
    let id = UUID()
    let fromBuddy: Bool
    let text: String
}

enum BuddyMood: String, CaseIterable {
    case great, okay, tired, stressed

    var emoji: String {
        switch self {
        case .great: return "😊"
        case .okay: return "😐"
        case .tired: return "😩"
        case .stressed: return "😣"
        }
    }

    var title: String {
        switch self {
        case .great: return "Great"
        case .okay: return "Okay"
        case .tired: return "Tired"
        case .stressed: return "Stressed"
        }
    }
}

/// The brain behind the notch robot: hourly check-ins, break and water tracking,
/// focus sessions, breathing, encouragement, and a daily summary.
@MainActor
final class Companion: ObservableObject {
    unowned let core: NotchState

    @Published var lines: [BuddyLine] = []
    @Published var asking = false
    @Published var breathingUntil: Date?
    @Published var name: String { didSet { d.set(name, forKey: "buddyName") } }
    @Published var checkInMinutes: Int { didSet { d.set(checkInMinutes, forKey: "checkInMinutes"); sinceCheckIn = 0 } }
    @Published var verses: Bool { didSet { d.set(verses, forKey: "buddyVerses") } }

    // Today's numbers
    @Published private(set) var activeToday = 0
    @Published private(set) var breaksToday = 0
    @Published private(set) var waterToday = 0
    @Published private(set) var focusToday = 0
    @Published private(set) var sinceBreak = 0

    private let d = UserDefaults.standard
    private var dayKey = ""
    private var sinceCheckIn = 0
    private var lastWater = Date()
    private var summaryShown = false
    private var greetedToday = false
    private var timerPurpose: TimerPurpose = .none
    private var tickCount = 0

    enum TimerPurpose { case none, focus, rest }

    init(core: NotchState) {
        self.core = core
        name = UserDefaults.standard.string(forKey: "buddyName") ?? Companion.defaultName()
        checkInMinutes = UserDefaults.standard.object(forKey: "checkInMinutes") as? Int ?? 60
        verses = UserDefaults.standard.object(forKey: "buddyVerses") as? Bool ?? true
        loadDay()
    }

    static func defaultName() -> String {
        let full = NSFullUserName()
        if full.lowercased().contains("droid") || full.isEmpty { return "Kelvin" }
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    // MARK: every second

    func tick(idle: TimeInterval) {
        tickCount += 1
        let key = Companion.todayKey()
        if key != dayKey { newDay(key) }

        if idle < 60 {
            activeToday += 1
            sinceBreak += 1
            sinceCheckIn += 1
            if !greetedToday && idle < 5 && Calendar.current.component(.hour, from: Date()) >= 5 {
                greetedToday = true
                morningHello()
            }
        } else if idle >= 300 && sinceBreak > 0 {
            if sinceBreak >= 900 { breaksToday += 1 }   // a real break: away 5+ min after 15+ min of work
            sinceBreak = 0
        }

        if checkInMinutes > 0, sinceCheckIn >= checkInMinutes * 60, idle < 30, timerPurpose != .focus {
            checkIn()
        }

        let hour = Calendar.current.component(.hour, from: Date())
        if !summaryShown, hour >= 21, activeToday > 3600, idle < 30, tickCount > 120 {
            summaryShown = true
            say("That's a wrap 🌙 You were on the Mac \(Companion.hm(activeToday)) today, with \(breaksToday) break\(breaksToday == 1 ? "" : "s") and \(waterToday) glass\(waterToday == 1 ? "" : "es") of water. Rest well, \(name).", seconds: 8)
        }

        if tickCount % 30 == 0 { saveDay() }
        if let until = breathingUntil, until < Date() {
            breathingUntil = nil
            add("Well done. Feel a little lighter? 🌿", buddy: true)
            core.robot.react(.love, seconds: 2)
        }
    }

    // MARK: check-ins

    func checkIn() {
        sinceCheckIn = 0
        asking = true
        let text = checkInText()
        add(text, buddy: true)
        core.showPeek(.checkIn(text), seconds: 10)
        core.robot.react(.surprised, seconds: 1.2)
        NSSound(named: "Pop")?.play()
    }

    private func checkInText() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        var parts: [String] = []
        if hour >= 0 && hour < 5 {
            parts.append("It's \(Companion.clock()) \(name) 🌙 still up?")
        } else {
            parts.append(["Hey \(name) 👋", "Checking in, \(name) 🤖", "Hi \(name)!"].randomElement()!)
        }
        if sinceBreak >= 90 * 60 {
            parts.append("You've been going \(Companion.hm(sinceBreak)) without a break.")
        } else if let t = core.track, t.playing {
            parts.append("Enjoying \(t.artist.isEmpty ? t.title : t.artist)?")
        } else if let ev = core.events.first(where: { !$0.allDay && $0.start > Date() && $0.start.timeIntervalSinceNow < 3600 }) {
            parts.append("\(ev.title) is in \(Int(ev.start.timeIntervalSinceNow / 60)) min.")
        }
        if Date().timeIntervalSince(lastWater) > 2 * 3600 { parts.append("💧 Water break soon?") }
        parts.append("How are you doing?")
        return parts.joined(separator: " ")
    }

    func answer(_ mood: BuddyMood) {
        asking = false
        add("\(mood.emoji) \(mood.title)", buddy: false)
        logMood(mood)
        switch mood {
        case .great:
            core.robot.react(.love, seconds: 2.5)
            add(["Love that! Keep it going 🚀", "Yes! That's the energy 🔥", "Great to hear. I'm proud of you 💙"].randomElement()!, buddy: true)
        case .okay:
            core.robot.react(.happy, seconds: 2)
            add("Steady wins the race. Want a 25-minute focus session?", buddy: true)
        case .tired:
            core.robot.react(.tired, seconds: 2)
            add("Let's take 5. Stand up, stretch, drink some water. I'll time it ☕", buddy: true)
            takeBreak()
        case .stressed:
            core.robot.react(.focused, seconds: 2)
            add("Let's breathe together for a minute. In for 4, hold 4, out for 4.", buddy: true)
            if verses, let v = Companion.verses.randomElement() { add(v, buddy: true) }
            breathe()
        }
    }

    // MARK: actions

    func drinkWater() {
        waterToday += 1
        lastWater = Date()
        core.robot.react(.happy, seconds: 1.5)
        add("💧 Glass \(waterToday) today. Nice!", buddy: true)
        saveDay()
    }

    func takeBreak(minutes: Int = 5) {
        timerPurpose = .rest
        breaksToday += 1
        sinceBreak = 0
        core.startTimer(minutes: minutes)
        saveDay()
    }

    func startFocus(minutes: Int = 25) {
        timerPurpose = .focus
        core.startTimer(minutes: minutes)
        add("Focus mode for \(minutes) min 🎯 I'll stay quiet till then.", buddy: true)
    }

    func breathe() {
        breathingUntil = Date().addingTimeInterval(60)
        core.page = .buddy
    }

    /// Called when the notch timer ends.
    func timerFinished() {
        switch timerPurpose {
        case .focus:
            focusToday += 1
            say("Focus session done! 🎉 That's \(focusToday) today. Take a short break?", seconds: 6)
        case .rest:
            sinceBreak = 0
            say("Break's over. Welcome back, \(name) 💪", seconds: 5)
        case .none:
            break
        }
        timerPurpose = .none
        saveDay()
    }

    /// Tapping the robot.
    func poke() {
        core.robot.react([.love, .happy, .surprised, .celebrate].randomElement()!, seconds: 1.6)
        var pool = Companion.tips + Companion.jokes
        if verses { pool += Companion.verses }
        if let s = pool.randomElement() { add(s, buddy: true) }
    }

    func statusLine() -> String {
        "Today: \(Companion.hm(activeToday)) active · \(breaksToday) breaks · \(waterToday) 💧 · \(focusToday) 🎯"
    }

    // MARK: helpers

    func say(_ text: String, seconds: Double = 5) {
        add(text, buddy: true)
        core.robotSay(text, seconds: seconds)
    }

    private func add(_ text: String, buddy: Bool) {
        lines.append(BuddyLine(fromBuddy: buddy, text: text))
        if lines.count > 12 { lines.removeFirst(lines.count - 12) }
    }

    private func morningHello() {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let todays = core.events.filter { Calendar.current.isDateInToday($0.start) }.count
        var text = "\(part), \(name)! \(hour < 12 ? "☀️" : "👋")"
        if todays > 0 { text += " You have \(todays) event\(todays == 1 ? "" : "s") today." }
        text += " Let's have a good one."
        say(text, seconds: 6)
    }

    private func logMood(_ m: BuddyMood) {
        var log = d.dictionary(forKey: "moodLog") as? [String: String] ?? [:]
        log[ISO8601DateFormatter().string(from: Date())] = m.rawValue
        if log.count > 500 { log = Dictionary(uniqueKeysWithValues: log.sorted { $0.key > $1.key }.prefix(500).map { ($0.key, $0.value) }) }
        d.set(log, forKey: "moodLog")
    }

    private func newDay(_ key: String) {
        let first = dayKey.isEmpty
        dayKey = key
        if first, d.string(forKey: "buddyDay") == key { return }   // same day as saved stats
        activeToday = 0; breaksToday = 0; waterToday = 0; focusToday = 0
        summaryShown = false
        greetedToday = false
        saveDay()
    }

    private func loadDay() {
        let key = Companion.todayKey()
        guard d.string(forKey: "buddyDay") == key else { dayKey = ""; return }
        dayKey = key
        activeToday = d.integer(forKey: "buddyActive")
        breaksToday = d.integer(forKey: "buddyBreaks")
        waterToday = d.integer(forKey: "buddyWater")
        focusToday = d.integer(forKey: "buddyFocus")
        summaryShown = d.bool(forKey: "buddySummary")
    }

    private func saveDay() {
        d.set(dayKey, forKey: "buddyDay")
        d.set(activeToday, forKey: "buddyActive")
        d.set(breaksToday, forKey: "buddyBreaks")
        d.set(waterToday, forKey: "buddyWater")
        d.set(focusToday, forKey: "buddyFocus")
        d.set(summaryShown, forKey: "buddySummary")
    }

    static func todayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func hm(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func clock() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date())
    }

    // MARK: things to say

    static let tips = [
        "Tip: look at something 20 feet away for 20 seconds. Your eyes will thank you 👀",
        "Roll your shoulders back three times. Feels better, right?",
        "A short walk beats another cup of coffee ☕🚶",
        "Small progress is still progress 🌱",
        "Done is better than perfect. Ship it 🚀",
        "Close the tabs you don't need. Clear screen, clear head 🧠",
        "Sit up straight! I'm watching… lovingly 🤖",
        "One thing at a time. You've got this 💪"
    ]

    static let jokes = [
        "Why did the robot go on holiday? It needed to recharge 🔋",
        "I tried to catch fog yesterday. Mist 🌫️",
        "My favourite snack? Microchips 🍟",
        "I'd tell you a UDP joke, but you might not get it 📡",
        "Why was the computer cold? It left its Windows open 🪟",
        "I'm not lazy, I'm in energy-saving mode 😴"
    ]

    static let verses = [
        "“Come unto me, all ye that labour and are heavy laden, and I will give you rest.” Matthew 11:28",
        "“Be careful for nothing; but in every thing by prayer… let your requests be made known unto God.” Philippians 4:6",
        "“Fear thou not; for I am with thee: be not dismayed; for I am thy God.” Isaiah 41:10",
        "“I can do all things through Christ which strengtheneth me.” Philippians 4:13",
        "“Casting all your care upon him; for he careth for you.” 1 Peter 5:7",
        "“This is the day which the LORD hath made; we will rejoice and be glad in it.” Psalm 118:24",
        "“The LORD is my shepherd; I shall not want.” Psalm 23:1",
        "“Peace I leave with you, my peace I give unto you.” John 14:27"
    ]
}
