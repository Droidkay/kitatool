import AppKit

struct Check: Identifiable, Equatable {
    enum Level { case good, tip, warn }
    let id = UUID()
    let level: Level
    let text: String

    static func == (a: Check, b: Check) -> Bool { a.text == b.text && a.level == b.level }
}

/// "Will this work on a phone?" — the size YouTube shows thumbnails on the home feed is about 246 px wide.
enum Checks {
    static let phoneWidth: CGFloat = 246

    static func run(_ d: Design, layout: Layout, plate: CGImage?) -> [Check] {
        var out: [Check] = []
        let scale = phoneWidth / Design.W
        let face = layout.faceRect.isNull ? nil : layout.faceRect.insetBy(dx: -layout.faceRect.width * 0.08, dy: -layout.faceRect.height * 0.08)
        var covered = false, tooSmall: [String] = [], lowContrast: [String] = []

        for b in d.blocks {
            let ls = Renderer.lines(of: b, date: d.date)
            if ls.isEmpty { continue }
            let ss = Renderer.sizes(for: ls, b: b)
            // capital letters on a phone, in pixels
            // capital-letter height on a phone: the title needs more than small labels
            let need: CGFloat = b.name == "Title" ? 7.5 : 4.8
            if let mn = ss.min(), mn * 0.72 * scale < need { tooSmall.append(b.name) }
            if let f = face, let rs = layout.textRects[b.id], b.style != .band, rs.contains(where: { $0.intersects(f) }) { covered = true }
            if b.style == .plain && b.stroke < 2, let p = plate, let rs = layout.textRects[b.id] {
                let bg = averageLuminance(p, in: rs.reduce(CGRect.null) { $0.union($1) })
                if abs(bg - b.color.luminance) < 0.45 { lowContrast.append(b.name) }
            }
        }

        let titleWords = d.blocks.first(where: { $0.name == "Title" }).map {
            Renderer.lines(of: $0, date: d.date).joined(separator: " ").replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                .split(separator: " ").count
        } ?? 0

        if d.subject.imagePath == nil {
            out.append(Check(level: .tip, text: "Add a photo: drag one onto the thumbnail."))
        } else if layout.faceRect.isNull {
            out.append(Check(level: .tip, text: "No face found in the photo, so I can't check the text stays off it."))
        } else if covered {
            out.append(Check(level: .warn, text: "Text is covering the face. Tap \"Keep text off face\"."))
        } else {
            out.append(Check(level: .good, text: "Face is clear of text."))
        }
        if !tooSmall.isEmpty {
            out.append(Check(level: .warn, text: "\(tooSmall.joined(separator: ", ")) will be too small on phones. Use fewer words or a bigger size."))
        } else {
            out.append(Check(level: .good, text: "Text is readable at phone size."))
        }
        if !lowContrast.isEmpty {
            out.append(Check(level: .warn, text: "\(lowContrast.joined(separator: ", ")) blends into the background. Add an outline or change the colour."))
        }
        if titleWords > 7 {
            out.append(Check(level: .tip, text: "Title has \(titleWords) words. 3–6 big words usually get more clicks."))
        }
        if d.background.kind == .image && d.background.darken < 0.2 {
            out.append(Check(level: .tip, text: "Busy picture behind the text? Darken it a little."))
        }
        return out
    }

    /// Average brightness (0…1) of part of an image.
    static func averageLuminance(_ img: CGImage, in r: CGRect) -> Double {
        guard !r.isNull, r.width > 1, r.height > 1 else { return 0 }
        let crop = r.intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        guard !crop.isNull, let part = img.cropping(to: crop.integral) else { return 0 }
        var px = [UInt8](repeating: 0, count: 16 * 16 * 4)
        guard let ctx = CGContext(data: &px, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        var sum = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            sum += (0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])) / 255
        }
        return sum / 256
    }
}

enum Layouts {
    /// Moves text blocks to the side away from the face (bands along the bottom stay put).
    static func keepOffFace(_ d: Design, layout: Layout) -> Design {
        var d = d
        let subject = layout.subjectRect.isNull ? nil : layout.subjectRect
        let face = layout.faceRect.isNull ? subject : layout.faceRect
        guard let f = face else { return d }
        let textOnLeft = f.midX > Design.W / 2
        // room between the edge of the thumbnail and the person (face plus some shoulder room)
        let margin: CGFloat = 46
        let gap: CGFloat = 30
        let limitLeft = f.minX - gap   // text on the left must end before the face
        let limitRight = f.maxX + gap  // text on the right must start after it
        for i in d.blocks.indices where d.blocks[i].style != .band {
            var b = d.blocks[i]
            if textOnLeft {
                b.x = Double(margin)
                b.w = Double(max(300, limitLeft - margin))
                if b.align == .right { b.align = .left }
            } else {
                b.w = Double(max(300, Design.W - margin - limitRight))
                b.x = Double(Design.W - margin) - b.w
                if b.align == .left { b.align = .right }
            }
            d.blocks[i] = b
        }
        return d
    }

    /// Mirror image of the layout: person on the other side, text follows.
    static func mirrored(_ d: Design) -> Design {
        var d = d
        d.subject.centerX = 1 - d.subject.centerX
        d.subject.flip.toggle()
        for i in d.blocks.indices where d.blocks[i].style != .band {
            d.blocks[i].x = Double(Design.W) - d.blocks[i].x - d.blocks[i].w
            switch d.blocks[i].align {
            case .left: d.blocks[i].align = .right
            case .right: d.blocks[i].align = .left
            case .center: break
            }
        }
        return d
    }

    /// Four options to choose from.
    static func variations(_ d: Design) -> [(String, Design)] {
        var out: [(String, Design)] = [("Current", d)]
        out.append(("Mirrored", mirrored(d)))

        var gold = d
        for i in gold.blocks.indices where gold.blocks[i].style == .plain {
            gold.blocks[i].accent = gold.blocks[i].accent == .gold || gold.blocks[i].accent == .yellow ? RGBA.red : RGBA.gold
        }
        out.append((gold.blocks.contains { $0.accent == .red } ? "Red words" : "Gold words", gold))

        var bold = d
        if let t = bold.blocks.firstIndex(where: { $0.name == "Title" }) {
            bold.blocks[t].maxSize *= 1.18
            bold.blocks[t].stroke = max(bold.blocks[t].stroke, 8)
            bold.background.darken = min(0.6, bold.background.darken + 0.15)
            bold.background.vignette = min(0.8, bold.background.vignette + 0.15)
        }
        out.append(("Bolder", bold))
        return out
    }
}
