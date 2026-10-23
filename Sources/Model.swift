import AppKit

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
}

enum BackgroundKind: String, Codable, CaseIterable, Identifiable {
    case solid, gradient, clouds, image
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: return "Plain"
        case .gradient: return "Gradient"
        case .clouds: return "Dark clouds"
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
    case plain, boxed, band
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plain: return "Plain"
        case .boxed: return "Box behind each line"
        case .band: return "Full-width band"
        }
    }
}

enum TextAlign: String, Codable, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
}

enum DateFormat: String, Codable, CaseIterable, Identifiable {
    case dayDate, dayDateYear, dayOnly, dateOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dayDate: return "SATURDAY 24TH OCTOBER"
        case .dayDateYear: return "SATURDAY 24TH OCTOBER 2026"
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
        case .dayOnly: return weekday
        case .dateOnly: return "\(day)\(suffix) \(month) \(year)"
        }
    }
}

/// One block of text. Put [square brackets] around words to colour them with the accent colour.
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
    var strokeColor: RGBA = .black
    /// Outline thickness, as % of the font size (0 = none).
    var stroke: Double = 7
    var shadow: Bool = true
    var align: TextAlign = .left
    var style: LineStyle = .plain
    var boxColor: RGBA = .red
    var lineSpacing: Double = 1.02
    var uppercase: Bool = true
    /// Text comes from the date picker instead of typing.
    var dateFormat: DateFormat? = nil

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
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

    static func font(_ name: String, size: CGFloat) -> NSFont {
        if name != "system-black", let f = NSFont(name: name, size: size) { return f }
        return NSFont.systemFont(ofSize: size, weight: .black)
    }
}
