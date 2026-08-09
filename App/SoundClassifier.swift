import Foundation

/// Reconnaît une carte à partir du spectrogramme capté, à l'aide du petit
/// réseau entraîné à la compilation sur des sons volontairement bruités.
enum SoundClassifier {

    struct Result {
        let label: String       // nom brut, ex. "hog_rider" ou "__fond__"
        let card: Card?
        let confidence: Double  // 0 à 1
        let isBackground: Bool
        let runnersUp: String     // les deux hypothèses suivantes
    }

    static var isReady: Bool { !SoundModel.labels.isEmpty && SoundModel.w1.count > 0 }

    /// Correspondance étiquette → carte du catalogue, calculée une fois.
    static let cardByLabel: [String: Card] = {
        var map: [String: Card] = [:]
        for l in SoundModel.labels where l != "__fond__" {
            let plain = l.replacingOccurrences(of: "_", with: " ")
            if let hit = CardCatalog.match(plain), hit.score >= 0.8 {
                map[l] = hit.card
            }
        }
        return map
    }()

    /// `frames` : les trames captées (26 × 32 valeurs de 0 à 255).
    static func classify(_ frames: [[UInt8]]) -> Result? {
        guard isReady else { return nil }
        let bands = SoundModel.bands
        let need = SoundModel.windowFrames
        guard frames.count >= need / 2, frames.first?.count == bands else { return nil }

        // Complète ou tronque à la longueur attendue
        var f = frames
        while f.count < need { f.append(f.last ?? [UInt8](repeating: 0, count: bands)) }
        f = Array(f.prefix(need))

        // Regroupement temporel, identique à l'entraînement
        var x = [Float](repeating: 0, count: SoundModel.inputDim)
        let pool = SoundModel.pool
        for t in 0..<(need / pool) {
            for b in 0..<bands {
                var s: Float = 0
                for k in 0..<pool { s += Float(f[t * pool + k][b]) / 255.0 }
                x[t * bands + b] = s / Float(pool)
            }
        }

        // Normalisation
        for i in 0..<x.count { x[i] = (x[i] - SoundModel.mu[i]) / SoundModel.sd[i] }

        // Couche cachée avec activation ReLU
        let h = SoundModel.hidden
        var hid = [Float](repeating: 0, count: h)
        for j in 0..<h {
            var s = SoundModel.b1[j]
            for i in 0..<x.count { s += x[i] * SoundModel.w1[i * h + j] }
            hid[j] = max(0, s)
        }

        // Couche de sortie
        let n = SoundModel.labels.count
        var out = [Float](repeating: 0, count: n)
        for k in 0..<n {
            var s = SoundModel.b2[k]
            for j in 0..<h { s += hid[j] * SoundModel.w2[j * n + k] }
            out[k] = s
        }

        // Softmax
        let mx = out.max() ?? 0
        var exps = out.map { expf($0 - mx) }
        let sum = exps.reduce(0, +)
        if sum > 0 { for i in 0..<n { exps[i] /= sum } }

        let order = (0..<n).sorted { exps[$0] > exps[$1] }
        let best = order[0]
        let label = SoundModel.labels[best]

        let others = order.dropFirst().prefix(2).map {
            "\(SoundModel.labels[$0].replacingOccurrences(of: "_", with: " ")) \(Int(exps[$0] * 100))%"
        }.joined(separator: " · ")

        return Result(label: label,
                      card: cardByLabel[label],
                      confidence: Double(exps[best]),
                      isBackground: label == "__fond__",
                      runnersUp: others)
    }
}
