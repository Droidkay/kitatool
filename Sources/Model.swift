import AppKit
import CoreText

/// A colour that can be saved to a preset file.
struct RGBA: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    init(_ c: NSColor) {
        let s = c.usingColorSpace(.sRGB) ?? .white
        r = Double(s.redComponent); g = Double(s.greenComponent); b = Double(s.blueComponent); a = Double(s.alphaComponent)
    }

    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cg: CGColor { ns.cgColor }
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    func with(alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }

    static let white = RGBA(1, 1, 1)
    static let black = RGBA(0, 0, 0)
    static let gold = RGBA(hex: 0xFFC83D)
    static let yellow = RGBA(hex: 0xFFE000)
    static let red = RGBA(hex: 0xE0201B)
    static let deepRed = RGBA(hex: 0xB3120F)
    static let navy = RGBA(hex: 0x0B1426)
    static let sunGold = RGBA(hex: 0xFFC531)
    static let orangeRed = RGBA(hex: 0xFF4A2B)
}

enum BackgroundKind: String, Codable, CaseIterable, Identifiable {
    case solid, gradient, clouds, sunrise, image
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: return "Plain"
        case .gradient: return "Gradient"
        case .clouds: return "Dark clouds"
        case .sunrise: return "Sunrise glow"
        case .image: return "Your picture"
        }
    }
}

struct Background: Codable, Equatable {
    var kind: BackgroundKind = .solid
    var color1: RGBA = .black
    var color2: RGBA = RGBA(hex: 0x1A1A1A)
    var imagePath: String?
    /// 0 = untouched, 1 = black.
    var darken: Double = 0
    var vignette: Double = 0.35
    /// Soft coloured light behind the person (e.g. restrained red).
    var glow: RGBA? = nil
    var glowStrength: Double = 0.5
    var seed: Int = 7

    init(kind: BackgroundKind = .solid, color1: RGBA = .black, color2: RGBA = RGBA(hex: 0x1A1A1A), imagePath: String? = nil,
         darken: Double = 0, vignette: Double = 0.35, glow: RGBA? = nil, glowStrength: Double = 0.5, seed: Int = 7) {
        self.kind = kind; self.color1 = color1; self.color2 = color2; self.imagePath = imagePath; self.darken = darken
        self.vignette = vignette; self.glow = glow; self.glowStrength = glowStrength; self.seed = seed
    }

    // Older saved designs may miss newer fields; fill in defaults instead of failing.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let z = Background()
        kind = (try? c.decode(BackgroundKind.self, forKey: .kind)) ?? z.kind
        color1 = (try? c.decode(RGBA.self, forKey: .color1)) ?? z.color1
        color2 = (try? c.decode(RGBA.self, forKey: .color2)) ?? z.color2
        imagePath = try? c.decode(String.self, forKey: .imagePath)
        darken = (try? c.decode(Double.self, forKey: .darken)) ?? z.darken
        vignette = (try? c.decode(Double.self, forKey: .vignette)) ?? z.vignette
        glow = try? c.decode(RGBA.self, forKey: .glow)
        glowStrength = (try? c.decode(Double.self, forKey: .glowStrength)) ?? z.glowStrength
        seed = (try? c.decode(Int.self, forKey: .seed)) ?? z.seed
    }
}

struct Subject: Codable, Equatable {
    var imagePath: String?
    /// Cut the person out of their photo's background (macOS 14+).
    var cutout: Bool = true
    /// Horizontal centre, 0…1 of the canvas width.
    var centerX: Double = 0.73
    /// Bottom edge, 0…1 of the canvas height (1 = bottom of the thumbnail).
    var bottom: Double = 1.0
    /// Height, as a fraction of the canvas height.
    var height: Double = 1.0
    var flip: Bool = false
}

enum LineStyle: String, Codable, CaseIterable, Identifiable {
    case plain, boxed, band, rule
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plain: return "Plain"
        case .boxed: return "Box behind each line"
        case .band: return "Full-width band"
        case .rule: return "Line above"
        }
    }
}

enum TextAlign: String, Codable, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
}

enum DateFormat: String, Codable, CaseIterable, Identifiable {
    case dayDate, dayDateYear, dayCommaDateYear, dayOnly, dateOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dayDate: return "SATURDAY 24TH OCTOBER"
        case .dayDateYear: return "SATURDAY 24TH OCTOBER 2026"
        case .dayCommaDateYear: return "SATURDAY, 24TH OCTOBER, 2026"
        case .dayOnly: return "SATURDAY"
        case .dateOnly: return "24TH OCTOBER 2026"
        }
    }

    func format(_ d: Date) -> String {
        let cal = Calendar.current
        let day = cal.component(.day, from: d)
        let suffix: String
        switch day {
        case 11, 12, 13: suffix = "TH"
        default:
            switch day % 10 {
            case 1: suffix = "ST"
            case 2: suffix = "ND"
            case 3: suffix = "RD"
            default: suffix = "TH"
            }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE"
        let weekday = f.string(from: d).uppercased()
        f.dateFormat = "MMMM"
        let month = f.string(from: d).uppercased()
        let year = cal.component(.year, from: d)
        switch self {
        case .dayDate: return "\(weekday) \(day)\(suffix) \(month)"
        case .dayDateYear: return "\(weekday) \(day)\(suffix) \(month) \(year)"
        case .dayCommaDateYear: return "\(weekday), \(day)\(suffix) \(month), \(year)"
        case .dayOnly: return weekday
        case .dateOnly: return "\(day)\(suffix) \(month) \(year)"
        }
    }
}

/// One block of text. Put [square brackets] around words for the accent colour, {curly brackets} for the second accent,
/// and write @DAY to get the weekday of the chosen date (e.g. "[@DAY MORNING]" → "FRIDAY MORNING").
struct TextBlock: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var text: String
    /// Box on the 1280×720 canvas.
    var x: Double, y: Double, w: Double, h: Double
    var font: String = "Impact"
    var maxSize: Double = 100
    var color: RGBA = .white
    var accent: RGBA = .gold
    var accent2: RGBA = .orangeRed
    var strokeColor: RGBA = .black
    /// Outline thickness, as % of the font size (0 = none).
    var stroke: Double = 7
    var shadow: Bool = true
    /// Solid offset shadow (sticker look) instead of a soft one.
    var hardShadow: Bool = false
    var align: TextAlign = .left
    var style: LineStyle = .plain
    var boxColor: RGBA = .red
    var boxRadius: Double = 6
    /// Space above and below the text inside a box, as a fraction of the font size.
    var boxPad: Double = 0.16
    var lineSpacing: Double = 1.02
    var uppercase: Bool = true
    /// Every line the same size (otherwise short lines can grow bigger).
    var sameSize: Bool = false
    /// Start at the top of the box instead of centring the lines in it.
    var alignTop: Bool = false
    /// Text comes from the date picker instead of typing.
    var dateFormat: DateFormat? = nil

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    init(name: String, text: String, x: Double, y: Double, w: Double, h: Double, font: String = "Impact", maxSize: Double = 100,
         color: RGBA = .white, accent: RGBA = .gold, accent2: RGBA = .orangeRed, strokeColor: RGBA = .black, stroke: Double = 7,
         shadow: Bool = true, hardShadow: Bool = false, align: TextAlign = .left, style: LineStyle = .plain, boxColor: RGBA = .red,
         boxRadius: Double = 6, boxPad: Double = 0.16, lineSpacing: Double = 1.02, uppercase: Bool = true, sameSize: Bool = false,
         alignTop: Bool = false, dateFormat: DateFormat? = nil) {
        self.name = name; self.text = text; self.x = x; self.y = y; self.w = w; self.h = h; self.font = font; self.maxSize = maxSize
        self.color = color; self.accent = accent; self.accent2 = accent2; self.strokeColor = strokeColor; self.stroke = stroke
        self.shadow = shadow; self.hardShadow = hardShadow; self.align = align; self.style = style; self.boxColor = boxColor
        self.boxRadius = boxRadius; self.boxPad = boxPad; self.lineSpacing = lineSpacing; self.uppercase = uppercase
        self.sameSize = sameSize; self.alignTop = alignTop; self.dateFormat = dateFormat
    }

    // Older saved designs may miss newer fields; fill in defaults instead of failing.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let z = TextBlock(name: "", text: "", x: 0, y: 0, w: 0, h: 0)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Text"
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        x = (try? c.decode(Double.self, forKey: .x)) ?? 60
        y = (try? c.decode(Double.self, forKey: .y)) ?? 200
        w = (try? c.decode(Double.self, forKey: .w)) ?? 500
        h = (try? c.decode(Double.self, forKey: .h)) ?? 200
        font = (try? c.decode(String.self, forKey: .font)) ?? z.font
        maxSize = (try? c.decode(Double.self, forKey: .maxSize)) ?? z.maxSize
        color = (try? c.decode(RGBA.self, forKey: .color)) ?? z.color
        accent = (try? c.decode(RGBA.self, forKey: .accent)) ?? z.accent
        accent2 = (try? c.decode(RGBA.self, forKey: .accent2)) ?? z.accent2
        strokeColor = (try? c.decode(RGBA.self, forKey: .strokeColor)) ?? z.strokeColor
        stroke = (try? c.decode(Double.self, forKey: .stroke)) ?? z.stroke
        shadow = (try? c.decode(Bool.self, forKey: .shadow)) ?? z.shadow
        hardShadow = (try? c.decode(Bool.self, forKey: .hardShadow)) ?? z.hardShadow
        align = (try? c.decode(TextAlign.self, forKey: .align)) ?? z.align
        style = (try? c.decode(LineStyle.self, forKey: .style)) ?? z.style
        boxColor = (try? c.decode(RGBA.self, forKey: .boxColor)) ?? z.boxColor
        boxRadius = (try? c.decode(Double.self, forKey: .boxRadius)) ?? z.boxRadius
        boxPad = (try? c.decode(Double.self, forKey: .boxPad)) ?? z.boxPad
        lineSpacing = (try? c.decode(Double.self, forKey: .lineSpacing)) ?? z.lineSpacing
        uppercase = (try? c.decode(Bool.self, forKey: .uppercase)) ?? z.uppercase
        sameSize = (try? c.decode(Bool.self, forKey: .sameSize)) ?? z.sameSize
        alignTop = (try? c.decode(Bool.self, forKey: .alignTop)) ?? z.alignTop
        dateFormat = try? c.decode(DateFormat.self, forKey: .dateFormat)
    }
}

struct Design: Codable, Equatable {
    var template: String = "Blank"
    var background = Background()
    var subject = Subject()
    var blocks: [TextBlock] = []
    var date: Date = Date()

    static let W: CGFloat = 1280
    static let H: CGFloat = 720
}

/// Fonts that are on every Mac and suit thumbnails.
enum Fonts {
    static let all: [(name: String, title: String)] = [
        ("Poppins-ExtraBold", "Poppins ExtraBold"),
        ("Poppins-Black", "Poppins Black"),
        ("Poppins-Bold", "Poppins Bold"),
        ("Poppins-SemiBold", "Poppins SemiBold"),
        ("Impact", "Impact"),
        ("HelveticaNeue-CondensedBlack", "Helvetica Condensed Black"),
        ("Futura-CondensedExtraBold", "Futura Condensed"),
        ("DINCondensed-Bold", "DIN Condensed"),
        ("Arial-Black", "Arial Black"),
        ("AvenirNext-Heavy", "Avenir Heavy"),
        ("Georgia-Bold", "Georgia Bold (serif)"),
        ("Didot-Bold", "Didot Bold (serif)"),
        ("system-black", "System Black"),
    ]

    /// Registers the fonts that come inside the app (Poppins).
    static func registerBundled() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
        for u in urls { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
    }

    static func font(_ name: String, size: CGFloat) -> NSFont {
        if name != "system-black", let f = NSFont(name: name, size: size) { return f }
        return NSFont.systemFont(ofSize: size, weight: .black)
    }
}
