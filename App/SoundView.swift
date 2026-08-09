import SwiftUI

// Écran d'écoute : spectrogramme en direct et journal des impulsions détectées.
struct SoundView: View {
    @ObservedObject private var sound = SoundAnalyzer.shared
    @ObservedObject private var capture = CaptureBridge.shared

    var body: some View {
        VStack(spacing: 14) {

            Text("Analyse sonore")
                .font(.headline)

            // Spectrogramme : le temps va de gauche à droite,
            // les graves en bas, les aigus en haut.
            Spectrogram(frames: sound.frames)
                .frame(height: 150)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)

            HStack {
                Text("Énergie \(Int(sound.energy))")
                Spacer()
                Text("Ton élixir : \(capture.myElixir)")
            }
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sensibilité : \(Int(sound.threshold))")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $sound.threshold, in: 5...60, step: 1)
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Text("Seuil de certitude : \(Int(sound.minScore * 100)) %")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $sound.minScore, in: 0.2...0.9, step: 0.05)
            }
            .padding(.horizontal, 20)

            Divider()

            Text(SoundMatcher.selfTest())
                .font(.caption2)
                .foregroundStyle(.yellow)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Text("\(SoundRefs.all.count) sons de référence · \(SoundMatcher.cardByFolder.count) reliés à une carte")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Impulsions détectées : \(sound.onsets.count)")
                .font(.subheadline.weight(.medium))

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(sound.onsets) { o in
                        VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(o.at, style: .time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(o.attribution)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(o.attribution.hasPrefix("moi")
                                                 ? .teal : .orange)
                            Spacer()
                            Text("force \(Int(o.strength))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        // Les deux candidats suivants : la bonne carte
                        // est-elle au moins dans le peloton de tête ?
                        if o.top.count > 1 {
                            Text(o.top.dropFirst().map {
                                "\($0.card?.name ?? SoundMatcher.plainName($0.refCard)) \(Int($0.score * 100))%"
                            }.joined(separator: "  ·  "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.gray.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 20)
            }

            Button("Effacer") { sound.reset() }
                .font(.footnote)
                .padding(.bottom, 16)
        }
        .padding(.top, 16)
    }
}

// Dessine le spectrogramme à partir des trames reçues
struct Spectrogram: View {
    let frames: [[UInt8]]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard !frames.isEmpty, let bands = frames.first?.count, bands > 0
                else { return }
                let cw = size.width / CGFloat(max(frames.count, 1))
                let chh = size.height / CGFloat(bands)
                for (t, frame) in frames.enumerated() {
                    for (b, v) in frame.enumerated() {
                        // On étire le haut de l'échelle : les valeurs utiles
                        // se situent entre 150 et 255 après normalisation.
                        let level = max(0, (Double(v) - 140) / 115)
                        guard level > 0.04 else { continue }
                        let color = Color(hue: 0.72 - 0.62 * level,
                                          saturation: 0.95,
                                          brightness: min(1, 0.2 + level))
                        let rect = CGRect(x: CGFloat(t) * cw,
                                          y: size.height - CGFloat(b + 1) * chh,
                                          width: max(cw, 1), height: chh + 0.5)
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
