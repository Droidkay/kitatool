import SwiftUI
import AppKit

enum ClipKind: String, Codable, CaseIterable {
    case text, link, email, number, code, color, image, file

    var title: String {
        switch self {
        case .text: return "Text"
        case .link: return "Link"
        case .email: return "Email"
        case .number: return "Number"
        case .code: return "Code"
        case .color: return "Colour"
        case .image: return "Image"
        case .file: return "File"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .email: return "envelope.fill"
        case .number: return "number"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette.fill"
        case .image: return "photo.fill"
        case .file: return "doc.fill"
        }
    }

    var tint: Color {
        switch self {
        case .text: return Color(red: 0.55, green: 0.62, blue: 0.75)
        case .link: return Color(red: 0.25, green: 0.55, blue: 1.0)
        case .email: return Color(red: 0.15, green: 0.75, blue: 0.75)
        case .number: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .code: return Color(red: 0.65, green: 0.45, blue: 1.0)
        case .color: return Color(red: 1.0, green: 0.4, blue: 0.65)
        case .image: return Color(red: 0.3, green: 0.8, blue: 0.45)
        case .file: return Color(red: 0.95, green: 0.78, blue: 0.25)
        }
    }

    /// Works out what kind of text this is.
    static func detect(_ s: String) -> ClipKind {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let single = !t.contains("\n") && !t.contains(" ")
        if single, let u = URL(string: t), let scheme = u.scheme?.lowercased(),
           ["http", "https", "ftp", "mailto", "file"].contains(scheme), u.host != nil || scheme == "mailto" {
            return .link
        }
        if single, t.range(of: "^www\\.[^\\s]+\\.[a-z]{2,}", options: [.regularExpression, .caseInsensitive]) != nil {
            return .link
        }
        if single, t.range(of: "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$", options: [.regularExpression, .caseInsensitive]) != nil {
            return .email
        }
        if t.range(of: "^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$", options: [.regularExpression, .caseInsensitive]) != nil {
            return .color
        }
        if t.count <= 40, t.range(of: "^[+-]?[₦$€£]?\\s?[0-9][0-9,. ]*%?$", options: .regularExpression) != nil {
            return .number
        }
        if looksLikeCode(t) { return .code }
        return .text
    }

    private static func looksLikeCode(_ t: String) -> Bool {
        let firstLine = t.split(separator: "\n").first.map(String.init) ?? t
        let commands = ["git ", "cd ", "npm ", "npx ", "brew ", "sudo ", "swift ", "python", "pip ", "curl ",
                        "ls ", "mkdir ", "rm ", "cp ", "mv ", "xattr ", "bash ", "open ", "./", "$ ", "yarn ", "node "]
        if !t.contains("\n") && commands.contains(where: { firstLine.hasPrefix($0) }) { return true }
        var score = 0
        let markers = ["{", "}", "();", "=>", "->", "func ", "def ", "const ", "let ", "var ", "import ",
                       "return ", "class ", "</", "/>", "==", "!=", "&&", "||", "#include", "public ", "fun "]
        for m in markers where t.contains(m) { score += 1 }
        let lines = t.split(separator: "\n")
        if lines.count > 1 && lines.filter({ $0.hasPrefix("    ") || $0.hasPrefix("\t") }).count >= 1 { score += 1 }
        if t.hasSuffix(";") { score += 1 }
        return score >= 2
    }
}

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ClipKind
    var text: String?
    var imageFile: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var filePaths: [String]?
    var contentHash: String?
    var created = Date()
    var lastUsed = Date()
    var sourceApp: String?
    var sourceBundle: String?
    var pinned = false
    var useCount = 0

    /// Text used for search.
    var searchText: String {
        if let text { return text }
        if let filePaths { return filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: " ") }
        return "image"
    }

    var fileURLs: [URL] { (filePaths ?? []).map { URL(fileURLWithPath: $0) } }
}

enum ClipFilter: String, CaseIterable, Identifiable {
    case all, pinned, text, links, code, images, files
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .pinned: return "Pinned"
        case .text: return "Text"
        case .links: return "Links"
        case .code: return "Code"
        case .images: return "Images"
        case .files: return "Files"
        }
    }

    func matches(_ c: Clip) -> Bool {
        switch self {
        case .all: return true
        case .pinned: return c.pinned
        case .text: return [.text, .number, .email, .color].contains(c.kind)
        case .links: return c.kind == .link || c.kind == .email
        case .code: return c.kind == .code
        case .images: return c.kind == .image
        case .files: return c.kind == .file
        }
    }
}

enum TextTransform: String, CaseIterable, Identifiable {
    case upper, lower, title, sentence, trim, oneLine, removeEmptyLines
    var id: String { rawValue }

    var title: String {
        switch self {
        case .upper: return "UPPERCASE"
        case .lower: return "lowercase"
        case .title: return "Title Case"
        case .sentence: return "Sentence case"
        case .trim: return "Trim spaces"
        case .oneLine: return "Join into one line"
        case .removeEmptyLines: return "Remove empty lines"
        }
    }

    func apply(_ s: String) -> String {
        switch self {
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .title: return s.capitalized
        case .sentence:
            let lower = s.lowercased()
            var out = ""
            var capNext = true
            for ch in lower {
                if capNext && ch.isLetter { out.append(contentsOf: String(ch).uppercased()); capNext = false }
                else { out.append(ch) }
                if ".!?\n".contains(ch) { capNext = true }
            }
            return out
        case .trim:
            return s.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .oneLine:
            return s.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .removeEmptyLines:
            return s.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
        }
    }
}

func colorFromHex(_ hex: String) -> Color? {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
    let rgb = h.count == 8 ? v >> 8 : v
    return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                 green: Double((rgb >> 8) & 0xFF) / 255,
                 blue: Double(rgb & 0xFF) / 255)
}
