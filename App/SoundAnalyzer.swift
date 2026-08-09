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
        let signature: [UInt8]   // spectre au moment de l'impulsion
        var myElixirBefore: Int
        var myElixirAfter: Int
        var attribution: String  // "moi", "adverse", ou "?"
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

    /// Ajoute les trames reçues et cherche les impulsions.
    func ingest(_ data: [UInt8], bands: Int, myElixir: Int) {
        guard bands > 0 else { return }
        let count = data.count / bands
        guard count > 0 else { return }

        for i in 0..<count {
            let frame = Array(data[(i * bands)..<((i + 1) * bands)])
            frames.append(frame)
            detect(frame, myElixir: myElixir)
        }
        if frames.count > maxFrames {
            frames.removeFirst(frames.count - maxFrames)
        }

        // Une impulsion en attente : on regarde si l'élixir a chuté depuis
        if var p = pendingOnset, Date().timeIntervalSince(p.at) > 0.6 {
            p.myElixirAfter = myElixir
            let drop = p.myElixirBefore - p.myElixirAfter
            p.attribution = drop >= 1 ? "moi (-\(drop))" : "adverse"
            onPulse?(p.attribution)
            onsets.insert(p, at: 0)
            if onsets.count > 30 { onsets.removeLast() }
            pendingOnset = nil
        }
    }

    private func detect(_ frame: [UInt8], myElixir: Int) {
        let e = frame.reduce(0.0) { $0 + Double($1) } / Double(frame.count)
        energy = e

        // Référence : moyenne des 12 trames précédentes (environ 0,3 s)
        let history = frames.suffix(13).dropLast()
        guard history.count >= 8 else { return }
        let base = history.reduce(0.0) { acc, f in
            acc + f.reduce(0.0) { $0 + Double($1) } / Double(f.count)
        } / Double(history.count)

        let jump = e - base
        let now = Date()
        guard jump > threshold,
              now.timeIntervalSince(lastOnset) > 0.35,
              pendingOnset == nil else { return }

        lastOnset = now
        onPulse?("…")
        pendingOnset = Onset(at: now, strength: jump, signature: frame,
                             myElixirBefore: myElixir, myElixirAfter: myElixir,
                             attribution: "…")
    }

    func reset() {
        frames.removeAll()
        onsets.removeAll()
        pendingOnset = nil
    }
}
