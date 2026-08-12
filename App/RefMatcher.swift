import Foundation

/// Cherche si un son de déploiement connu est PRÉSENT dans ce qu'on a capté.
///
/// C'est une mesure asymétrique, et c'est ce qui la distingue d'une simple
/// corrélation : on vérifie que là où la référence a de l'énergie, la capture
/// en a aussi. Tout ce que la capture contient EN PLUS — une sorcière qui
/// frappe, des squelettes qui marchent, une boule de feu — est ignoré au lieu
/// de pénaliser le score.
enum RefMatcher {

    struct Hit {
        let refCard: String     // nom brut du dossier, ex. "hog_rider"
        let card: Card?
        let score: Double       // 0 à 1
        let runnerUp: String
    }

    static var isReady: Bool { !SoundRefs.all.isEmpty }

    /// Empreinte d'une référence, pour l'afficher à côté d'une capture.
    static func frames(for refCard: String) -> [[UInt8]]? {
        SoundRefs.all.first { $0.card == refCard }?.frames
    }

    /// Résultats mis en cache : comparer une capture aux 190 références
    /// est coûteux, et la vue se redessine souvent.
    nonisolated(unsafe) private static var cache: [String: Hit] = [:]

    static func clearCache() { cache.removeAll() }

    static func cachedBest(key: String, capture: [[UInt8]]) -> Hit? {
        if let c = cache[key] { return c }
        guard let h = best(in: capture) else { return nil }
        cache[key] = h
        if cache.count > 200 { cache.removeAll() }
        return h
    }

    /// Correspondance dossier → carte du catalogue, calculée une fois.
    static let cardByRef: [String: Card] = {
        var map: [String: Card] = [:]
        for r in SoundRefs.all where map[r.card] == nil {
            let plain = r.card.replacingOccurrences(of: "_", with: " ")
            if let hit = CardCatalog.match(plain), hit.score >= 0.8 {
                map[r.card] = hit.card
            }
        }
        return map
    }()

    /// Taux de présence de `ref` dans `capture`, au meilleur alignement.
    private static func presence(_ capture: [[UInt8]], _ ref: [[UInt8]]) -> Double {
        guard !ref.isEmpty, !capture.isEmpty,
              let bands = ref.first?.count, bands > 0 else { return 0 }

        // Cases actives de la référence : celles qui portent le son
        var active: [(Int, Int, Double)] = []
        for (t, row) in ref.enumerated() {
            for b in 0..<min(bands, row.count) where row[b] > 40 {
                active.append((t, b, Double(row[b]) / 255.0))
            }
        }
        guard active.count >= 20 else { return 0 }

        var best = 0.0
        let maxShift = max(0, capture.count - ref.count)
        for shift in 0...max(0, maxShift) {
            var matched = 0.0, total = 0.0
            for (t, b, w) in active {
                let i = t + shift
                guard i < capture.count, b < capture[i].count else { continue }
                let got = Double(capture[i][b]) / 255.0
                // La capture doit être au moins aussi forte que la référence
                matched += w * min(1.0, got / max(w, 0.05))
                total += w
            }
            guard total > 0 else { continue }
            best = max(best, matched / total)
        }
        return best
    }

    /// Meilleure carte trouvée dans la capture.
    static func best(in capture: [[UInt8]],
                     restrictedTo pool: Set<String>? = nil) -> Hit? {
        guard isReady, capture.count >= 20 else { return nil }

        var scores: [String: Double] = [:]
        for r in SoundRefs.all {
            if let pool, !pool.contains(r.card) { continue }
            let s = presence(capture, r.frames)
            if s > (scores[r.card] ?? 0) { scores[r.card] = s }
        }
        guard !scores.isEmpty else { return nil }

        let sorted = scores.sorted { $0.value > $1.value }
        let top = sorted[0]
        var runner = ""
        if sorted.count > 1 {
            let s = sorted[1]
            let n = cardByRef[s.key]?.name
                ?? s.key.replacingOccurrences(of: "_", with: " ")
            runner = "\(n) \(Int(s.value * 100))%"
        }
        return Hit(refCard: top.key,
                   card: cardByRef[top.key],
                   score: top.value,
                   runnerUp: runner)
    }
}
