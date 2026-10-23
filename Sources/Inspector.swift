import SwiftUI

func colorBinding(_ b: Binding<RGBA>) -> Binding<Color> {
    Binding(get: { Color(nsColor: b.wrappedValue.ns) }, set: { b.wrappedValue = RGBA(NSColor($0)) })
}

struct Inspector: View {
    @ObservedObject var m: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                photo
                Divider()
                textSection
                Divider()
                background
                if m.hasDate {
                    Divider()
                    dateSection
                }
            }
            .padding(16)
        }
    }

    // MARK: photo

    var photo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Header(title: "PHOTO", symbol: "person.fill")
            HStack {
                Button("Choose photo…") { m.choosePicture(background: false) }
                if m.design.subject.imagePath != nil {
                    Button("Remove") { m.design.subject.imagePath = nil }
                }
            }
            if m.design.subject.imagePath != nil {
                Toggle("Remove photo background", isOn: $m.design.subject.cutout)
                if #unavailable(macOS 14.0) {
                    Text("Needs macOS 14 or newer.").font(.caption).foregroundColor(.secondary)
                }
                LabeledSlider(title: "Size", value: $m.design.subject.height, range: 0.5...1.5)
                Toggle("Flip left–right", isOn: $m.design.subject.flip)
                Button {
                    m.keepOffFace()
                } label: { Label("Keep text off face", systemImage: "face.smiling") }
                Text("Drag the person or any text on the thumbnail to move it. The face is never filtered or changed.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: text

    var textSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Header(title: "TEXT", symbol: "textformat")
                Spacer()
                Button { m.addText() } label: { Image(systemName: "plus") }.help("Add text")
                Button { m.deleteSelected() } label: { Image(systemName: "trash") }.help("Delete selected text").disabled(m.selected == nil)
            }
            Picker("", selection: $m.selected) {
                Text("Choose…").tag(UUID?.none)
                ForEach(m.design.blocks) { b in Text(b.name).tag(UUID?.some(b.id)) }
            }
            .labelsHidden()
            if let i = m.selectedIndex {
                BlockEditor(m: m, i: i)
            } else {
                Text("Click any text on the thumbnail to edit it.").font(.callout).foregroundColor(.secondary)
            }
        }
    }

    // MARK: background

    var background: some View {
        VStack(alignment: .leading, spacing: 10) {
            Header(title: "BACKGROUND", symbol: "photo")
            Picker("Style", selection: $m.design.background.kind) {
                ForEach(BackgroundKind.allCases) { k in Text(k.title).tag(k) }
            }
            switch m.design.background.kind {
            case .solid:
                ColorPicker("Colour", selection: colorBinding($m.design.background.color1), supportsOpacity: false)
            case .gradient, .clouds:
                ColorPicker("Dark colour", selection: colorBinding($m.design.background.color1), supportsOpacity: false)
                ColorPicker("Light colour", selection: colorBinding($m.design.background.color2), supportsOpacity: false)
                if m.design.background.kind == .clouds {
                    Button("New clouds") { m.design.background.seed += 1 }
                }
            case .image:
                Button("Choose picture…") { m.choosePicture(background: true) }
            }
            LabeledSlider(title: "Darken", value: $m.design.background.darken, range: 0...0.85)
            LabeledSlider(title: "Dark edges", value: $m.design.background.vignette, range: 0...0.9)
            Toggle("Light behind the person", isOn: Binding(
                get: { m.design.background.glow != nil },
                set: { m.design.background.glow = $0 ? RGBA(hex: 0xC4161C) : nil }))
            if m.design.background.glow != nil {
                ColorPicker("Light colour", selection: colorBinding(Binding(
                    get: { m.design.background.glow ?? .red },
                    set: { m.design.background.glow = $0 })), supportsOpacity: false)
                LabeledSlider(title: "Strength", value: $m.design.background.glowStrength, range: 0.05...1)
            }
        }
    }

    var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Header(title: "DATE", symbol: "calendar")
            DatePicker("Day", selection: $m.design.date, displayedComponents: .date)
            Text("Only the date line changes. \"Export 7 days\" makes one for each day of the week.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BlockEditor: View {
    @ObservedObject var m: AppModel
    let i: Int

    var body: some View {
        if i < m.design.blocks.count {
            let b = $m.design.blocks[i]
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: b.name).textFieldStyle(.roundedBorder)
                if b.wrappedValue.dateFormat != nil {
                    Picker("Date as", selection: Binding(get: { b.wrappedValue.dateFormat ?? .dayDate }, set: { b.wrappedValue.dateFormat = $0 })) {
                        ForEach(DateFormat.allCases) { f in Text(f.title).tag(f) }
                    }
                    Button("Type it instead") { b.wrappedValue.text = b.wrappedValue.dateFormat?.format(m.design.date) ?? ""; b.wrappedValue.dateFormat = nil }
                        .font(.caption)
                } else {
                    TextEditor(text: b.text)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(height: 78)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    Text("One line per row. Put [brackets] around words to colour them.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Picker("Font", selection: b.font) {
                    ForEach(Fonts.all, id: \.name) { f in Text(f.title).tag(f.name) }
                }
                LabeledSlider(title: "Max size", value: b.maxSize, range: 24...300, format: "%.0f")
                HStack {
                    ColorPicker("Text", selection: colorBinding(b.color))
                    ColorPicker("[Words]", selection: colorBinding(b.accent), supportsOpacity: false)
                }
                LabeledSlider(title: "Outline", value: b.stroke, range: 0...16, format: "%.0f")
                if b.wrappedValue.stroke > 0 {
                    ColorPicker("Outline colour", selection: colorBinding(b.strokeColor), supportsOpacity: false)
                }
                Toggle("Shadow", isOn: b.shadow)
                Picker("Look", selection: b.style) {
                    ForEach(LineStyle.allCases) { s in Text(s.title).tag(s) }
                }
                if b.wrappedValue.style != .plain {
                    ColorPicker("Box colour", selection: colorBinding(b.boxColor))
                }
                Picker("Align", selection: b.align) {
                    Image(systemName: "text.alignleft").tag(TextAlign.left)
                    Image(systemName: "text.aligncenter").tag(TextAlign.center)
                    Image(systemName: "text.alignright").tag(TextAlign.right)
                }
                .pickerStyle(.segmented)
                LabeledSlider(title: "Line spacing", value: b.lineSpacing, range: 0.8...1.5)
                Toggle("ALL CAPITALS", isOn: b.uppercase)
            }
        }
    }
}

struct Header: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol).font(.caption.weight(.bold)).foregroundColor(.secondary)
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(String(format: format, value)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
