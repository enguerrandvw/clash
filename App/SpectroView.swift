import SwiftUI

/// Affiche une matrice bandes × tranches. Les graves en bas, le temps
/// de gauche à droite. Sombre = silence, clair = énergie.
struct SpectroView: View {
    let frames: [[UInt8]]
    var height: CGFloat = 120

    var body: some View {
        Canvas { ctx, size in
            guard !frames.isEmpty, let bands = frames.first?.count, bands > 0
            else { return }
            let cw = size.width / CGFloat(frames.count)
            let ch = size.height / CGFloat(bands)
            for (t, frame) in frames.enumerated() {
                for (b, v) in frame.enumerated() {
                    let level = Double(v) / 255.0
                    let color = Color(hue: 0.70 - 0.62 * level,
                                      saturation: level < 0.03 ? 0 : 0.95,
                                      brightness: level < 0.03 ? 0.08 : (0.15 + 0.85 * level))
                    ctx.fill(Path(CGRect(x: CGFloat(t) * cw,
                                         y: size.height - CGFloat(b + 1) * ch,
                                         width: max(cw, 1), height: ch + 0.5)),
                             with: .color(color))
                }
            }
        }
        .frame(height: height)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Quelques chiffres pour savoir si la fenêtre contient vraiment du son.
struct SpectroStats {
    let filled: Double      // proportion de valeurs non nulles
    let peakFrame: Int      // tranche la plus énergique
    let contrast: Double    // écart entre les tranches fortes et faibles

    init(_ frames: [[UInt8]]) {
        guard !frames.isEmpty, let bands = frames.first?.count, bands > 0 else {
            filled = 0; peakFrame = 0; contrast = 0; return
        }
        var nonZero = 0, total = 0
        var energies: [Double] = []
        for f in frames {
            var e = 0.0
            for v in f {
                total += 1
                if v > 12 { nonZero += 1 }
                e += Double(v)
            }
            energies.append(e / Double(max(1, f.count)))
        }
        filled = Double(nonZero) / Double(max(1, total))
        peakFrame = energies.firstIndex(of: energies.max() ?? 0) ?? 0
        let lo = energies.min() ?? 0, hi = energies.max() ?? 0
        contrast = hi - lo
    }

    var summary: String {
        String(format: "rempli %.0f %% · pic tranche %d · contraste %.0f",
               filled * 100, peakFrame, contrast)
    }
}
