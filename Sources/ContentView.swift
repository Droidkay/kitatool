import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var m: AppModel
    @State private var presetName = ""
    @State private var askPreset = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(m: m, askPreset: $askPreset)
                .frame(width: 210)
            Divider()
            VStack(spacing: 14) {
                CanvasView(m: m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(alignment: .top, spacing: 16) {
                    OptionsRow(m: m)
                    Divider().frame(height: 150)
                    PhoneCheck(m: m)
                }
                .frame(height: 170)
                BottomBar(m: m)
            }
            .padding(16)
            .frame(minWidth: 640)
            Divider()
            Inspector(m: m)
                .frame(width: 310)
        }
        .sheet(isPresented: $askPreset) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save as your own template").font(.headline)
                Text("Saves the whole design (photo, background, text and colours) so you can start from it next time.")
                    .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("Name, e.g. Kingdom Altar – Night", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { askPreset = false }
                    Button("Save") {
                        m.savePreset(presetName)
                        presetName = ""
                        askPreset = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
    }
}

// MARK: - sidebar

struct Sidebar: View {
    @ObservedObject var m: AppModel
    @Binding var askPreset: Bool

    var body: some View {
        List {
            Section("Templates") {
                ForEach(Template.allCases) { t in
                    Button { m.use(t) } label: {
                        Label(t.title, systemImage: t.symbol)
                            .fontWeight(m.design.template == t.title ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
            }
            Section("My templates") {
                if m.presets.isEmpty {
                    Text("None yet").foregroundColor(.secondary).font(.callout)
                }
                ForEach(m.presets, id: \.self) { p in
                    Button { m.openPreset(p) } label: { Label(p, systemImage: "star.fill") }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                        .contextMenu { Button("Delete \"\(p)\"", role: .destructive) { m.deletePreset(p) } }
                }
                Button { askPreset = true } label: { Label("Save current…", systemImage: "plus") }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 3)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - canvas

struct CanvasView: View {
    @ObservedObject var m: AppModel
    @State private var dragStart: Design?
    @State private var target: Target?
    @State private var dropping = false

    enum Target: Equatable {
        case block(UUID), subject
    }

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width / Design.W, g.size.height / Design.H)
            let w = Design.W * s, h = Design.H * s
            let ox = (g.size.width - w) / 2, oy = (g.size.height - h) / 2
            ZStack(alignment: .topLeading) {
                Group {
                    if let img = m.image {
                        Image(nsImage: img).resizable().interpolation(.high)
                    } else {
                        Color.black
                    }
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)

                if let i = m.selectedIndex {
                    let r = m.design.blocks[i].rect
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: r.width * s, height: r.height * s)
                        .offset(x: r.minX * s, y: r.minY * s)
                        .allowsHitTesting(false)
                }
                if !m.layout.faceRect.isNull && m.selected == nil && target == .subject {
                    let f = m.layout.faceRect
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.green.opacity(0.8), lineWidth: 2)
                        .frame(width: f.width * s, height: f.height * s)
                        .offset(x: f.minX * s, y: f.minY * s)
                        .allowsHitTesting(false)
                }
                if dropping {
                    RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.25))
                        .overlay(Text("Drop the photo").font(.title2.bold()).foregroundColor(.white))
                        .frame(width: w, height: h)
                }
                if m.design.subject.imagePath == nil && !dropping {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.rectangle.badge.plus").font(.system(size: 30))
                        Text("Drag a photo here, or click Choose photo").font(.callout)
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: w * 0.4, height: h)
                    .offset(x: w * 0.55)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(drag(scale: s))
            .offset(x: ox, y: oy)
            .onDrop(of: [.fileURL], isTargeted: $dropping) { items in
                guard let item = items.first else { return false }
                _ = item.loadObject(ofClass: URL.self) { url, _ in
                    if let u = url { DispatchQueue.main.async { m.setPerson(u) } }
                }
                return true
            }
        }
    }

    func drag(scale s: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragStart == nil {
                    dragStart = m.design
                    let p = CGPoint(x: v.startLocation.x / s, y: v.startLocation.y / s)
                    if let b = m.design.blocks.reversed().first(where: { $0.rect.contains(p) }) {
                        target = .block(b.id)
                        m.selected = b.id
                    } else if !m.layout.subjectRect.isNull && m.layout.subjectRect.contains(p) {
                        target = .subject
                        m.selected = nil
                    } else {
                        target = nil
                        m.selected = nil
                    }
                }
                guard let start = dragStart, let t = target else { return }
                let dx = Double(v.translation.width / s), dy = Double(v.translation.height / s)
                var d = start
                switch t {
                case .subject:
                    d.subject.centerX = start.subject.centerX + dx / Double(Design.W)
                    d.subject.bottom = start.subject.bottom + dy / Double(Design.H)
                case .block(let id):
                    if let i = d.blocks.firstIndex(where: { $0.id == id }), d.blocks[i].style != .band {
                        d.blocks[i].x = start.blocks[i].x + dx
                        d.blocks[i].y = start.blocks[i].y + dy
                    } else if let i = d.blocks.firstIndex(where: { $0.id == id }) {
                        d.blocks[i].y = start.blocks[i].y + dy
                    }
                }
                m.design = d
            }
            .onEnded { _ in
                dragStart = nil
                if target == .subject {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if dragStart == nil { target = nil } }
                } else {
                    target = nil
                }
            }
    }
}

// MARK: - options + phone check

struct OptionsRow: View {
    @ObservedObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("4 OPTIONS").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            HStack(spacing: 10) {
                ForEach(0..<m.options.count, id: \.self) { i in
                    let o = m.options[i]
                    Button {
                        m.design = o.2
                        m.status = "Using \"\(o.0)\""
                    } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: o.1).resizable().aspectRatio(16 / 9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(i == 0 ? Color.accentColor : Color.clear, lineWidth: 2))
                            Text(o.0).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 190)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PhoneCheck: View {
    @ObservedObject var m: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ON A PHONE").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                if let img = m.image {
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: Checks.phoneWidth * 0.62, height: Checks.phoneWidth * 0.62 * 9 / 16)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Actual phone size").font(.caption2).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("CHECKS").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                ForEach(m.checks) { c in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: c.level == .good ? "checkmark.circle.fill" : c.level == .warn ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                            .foregroundColor(c.level == .good ? .green : c.level == .warn ? .orange : .yellow)
                        Text(c.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(width: 250, alignment: .leading)
        }
    }
}

struct BottomBar: View {
    @ObservedObject var m: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Text(m.status).font(.callout).foregroundColor(.secondary).lineLimit(1)
            Spacer()
            if m.hasDate {
                Button { m.exportWeek() } label: { Label("Export 7 days…", systemImage: "calendar.badge.plus") }
            }
            Button { m.copyToClipboard() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button { m.export() } label: { Label("Export…", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("e", modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }
}
