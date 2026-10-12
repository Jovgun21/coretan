import SwiftUI

struct InkPreset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var tool: InkToolKind
    var color: InkColor
    var width: Float
}

/// Pen toolbar: tool, colour, width, presets. Everything here changes live state,
/// nothing is decorative.
struct PenPalette: View {
    @Binding var tool: EditorTool
    @Binding var color: UIColor
    @Binding var width: CGFloat
    @Binding var fingerDrawing: Bool
    @State private var presets: [InkPreset] = PenPalette.loadPresets()
    @State private var showCustomColor = false

    private let swatches: [UIColor] = [
        .black, .darkGray, .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemTeal, .systemBlue, .systemIndigo, .systemPurple,
        .systemPink, .brown
    ]

    var body: some View {
        HStack(spacing: 12) {
            toolButton(.pen(.pen, InkColor.from(color), Float(width)), icon: "pencil.tip", label: "Pena")
            toolButton(.pen(.highlighter, InkColor.from(color), Float(width * 4 + 6)), icon: "highlighter", label: "Stabilo")
            toolButton(.pen(.pencil, InkColor.from(color), Float(width)), icon: "pencil", label: "Pensil")
            toolButton(.eraser(Float(width) * 3 + 6, .any), icon: "eraser", label: "Hapus")
            toolButton(.lasso, icon: "lasso", label: "Lasso")
            toolButton(.move, icon: "arrow.up.and.down.and.arrow.left.and.right", label: "Pindah")

            Divider().frame(height: 26)

            ColorStrip(swatches: swatches, color: $color, showCustom: $showCustomColor)

            Slider(value: $width, in: 0.5...20)
                .frame(width: 120)
                .accessibilityLabel("Ketebalan")

            Toggle(isOn: $fingerDrawing) { Image(systemName: "hand.point.up.left") }
                .toggleStyle(.button)
                .help("Gambar pakai jari")

            Menu {
                ForEach(presets) { p in
                    Button(p.name) { apply(p) }
                }
                Divider()
                Button("Simpan preset sekarang") { savePreset() }
            } label: { Image(systemName: "bookmark") }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .sheet(isPresented: $showCustomColor) {
            ColorPicker("Warna kustom", selection: Binding(
                get: { Color(color) },
                set: { color = UIColor($0) }))
                .padding()
        }
    }

    @ViewBuilder
    private func toolButton(_ t: EditorTool, icon: String, label: String) -> some View {
        Button {
            tool = t
        } label: {
            Image(systemName: icon).font(.system(size: 17))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive(t) ? .white : .primary)
        .background(isActive(t) ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
        .help(label)
    }

    private func isActive(_ t: EditorTool) -> Bool {
        switch (tool, t) {
        case (.pen(let a, _, _), .pen(let b, _, _)): return a == b
        case (.eraser, .eraser): return true
        case (.lasso, .lasso): return true
        case (.move, .move): return true
        default: return false
        }
    }

    private func apply(_ p: InkPreset) {
        tool = .pen(p.tool, p.color, p.width)
        color = p.color.ui
        width = CGFloat(p.width)
    }

    private func savePreset() {
        let p = InkPreset(name: "Preset \(presets.count + 1)",
                          tool: currentToolKind, color: InkColor.from(color), width: Float(width))
        presets.append(p); persist()
    }

    private var currentToolKind: InkToolKind {
        if case .pen(let k, _, _) = tool { return k }
        return .pen
    }

    private static let presetKey = "coretan.pen.presets"

    static func loadPresets() -> [InkPreset] {
        guard let d = UserDefaults.standard.data(forKey: presetKey),
              let list = try? JSONDecoder().decode([InkPreset].self, from: d)
        else { return [] }
        return list
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(d, forKey: Self.presetKey)
        }
    }
}

struct ColorStrip: View {
    let swatches: [UIColor]
    @Binding var color: UIColor
    @Binding var showCustom: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(swatches.prefix(8).enumerated()), id: \.offset) { _, c in
                Circle()
                    .fill(Color(c))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(.white, lineWidth: color == c ? 2.5 : 0))
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .onTapGesture { color = c }
            }
            Button { showCustom = true } label: {
                Image(systemName: "paintpalette").font(.system(size: 15))
            }.buttonStyle(.plain)
        }
    }
}
