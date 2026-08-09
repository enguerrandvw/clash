import SwiftUI

/// Reçoit le flux spectral de l'extension, l'accumule, et repère les
/// impulsions sonores — les moments où un son démarre brutalement.
@MainActor
final class SoundAnalyzer: ObservableObject {

    static let shared = SoundAnalyzer()

    struct Onset: Identifiable {
        let id = UUID()
        let at: Date
        let strength: Double
        var signature: [UInt8]   // spectre au moment de l'impulsion
        var myElixirBefore: Int
        var myElixirAfter: Int
        var attribution: String  // "moi", "adverse", ou "?"
        var match: SoundMatcher.Match?
    }

    @Published var frames: [[UInt8]] = []      // spectres récents
    @Published var onsets: [Onset] = []
    @Published var energy: Double = 0
    @Published var threshold: Double = 22      // sensibilité, réglable

    /// Appelé à chaque impulsion : sert à faire clignoter la fenêtre flottante.
    var onPulse: ((String) -> Void)?

    private let maxFrames = 260                // environ 6 secondes
    private var lastOnset = Date.distantPast
    private var pendingOnset: Onset?
    private var levelHistory: [Double] = []
    private var pendingIndex: Int?

    /// Ajoute les trames reçues et cherche les impulsions.
    func ingest(_ data: [UInt8], levels: [UInt8], bands: Int, myElixir: Int) {
        guard bands > 0 else { return }
        let count = min(data.count / bands, max(levels.count, 1))
        guard count > 0 else { return }

        for i in 0..<count {
            let frame = Array(data[(i * bands)..<((i + 1) * bands)])
            frames.append(frame)
            let lvl = i < levels.count ? Double(levels[i]) : 0
            levelHistory.append(lvl)
            if levelHistory.count > maxFrames { levelHistory.removeFirst() }
            detect(level: lvl, myElixir: myElixir)
        }
        if frames.count > maxFrames {
            frames.removeFirst(frames.count - maxFrames)
        }

        // Une impulsion en attente : on regarde si l'élixir a chuté depuis
        if var p = pendingOnset, Date().timeIntervalSince(p.at) > 0.6,
           let idx = pendingIndex {

            p.myElixirAfter = myElixir
            let drop = p.myElixirBefore - p.myElixirAfter

            // Les 8 trames suivant l'impulsion forment sa signature
            let end = min(frames.count, idx + 8)
            if idx < end {
                let seq = Array(frames[idx..<end])
                p.signature = seq.first ?? []
                p.match = SoundMatcher.best(for: seq)
            }

            let name = p.match?.card?.name
                ?? p.match.map { SoundMatcher.plainName($0.refCard) }
                ?? "inconnu"
            let pct = Int((p.match?.score ?? 0) * 100)
            p.attribution = (drop >= 1 ? "moi (-\(drop)) " : "adverse ")
                + "· \(name) \(pct)%"

            onPulse?(p.attribution)
            onsets.insert(p, at: 0)
            if onsets.count > 30 { onsets.removeLast() }
            pendingOnset = nil
            pendingIndex = nil
        }
    }

    private func detect(level: Double, myElixir: Int) {
        energy = level

        // Référence : moyenne des 12 trames précédentes (environ 0,3 s)
        let history = levelHistory.suffix(13).dropLast()
        guard history.count >= 8 else { return }
        let base = history.reduce(0, +) / Double(history.count)

        let jump = level - base
        let now = Date()
        guard jump > threshold,
              now.timeIntervalSince(lastOnset) > 0.35,
              pendingOnset == nil else { return }

        lastOnset = now
        onPulse?("…")
        // On note l'indice de départ : la reconnaissance a besoin des
        // 8 trames qui SUIVENT l'impulsion, pas encore reçues.
        pendingIndex = frames.count - 1
        pendingOnset = Onset(at: now, strength: jump, signature: [],
                             myElixirBefore: myElixir, myElixirAfter: myElixir,
                             attribution: "…", match: nil)
    }

    func reset() {
        frames.removeAll()
        onsets.removeAll()
        pendingOnset = nil
        pendingIndex = nil
        levelHistory.removeAll()
    }
}
