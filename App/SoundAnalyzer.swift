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
        var result: SoundClassifier.Result?
    }

    @Published var frames: [[UInt8]] = []      // spectres récents
    @Published var onsets: [Onset] = []
    @Published var energy: Double = 0
    @Published var threshold: Double = 22      // sensibilité, réglable
    @Published var minScore: Double = 0.55     // en dessous, on n'affirme rien

    // Diagnostic : ce que l'extension envoie réellement
    @Published var bandsSeen = 0
    @Published var classifyOK = 0
    @Published var classifyFail = 0

    /// Appelé à chaque impulsion : sert à faire clignoter la fenêtre flottante.
    var onPulse: ((String) -> Void)?

    private let maxFrames = 260                // environ 6 secondes
    private var lastOnset = Date.distantPast
    private var pendingOnset: Onset?
    private var levelHistory: [Double] = []
    private var pendingIndex: Int?
    private var capturing = false
    private var capture: [[UInt8]] = []     // trames suivant l'impulsion
    private var background: [Double] = []   // spectre moyen juste avant

    /// Ajoute les trames reçues et cherche les impulsions.
    func ingest(_ data: [UInt8], levels: [UInt8], bands: Int, myElixir: Int) {
        guard bands > 0 else { return }
        bandsSeen = bands
        let count = min(data.count / bands, max(levels.count, 1))
        guard count > 0 else { return }

        for i in 0..<count {
            let frame = Array(data[(i * bands)..<((i + 1) * bands)])
            frames.append(frame)
            let lvl = i < levels.count ? Double(levels[i]) : 0
            levelHistory.append(lvl)
            if levelHistory.count > maxFrames { levelHistory.removeFirst() }

            detect(level: lvl, myElixir: myElixir)

            // Une impulsion vient d'être repérée : on met de côté ses trames
            if capturing && capture.count < 26 { capture.append(frame) }
        }
        if frames.count > maxFrames {
            frames.removeFirst(frames.count - maxFrames)
        }

        // Une impulsion en attente : on regarde si l'élixir a chuté depuis
        if var p = pendingOnset, Date().timeIntervalSince(p.at) > 0.75,
           pendingIndex != nil {

            p.myElixirAfter = myElixir
            let drop = p.myElixirBefore - p.myElixirAfter

            // Les trames collectées après l'impulsion forment sa signature
            if capture.count >= 12 {
                p.signature = capture.first ?? []
                p.result = SoundClassifier.classify(capture)
                if p.result == nil { classifyFail += 1 } else { classifyOK += 1 }
            }
            capturing = false

            let r = p.result
            let sure = (r?.confidence ?? 0) >= minScore && !(r?.isBackground ?? true)
            let name = sure
                ? (r?.card?.name ?? (r?.label ?? "?").replacingOccurrences(of: "_", with: " "))
                : ((r?.isBackground ?? false) ? "bruit" : "?")
            let pct = Int((r?.confidence ?? 0) * 100)
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
        capturing = true
        capture.removeAll(keepingCapacity: true)

        // Fond sonore : moyenne des 6 trames précédant l'impulsion
        let prev = frames.suffix(7).dropLast()
        if let width = prev.first?.count, !prev.isEmpty {
            var acc = [Double](repeating: 0, count: width)
            for f in prev where f.count == width {
                for i in 0..<width { acc[i] += Double(f[i]) }
            }
            background = acc.map { $0 / Double(prev.count) }
        } else {
            background = []
        }
        pendingIndex = 0
        pendingOnset = Onset(at: now, strength: jump, signature: [],
                             myElixirBefore: myElixir, myElixirAfter: myElixir,
                             attribution: "…", result: nil)
    }

    func reset() {
        frames.removeAll()
        onsets.removeAll()
        pendingOnset = nil
        pendingIndex = nil
        levelHistory.removeAll()
        capturing = false
        capture.removeAll()
    }
}
