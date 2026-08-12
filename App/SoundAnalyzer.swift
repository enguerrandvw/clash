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
        var extra = ""
        var elixirTrace = ""
    }

    @Published var frames: [[UInt8]] = []      // spectres récents
    @Published var onsets: [Onset] = []
    @Published var energy: Double = 0
    @Published var threshold: Double = 22      // sensibilité, réglable
    @Published var minScore: Double = 0.55     // en dessous, on n'affirme rien

    // Diagnostic : ce que l'extension envoie réellement
    /// Dernière impulsion captée, quelle qu'en soit l'origine.
    /// Sert à l'enregistrement manuel : tu poses, puis tu enregistres.
    @Published var lastCapture: [[UInt8]] = []
    @Published var lastCaptureAt = Date.distantPast

    @Published var myPlays = 0
    // Où partent les détections qui ne deviennent pas des exemples
    @Published var rejectedNoEvent = 0
    /// Dernière baisse d'élixir constatée : sert aussi à attribuer les impulsions
    private var lastMyPlayAt = Date.distantPast
    private var lastMyPlayDrop = 0
    @Published var lastPlayInfo = "—"
    /// Dernière fenêtre traitée, pour inspection visuelle
    @Published var lastProcessed: [[UInt8]] = []
    @Published var lastRaw: [[UInt8]] = []
    @Published var lastAudio: [UInt8] = []
    /// Résultat de la recherche de motifs sur la dernière capture
    @Published var lastTemplateHit = "—"
    @Published var bandsSeen = 0
    /// Audio brut à 11025 Hz, quelques secondes glissantes
    private var pcmBuffer: [UInt8] = []
    private let pcmRate = 11025

    @Published var framesInBuffer = 0
    @Published var totalFrames = 0
    @Published var classifyOK = 0
    @Published var classifyFail = 0

    /// Appelé à chaque impulsion : sert à faire clignoter la fenêtre flottante.
    var onPulse: ((String) -> Void)?

    private let maxFrames = 320                // environ 6 secondes
    private var lastOnset = Date.distantPast
    private var pendingOnset: Onset?
    private var levelHistory: [Double] = []
    // Suivi direct de TA barre d'élixir : c'est elle qui dit que tu as posé.
    private var prevElixir = -1
    private var rawElixir: [Int] = []     // lectures brutes, avant stabilisation
    private var stableElixir = -1
    private var dropStart: Date?
    private var dropFrom = 0
    private var dropWindow: [[UInt8]] = []   // son capté au DÉBUT de la baisse
    private var dropAmbience: [[UInt8]] = [] // ambiance mesurée juste avant
    // Récolte différée : le son de la troupe arrive après le déploiement
    private var harvestAt: Date?
    private var harvestDrop = 0
    private var harvestAmbience: [[UInt8]] = []
    private var dropTo = 0
    private var recentElixir: [Int] = []  // historique court, pour retrouver le pic
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

            recentElixir.append(myElixir)
            if recentElixir.count > 20 { recentElixir.removeFirst() }

            detect(level: lvl, myElixir: myElixir)

            // Une impulsion vient d'être repérée : on met de côté ses trames
            if capturing && capture.count < 26 { capture.append(frame) }
        }
        if frames.count > maxFrames {
            frames.removeFirst(frames.count - maxFrames)
        }
        framesInBuffer = frames.count
        totalFrames += count

        // Une impulsion en attente : on regarde si l'élixir a chuté depuis
        if var p = pendingOnset, Date().timeIntervalSince(p.at) > 0.75,
           pendingIndex != nil {

            // La barre remonte pendant les 0,75 s d'attente : on retient
            // le point le plus bas atteint, pas la valeur du moment.
            p.myElixirAfter = min(myElixir, recentElixir.suffix(12).min() ?? myElixir)

            // Une seule source de vérité : la baisse détectée sur ta barre.
            // Si elle date de moins de 2 s, cette impulsion est la tienne.
            let recent = Date().timeIntervalSince(lastMyPlayAt) < 2.0
            let drop = recent ? lastMyPlayDrop : 0

            // Les trames collectées après l'impulsion forment sa signature
            if capture.count >= 12 {
                p.signature = capture.first ?? []
                p.result = SoundClassifier.classify(capture)
                if p.result == nil { classifyFail += 1 } else { classifyOK += 1 }
            }
            capturing = false

            lastCapture = capture
            lastCaptureAt = Date()

            // Mode apprentissage : si une carte est sélectionnée et que TON
            // élixir a baissé du bon montant, on enregistre l'empreinte.
            let learn = LearnedSounds.shared

            let r = p.result
            // Priorité aux sons appris sur l'appareil : même chaîne de calcul
            // à l'apprentissage et à la reconnaissance, donc pas d'écart possible.
            var name = "?"
            var pct = 0
            let treated = LearnedSounds.process(
                window: capture,
                ambience: Array(frames.suffix(60).prefix(20)))
            if let ref = RefMatcher.best(in: treated), ref.score > 0.35 {
                pct = Int(ref.score * 100)
                name = ref.card?.name
                    ?? ref.refCard.replacingOccurrences(of: "_", with: " ")
                p.extra = ref.runnerUp
            } else if let hit = learn.recognise(treated) {
                pct = Int(hit.score * 100)
                name = hit.score >= minScore ? hit.card.name : "?"
                p.extra = hit.runnerUp
            } else {
                let sure = (r?.confidence ?? 0) >= minScore && !(r?.isBackground ?? true)
                name = sure
                    ? (r?.card?.name ?? (r?.label ?? "?").replacingOccurrences(of: "_", with: " "))
                    : ((r?.isBackground ?? false) ? "bruit" : "?")
                pct = Int((r?.confidence ?? 0) * 100)
            }
            p.attribution = (drop >= 1 ? "moi (-\(drop)) " : "adverse ")
                + "· \(name) \(pct)%"
            p.elixirTrace = recent
                ? "ta carte · −\(lastMyPlayDrop) élixir"
                : "aucune baisse de ton élixir → adverse"

            onPulse?(p.attribution)
            onsets.insert(p, at: 0)
            if onsets.count > 30 { onsets.removeLast() }
            pendingOnset = nil
            pendingIndex = nil
        }
    }

    /// Surveille TA barre. Une baisse ne peut venir que d'une carte posée
    /// par toi : dès qu'elle se stabilise, on enregistre le son qui précède.
    /// Appelé à chaque paquet reçu, que l'audio ait bougé ou non.
    /// Reçoit l'audio brut décimé, pour pouvoir le réécouter ensuite.
    private var pcmCount = 0
    private var pcmStart: Date?
    /// Débit audio réellement reçu. Doit valoir ~11025 échantillons/s.
    @Published var pcmRateMeasured = 0

    func ingestPCM(_ samples: [UInt8]) {
        if pcmStart == nil { pcmStart = Date() }
        pcmCount += samples.count
        if let st = pcmStart {
            let dt = Date().timeIntervalSince(st)
            if dt > 1 { pcmRateMeasured = Int(Double(pcmCount) / dt) }
            if dt > 10 { pcmStart = Date(); pcmCount = 0 }
        }

        pcmBuffer.append(contentsOf: samples)
        let maxLen = pcmRate * 4
        if pcmBuffer.count > maxLen { pcmBuffer.removeFirst(pcmBuffer.count - maxLen) }
    }

    func observeElixir(_ raw: Int) {
        watchElixir(raw)
        harvestIfDue()
    }

    /// Récupère le son une fois la troupe déployée.
    private func harvestIfDue() {
        guard let due = harvestAt, Date() >= due else { return }
        harvestAt = nil

        // 160 trames ≈ 1,85 s : couvre le déploiement le plus lent
        let available = frames.count
        let raw = Array(frames.suffix(160))
        lastAudio = Array(pcmBuffer.suffix(pcmRate * 2))
        let treated = LearnedSounds.process(window: raw, ambience: harvestAmbience)
        harvestAmbience = []
        lastRaw = Array(raw.suffix(50))

        // Recherche des motifs de référence dans la capture brute
        if let hit = RefMatcher.best(in: raw) {
            let name = hit.card?.name
                ?? hit.refCard.replacingOccurrences(of: "_", with: " ")
            lastPlayInfo = "\(name) \(Int(hit.score * 100))%"
                + (hit.runnerUp.isEmpty ? "" : " · puis \(hit.runnerUp)")
        }

            lastTemplateHit = "\(name) \(Int(hit.score * 100))%"
                + (hit.runnersUp.isEmpty ? "" : " · puis \(hit.runnersUp)")
        } else {
            lastTemplateHit = "aucun motif"
        }
        lastProcessed = treated
        guard treated.count >= 30 else {
            rejectedNoEvent += 1
            lastPlayInfo = String(format: "−%d élixir · fenêtre trop courte (%d trames)",
                                  harvestDrop, treated.count)
            return
        }
        lastPlayInfo = String(format: "−%d élixir · capté · %d trames · bond %.1f dB · relief %d",
                              harvestDrop, available, LearnedSounds.lastJump,
                              Int(variation(treated)))
        // Les deux dernières secondes d'audio brut accompagnent l'exemple :
        // c'est ce qui permettra de le vérifier à l'oreille.
        let audio = Array(pcmBuffer.suffix(pcmRate * 2))
        LearnedSounds.shared.observeMyPlay(drop: harvestDrop, frames: treated, audio: audio)
    }

    private func watchElixir(_ raw: Int) {
        guard raw >= 0 else { return }

        // La barre se remplit en continu : le dernier segment franchit sans
        // cesse le seuil de détection. On n'accepte donc une nouvelle valeur
        // que si elle est confirmée par deux lectures sur les trois dernières.
        rawElixir.append(raw)
        if rawElixir.count > 3 { rawElixir.removeFirst() }
        guard rawElixir.count == 3 else { return }

        var counts: [Int: Int] = [:]
        for v in rawElixir { counts[v, default: 0] += 1 }
        guard let confirmed = counts.first(where: { $0.value >= 2 })?.key else { return }

        if stableElixir < 0 { stableElixir = confirmed; prevElixir = confirmed; return }
        guard confirmed != stableElixir else {
            closeDropIfSettled()
            return
        }
        let now = confirmed
        stableElixir = confirmed
        defer { prevElixir = now }

        if now < prevElixir {
            // La baisse commence, ou se poursuit sur plusieurs mesures
            if dropStart == nil {
                dropStart = Date()
                dropFrom = prevElixir
                // Le son du déploiement est ICI, au tout début de la baisse.
                // Une demi-seconde plus tard il est déjà passé.
                // 60 trames : les 20 premières servent de profil d'ambiance,
                // les 40 suivantes contiennent le son du déploiement.
                // Seule l'ambiance est prise ici. Le son de la troupe n'a
                // pas encore été joué : il arrive pendant le déploiement,
                // environ une seconde plus tard.
                dropAmbience = Array(frames.suffix(24).prefix(20))
                dropWindow = []
            }
            dropTo = now
            return
        }

        closeDropIfSettled()
    }

    /// Clôt une baisse en cours dès qu'elle ne progresse plus.
    private func closeDropIfSettled() {
        if let start = dropStart, Date().timeIntervalSince(start) > 0.5 {
            let drop = dropFrom - dropTo
            dropStart = nil
            // Une carte coûte au plus 9 : au-delà, c'est une erreur de lecture
            guard drop >= 1, drop <= 9 else { return }

            // On réutilise l'instantané pris au début de la baisse
            // On programme la récolte pour dans 1,9 s : le temps que la
            // troupe se déploie et fasse enfin son bruit.
            harvestAt = Date().addingTimeInterval(1.9)
            harvestDrop = drop
            harvestAmbience = dropAmbience
            dropAmbience = []
            let window: [[UInt8]] = []
            myPlays += 1
            lastMyPlayAt = Date()
            lastMyPlayDrop = drop
            lastPlayInfo = "−\(drop) élixir (\(dropFrom)→\(dropTo)) · écoute…"

            // C'est la BAISSE elle-même qui déclenche l'affichage.
            // Plus besoin qu'un son ait été détecté au bon moment.
            let tag = "moi · carte à \(drop) élixir"
            onPulse?(tag)

            var entry = Onset(at: Date(), strength: 0, signature: [],
                              myElixirBefore: dropFrom, myElixirAfter: dropTo,
                              attribution: tag, result: nil)
            entry.elixirTrace = "ton élixir \(dropFrom) → \(dropTo)"

            // Si un son exploitable vient de passer, on l'identifie au passage
            if window.count >= 20, let hit = LearnedSounds.shared.recognise(window) {
                entry.attribution = tag + " · \(hit.card.name) \(Int(hit.score * 100))%"
                entry.extra = hit.runnerUp
            }
            onsets.insert(entry, at: 0)
            if onsets.count > 30 { onsets.removeLast() }
        }
    }

    /// Écart-type moyen des trames : proche de zéro si le son est plat.
    private func variation(_ w: [[UInt8]]) -> Double {
        guard !w.isEmpty else { return 0 }
        var total = 0.0
        for f in w {
            guard !f.isEmpty else { continue }
            let m = f.reduce(0.0) { $0 + Double($1) } / Double(f.count)
            let v = f.reduce(0.0) { $0 + pow(Double($1) - m, 2) } / Double(f.count)
            total += v.squareRoot()
        }
        return total / Double(w.count)
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
        let before = max(myElixir, recentElixir.suffix(8).max() ?? myElixir)
        pendingOnset = Onset(at: now, strength: jump, signature: [],
                             myElixirBefore: before, myElixirAfter: myElixir,
                             attribution: "…", result: nil)
    }

    func reset() {
        frames.removeAll()
        onsets.removeAll()
        pendingOnset = nil
        pendingIndex = nil
        levelHistory.removeAll()
        recentElixir.removeAll()
        prevElixir = -1
        stableElixir = -1
        rawElixir.removeAll()
        dropStart = nil
        dropWindow = []
        dropAmbience = []
        harvestAt = nil
        harvestAmbience = []
        lastMyPlayAt = .distantPast
        capturing = false
        capture.removeAll()
    }
}
