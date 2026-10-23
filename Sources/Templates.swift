import Foundation

/// Starting points, built around DroidKay's thumbnail rules:
/// dark matte backgrounds, restrained red, text kept on the side away from the face,
/// "APOSTLE JOSHUA SELMAN" along the bottom, and straight (never curved) lettering.
enum Template: String, CaseIterable, Identifiable {
    case earlyMorning, psalm, dated, morning, doctor, blank
    var id: String { rawValue }

    var title: String {
        switch self {
        case .earlyMorning: return "Early Morning Prayer"
        case .psalm: return "Psalm Prayer"
        case .dated: return "Dated Prayer"
        case .morning: return "Morning (plain)"
        case .doctor: return "Doctor / Health"
        case .blank: return "Blank"
        }
    }

    var symbol: String {
        switch self {
        case .earlyMorning: return "sun.horizon.fill"
        case .psalm: return "book.closed.fill"
        case .dated: return "calendar"
        case .morning: return "sunrise.fill"
        case .doctor: return "cross.case.fill"
        case .blank: return "square.dashed"
        }
    }

    func make(keeping old: Design? = nil) -> Design {
        var d = Design()
        d.template = title
        // keep the person and date when switching templates
        if let o = old {
            d.subject.imagePath = o.subject.imagePath
            d.subject.cutout = o.subject.cutout
            d.date = o.date
        }
        let nameBand = TextBlock(name: "Name", text: "APOSTLE JOSHUA SELMAN", x: 0, y: 646, w: 1280, h: 74,
                                 font: "HelveticaNeue-CondensedBlack", maxSize: 50, color: .white, accent: .gold,
                                 strokeColor: .black, stroke: 0, shadow: false, align: .center, style: .band,
                                 boxColor: RGBA.deepRed.with(alpha: 0.92), lineSpacing: 1, uppercase: true)
        switch self {
        case .earlyMorning:
            // Matches the Friday "Speak into your morning" design: night-blue to sunrise, Poppins, yellow date pill.
            d.background = Background(kind: .sunrise, color1: RGBA(hex: 0x0A0B2E), color2: RGBA(hex: 0x2A0E36), darken: 0,
                                      vignette: 0.18, glow: RGBA(hex: 0xFF8A1A), glowStrength: 0.9, seed: 9)
            d.subject.centerX = 0.80
            d.subject.height = 1.02
            d.subject.bottom = 1.03
            d.blocks = [
                TextBlock(name: "Date", text: "", x: 50, y: 40, w: 650, h: 74, font: "Poppins-Bold", maxSize: 38,
                          color: RGBA(hex: 0x1C1406), stroke: 0, shadow: false, align: .left, style: .boxed,
                          boxColor: .sunGold, boxRadius: 14, boxPad: 0.48, dateFormat: .dayCommaDateYear),
                TextBlock(name: "Title", text: "SPEAK INTO YOUR\n[@DAY MORNING]\nBEFORE THE\n{ENEMY DOES}", x: 54, y: 166, w: 850, h: 440,
                          font: "Poppins-ExtraBold", maxSize: 110, color: .white, accent: .sunGold, accent2: .orangeRed,
                          stroke: 0, shadow: true, hardShadow: true, align: .left, lineSpacing: 1.1, sameSize: true, alignTop: true),
                TextBlock(name: "Footer", text: "EARLY MORNING PRAYER", x: 57, y: 636, w: 320, h: 64, font: "Poppins-SemiBold", maxSize: 26,
                          color: RGBA(1, 1, 1, 0.92), accent: .sunGold, stroke: 0, shadow: false, align: .left, style: .rule),
            ]
        case .psalm:
            d.background = Background(kind: .clouds, color1: RGBA(hex: 0x05070C), color2: RGBA(hex: 0x1B2130), darken: 0.15,
                                      vignette: 0.55, glow: RGBA(hex: 0xC4161C), glowStrength: 0.45, seed: 11)
            d.blocks = [
                TextBlock(name: "Psalm", text: "PSALM\n[35]", x: 46, y: 26, w: 600, h: 400, font: "Impact", maxSize: 250,
                          color: .white, accent: .gold, stroke: 4, align: .left, lineSpacing: 0.92),
                TextBlock(name: "Title", text: "CONTEND WITH\n[MY ENEMIES]", x: 46, y: 430, w: 620, h: 200, font: "Impact", maxSize: 92,
                          color: .white, accent: .gold, stroke: 6, align: .left),
                nameBand,
            ]
        case .dated:
            d.background = Background(kind: .clouds, color1: RGBA(hex: 0x030406), color2: RGBA(hex: 0x15171F), darken: 0.2,
                                      vignette: 0.5, glow: RGBA(hex: 0xB3120F), glowStrength: 0.35, seed: 23)
            d.blocks = [
                TextBlock(name: "Date", text: "", x: 46, y: 40, w: 640, h: 78, font: "HelveticaNeue-CondensedBlack", maxSize: 50,
                          color: .white, stroke: 0, shadow: false, align: .left, style: .boxed, boxColor: RGBA.deepRed,
                          dateFormat: .dayDate),
                TextBlock(name: "Title", text: "FATHER,\nREMEMBER ME\n[TODAY]", x: 46, y: 150, w: 640, h: 460, font: "Impact", maxSize: 128,
                          color: .white, accent: .gold, stroke: 6, align: .left, lineSpacing: 1.0),
                nameBand,
            ]
        case .morning:
            d.background = Background(kind: .solid, color1: RGBA(hex: 0x0D1522), color2: RGBA(hex: 0x0D1522), darken: 0,
                                      vignette: 0.25, glow: nil, glowStrength: 0, seed: 3)
            d.blocks = [
                TextBlock(name: "Date", text: "", x: 50, y: 48, w: 640, h: 60, font: "HelveticaNeue-CondensedBlack", maxSize: 46,
                          color: .gold, stroke: 0, shadow: false, align: .left, dateFormat: .dayDate),
                TextBlock(name: "Title", text: "SPEAK INTO\nYOUR\n[MORNING]", x: 50, y: 130, w: 640, h: 440, font: "Impact", maxSize: 132,
                          color: .white, accent: .gold, stroke: 0, shadow: true, align: .left, lineSpacing: 1.04),
                TextBlock(name: "Name", text: "APOSTLE JOSHUA SELMAN", x: 50, y: 610, w: 640, h: 60, font: "HelveticaNeue-CondensedBlack",
                          maxSize: 40, color: RGBA(1, 1, 1, 0.85), stroke: 0, shadow: false, align: .left),
            ]
        case .doctor:
            d.background = Background(kind: .gradient, color1: RGBA(hex: 0x0A2342), color2: RGBA(hex: 0x05101F), darken: 0,
                                      vignette: 0.4, glow: RGBA(hex: 0x2E86FF), glowStrength: 0.3, seed: 5)
            d.blocks = [
                TextBlock(name: "Tag", text: "DOCTORS WARN", x: 46, y: 46, w: 420, h: 72, font: "HelveticaNeue-CondensedBlack", maxSize: 48,
                          color: .white, stroke: 0, shadow: false, align: .left, style: .boxed, boxColor: .red),
                TextBlock(name: "Title", text: "STOP DOING THIS\n[AFTER 60]", x: 46, y: 150, w: 660, h: 420, font: "Impact", maxSize: 120,
                          color: .white, accent: .yellow, stroke: 7, align: .left),
            ]
        case .blank:
            d.background = Background(kind: .solid, color1: RGBA(hex: 0x111111), color2: RGBA(hex: 0x111111), vignette: 0.3)
            d.blocks = [
                TextBlock(name: "Title", text: "YOUR\n[TITLE]", x: 46, y: 150, w: 660, h: 420, font: "Impact", maxSize: 130,
                          color: .white, accent: .gold, stroke: 6, align: .left),
            ]
        }
        return d
    }
}
