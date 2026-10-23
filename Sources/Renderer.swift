import AppKit
import CoreImage
import Vision
import CoreText

/// Loads pictures once, and keeps the cut-out version of each person photo.
final class ImageStore {
    static let shared = ImageStore()
    private var images: [String: NSImage] = [:]
    private var cutouts: [String: NSImage] = [:]
    private var faces: [String: CGRect] = [:]
    private var clouds: [String: CGImage] = [:]
    private var pending: Set<String> = []
    var onReady: (() -> Void)?

    func image(_ path: String?) -> NSImage? {
        guard let p = path else { return nil }
        if let i = images[p] { return i }
        guard let i = NSImage(contentsOfFile: p) else { return nil }
        images[p] = i
        return i
    }

    /// The person without their photo's background, if ready. Starts working on it otherwise.
    func cutout(_ path: String?) -> NSImage? {
        guard let p = path else { return nil }
        if let c = cutouts[p] { return c }
        requestAnalysis(p)
        return nil
    }

    /// Face position in the photo, 0…1 with the origin at the top-left. Nil if none found (yet).
    func face(_ path: String?) -> CGRect? {
        guard let p = path else { return nil }
        if let f = faces[p] { return f.isNull ? nil : f }
        requestAnalysis(p)
        return nil
    }

    /// Same as the background work, but waits for it (used by the command-line sample renderer).
    func analyseNow(_ p: String) {
        guard let img = image(p) else { return }
        let (cut, face) = Vision2.analyse(img)
        if let c = cut { cutouts[p] = c }
        faces[p] = face ?? .null
        pending.insert(p)
    }

    private func requestAnalysis(_ p: String) {
        if pending.contains(p) { return }
        pending.insert(p)
        guard let img = image(p) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let (cut, face) = Vision2.analyse(img)
            DispatchQueue.main.async {
                if let c = cut { self.cutouts[p] = c }
                self.faces[p] = face ?? .null
                self.onReady?()
            }
        }
    }

    /// Smoky "dark clouds" texture in the two colours.
    func clouds(_ c1: RGBA, _ c2: RGBA, seed: Int) -> CGImage? {
        let key = "\(c1)\(c2)\(seed)"
        if let c = clouds[key] { return c }
        let ctx = CIContext()
        let w = Design.W, h = Design.H
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        // big soft blobs, then a few smaller ones on top for texture
        let shifted = noise.transformed(by: CGAffineTransform(translationX: CGFloat(seed * 97), y: CGFloat(seed * 53)))
        func blur(_ img: CIImage, scale: CGFloat, radius: Double) -> CIImage {
            let s = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            return s.applyingGaussianBlur(sigma: radius).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let big = blur(shifted, scale: 18, radius: 40)
        let mid = blur(shifted.transformed(by: CGAffineTransform(translationX: 500, y: 300)), scale: 6, radius: 14)
        let mixed = big.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputGVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputBVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
        ]).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: mid.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.12, y: 0.12, z: 0.12, w: 0),
            "inputGVector": CIVector(x: 0.12, y: 0.12, z: 0.12, w: 0),
            "inputBVector": CIVector(x: 0.12, y: 0.12, z: 0.12, w: 0),
        ])])
        // stretch contrast, then map dark→light onto colour1→colour2
        let contrasted = mixed.applyingFilter("CIColorControls", parameters: ["inputContrast": 2.6, "inputBrightness": -0.32, "inputSaturation": 0])
        let mapped = contrasted.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(cgColor: c1.cg), "inputColor1": CIColor(cgColor: c2.cg),
        ]).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        guard let cg = ctx.createCGImage(mapped, from: CGRect(x: 0, y: 0, width: w, height: h)) else { return nil }
        clouds[key] = cg
        return cg
    }
}

/// Apple's on-device Vision: find the face, and lift the person off their background.
enum Vision2 {
    static func analyse(_ img: NSImage) -> (NSImage?, CGRect?) {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return (nil, nil) }
        var face: CGRect?
        let fr = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([fr])
        if let best = fr.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
            let b = best.boundingBox // origin bottom-left
            face = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
        }
        var cut: NSImage?
        if #available(macOS 14.0, *) {
            let req = VNGenerateForegroundInstanceMaskRequest()
            let h2 = VNImageRequestHandler(cgImage: cg, options: [:])
            if (try? h2.perform([req])) != nil, let r = req.results?.first {
                if let buf = try? r.generateMaskedImage(ofInstances: r.allInstances, from: h2, croppedToInstancesExtent: false) {
                    let ci = CIImage(cvPixelBuffer: buf)
                    if let out = CIContext().createCGImage(ci, from: ci.extent) {
                        cut = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
                    }
                }
            }
        }
        return (cut, face)
    }
}

/// Where things ended up on the canvas (for the checks and for dragging).
struct Layout {
    var subjectRect: CGRect = .null
    var faceRect: CGRect = .null
    var textRects: [UUID: [CGRect]] = [:]
}

/// Draws a Design at exactly 1280×720 — the same picture for the preview and the export.
enum Renderer {
    static func render(_ d: Design, store: ImageStore = .shared, drawText: Bool = true) -> (CGImage?, Layout) {
        let W = Int(Design.W), H = Int(Design.H)
        var layout = Layout()
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (nil, layout) }
        // top-left origin, like the design coordinates
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let full = CGRect(x: 0, y: 0, width: W, height: H)

        drawBackground(d.background, in: full, ctx: ctx, store: store)

        // the person
        let photo = d.subject.cutout ? (store.cutout(d.subject.imagePath) ?? store.image(d.subject.imagePath)) : store.image(d.subject.imagePath)
        if let img = photo, img.size.width > 0 {
            let h = CGFloat(d.subject.height) * Design.H
            let w = h * img.size.width / img.size.height
            let r = CGRect(x: CGFloat(d.subject.centerX) * Design.W - w / 2, y: CGFloat(d.subject.bottom) * Design.H - h, width: w, height: h)
            layout.subjectRect = r
            if let g = d.background.glow, d.background.glowStrength > 0 {
                drawGlow(g, strength: d.background.glowStrength, around: r, ctx: ctx)
            }
            ctx.saveGState()
            if d.subject.flip {
                ctx.translateBy(x: r.midX, y: 0)
                ctx.scaleBy(x: -1, y: 1)
                ctx.translateBy(x: -r.midX, y: 0)
            }
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            ctx.restoreGState()
            if let f = store.face(d.subject.imagePath) {
                var fx = f.minX
                if d.subject.flip { fx = 1 - f.maxX }
                layout.faceRect = CGRect(x: r.minX + fx * r.width, y: r.minY + f.minY * r.height, width: f.width * r.width, height: f.height * r.height)
            }
        } else if let g = d.background.glow, d.background.glowStrength > 0 {
            let r = CGRect(x: CGFloat(d.subject.centerX) * Design.W - 250, y: 120, width: 500, height: 600)
            drawGlow(g, strength: d.background.glowStrength, around: r, ctx: ctx)
        }

        if d.background.vignette > 0 { drawVignette(d.background.vignette, in: full, ctx: ctx) }

        if drawText {
            for b in d.blocks {
                layout.textRects[b.id] = drawBlock(b, date: d.date)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return (ctx.makeImage(), layout)
    }

    // MARK: background

    static func drawBackground(_ bg: Background, in r: CGRect, ctx: CGContext, store: ImageStore) {
        switch bg.kind {
        case .solid:
            ctx.setFillColor(bg.color1.cg)
            ctx.fill(r)
        case .gradient:
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bg.color1.cg, bg.color2.cg] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX * 0.4, y: r.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .clouds:
            ctx.setFillColor(bg.color1.cg)
            ctx.fill(r)
            if let c = store.clouds(bg.color1, bg.color2, seed: bg.seed) {
                ctx.saveGState()
                // CGContext images are drawn bottom-up; flip back for this one
                ctx.translateBy(x: 0, y: r.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(c, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
                ctx.restoreGState()
            }
        case .image:
            ctx.setFillColor(bg.color1.cg)
            ctx.fill(r)
            if let img = store.image(bg.imagePath), img.size.width > 0 {
                // fill the frame, cropping the edges
                let s = max(r.width / img.size.width, r.height / img.size.height)
                let w = img.size.width * s, h = img.size.height * s
                img.draw(in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h), from: .zero, operation: .sourceOver,
                         fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
        }
        if bg.darken > 0 {
            ctx.setFillColor(RGBA.black.with(alpha: bg.darken).cg)
            ctx.fill(r)
        }
    }

    static func drawGlow(_ c: RGBA, strength: Double, around r: CGRect, ctx: CGContext) {
        let center = CGPoint(x: r.midX, y: r.minY + r.height * 0.42)
        let radius = max(r.width, r.height) * 0.62
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [c.with(alpha: 0.85 * strength).cg, c.with(alpha: 0.25 * strength).cg, c.with(alpha: 0).cg] as CFArray,
                           locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    static func drawVignette(_ amount: Double, in r: CGRect, ctx: CGContext) {
        let center = CGPoint(x: r.midX, y: r.midY)
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [RGBA.black.with(alpha: 0).cg, RGBA.black.with(alpha: 0).cg, RGBA.black.with(alpha: amount).cg] as CFArray,
                           locations: [0, 0.55, 1])!
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: r.width / r.height, y: 1)
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r.height * 0.78, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    // MARK: text

    /// The block's lines after applying the date and capitals.
    static func lines(of b: TextBlock, date: Date) -> [String] {
        var t = b.dateFormat.map { $0.format(date) } ?? b.text
        if b.uppercase { t = t.uppercased() }
        return t.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Builds one line, colouring [bracketed] words with the accent colour.
    static func attributed(_ line: String, b: TextBlock, size: CGFloat, outline: Bool) -> NSAttributedString {
        let font = Fonts.font(b.font, size: size)
        let out = NSMutableAttributedString()
        var accent = false
        var buf = ""
        func flush() {
            if buf.isEmpty { return }
            var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: (accent ? b.accent : b.color).ns]
            if outline {
                a[.strokeColor] = b.strokeColor.ns
                a[.strokeWidth] = b.stroke * 2 // positive = outline only; it's centred on the edge, so double it
                a[.foregroundColor] = NSColor.clear
            }
            out.append(NSAttributedString(string: buf, attributes: a))
            buf = ""
        }
        for ch in line {
            if ch == "[" { flush(); accent = true } else if ch == "]" { flush(); accent = false } else { buf.append(ch) }
        }
        flush()
        return out
    }

    /// Font size so every line fits the box (each line can be as big as its width allows, up to maxSize).
    static func sizes(for lines: [String], b: TextBlock) -> [CGFloat] {
        let pad: CGFloat = b.style == .plain ? 0 : 28
        var s: [CGFloat] = lines.map { line in
            let probe = attributed(line, b: b, size: 100, outline: false).size().width
            let fit = probe > 0 ? 100 * (CGFloat(b.w) - pad) / probe : CGFloat(b.maxSize)
            return min(CGFloat(b.maxSize), fit)
        }
        // keep lines from varying wildly: no line more than 1.6× the smallest
        if let mn = s.min() { s = s.map { min($0, mn * 1.6) } }
        let total = s.reduce(0) { $0 + $1 * CGFloat(b.lineSpacing) }
        if total > CGFloat(b.h) && total > 0 { s = s.map { $0 * CGFloat(b.h) / total } }
        return s
    }

    @discardableResult
    static func drawBlock(_ b: TextBlock, date: Date) -> [CGRect] {
        let ls = lines(of: b, date: date)
        if ls.isEmpty { return [] }
        let ss = sizes(for: ls, b: b)
        var rects: [CGRect] = []
        let total = ss.reduce(0) { $0 + $1 * CGFloat(b.lineSpacing) }
        if b.style == .band {
            NSGraphicsContext.current?.cgContext.setFillColor(b.boxColor.cg)
            NSGraphicsContext.current?.cgContext.fill(b.rect)
        }
        var y = CGFloat(b.y) + max(0, (CGFloat(b.h) - total) / 2)
        for (i, line) in ls.enumerated() {
            let size = ss[i]
            let fill = attributed(line, b: b, size: size, outline: false)
            let ts = fill.size()
            let lineH = size * CGFloat(b.lineSpacing)
            var x: CGFloat
            let inset: CGFloat = b.style == .boxed ? 14 : 0
            switch b.align {
            case .left: x = CGFloat(b.x) + inset
            case .center: x = CGFloat(b.x) + (CGFloat(b.w) - ts.width) / 2
            case .right: x = CGFloat(b.x) + CGFloat(b.w) - ts.width - inset
            }
            // centre the glyphs in the line's slot (fonts carry extra space above and below)
            let font = Fonts.font(b.font, size: size)
            let glyphH = font.capHeight
            let baselineY = y + (lineH + glyphH) / 2
            let origin = CGPoint(x: x, y: baselineY - font.ascender)
            let box = CGRect(x: x - inset, y: baselineY - glyphH - size * 0.16, width: ts.width + inset * 2, height: glyphH + size * 0.32)
            if b.style == .boxed {
                let ctx = NSGraphicsContext.current!.cgContext
                ctx.setFillColor(b.boxColor.cg)
                ctx.addPath(CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil))
                ctx.fillPath()
            }
            // Draw with Core Text so the outline uses rounded corners (no spiky letter tips).
            let ctx = NSGraphicsContext.current!.cgContext
            let ctLine = CTLineCreateWithAttributedString(fill)
            ctx.saveGState()
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: origin.x, y: baselineY)
            if b.stroke > 0 {
                ctx.saveGState()
                ctx.setTextDrawingMode(.stroke)
                ctx.setLineJoin(.round)
                ctx.setLineCap(.round)
                ctx.setLineWidth(size * CGFloat(b.stroke) / 100 * 2)
                ctx.setStrokeColor(b.strokeColor.cg)
                if b.shadow {
                    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.04), blur: size * 0.12, color: NSColor.black.withAlphaComponent(0.7).cgColor)
                }
                CTLineDraw(ctLine, ctx)
                ctx.restoreGState()
                ctx.textPosition = CGPoint(x: origin.x, y: baselineY)
            }
            ctx.setTextDrawingMode(.fill)
            if b.shadow && b.stroke <= 0 {
                ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.04), blur: size * 0.12, color: NSColor.black.withAlphaComponent(0.75).cgColor)
            }
            CTLineDraw(ctLine, ctx)
            ctx.restoreGState()
            rects.append(b.style == .band ? b.rect : box)
            y += lineH
        }
        return rects
    }
}
