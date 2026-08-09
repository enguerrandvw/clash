import Foundation

/// Compare la forme spectrale d'une impulsion aux empreintes des sons
/// de déploiement extraits du jeu, et retourne la carte la plus proche.
enum SoundMatcher {

    struct Match {
        let refCard: String     // nom du dossier, ex. "card_common_knight"
        let card: Card?         // carte reconnue dans notre catalogue
        let score: Double       // 0 à 1, plus c'est haut mieux c'est
        let file: String
    }

    /// Retire le préfixe de rareté : "card_common_hog_rider" → "hog rider"
    static func plainName(_ folder: String) -> String {
        var s = folder
        for p in ["card_champion_", "card_legendary_", "card_epic_",
                  "card_rare_", "card_common_", "card_"] {
            if s.hasPrefix(p) { s = String(s.dropFirst(p.count)); break }
        }
        return s.replacingOccurrences(of: "_", with: " ")
    }

    /// Table dossier → carte, construite une seule fois.
    static let cardByFolder: [String: Card] = {
        var map: [String: Card] = [:]
        for ref in SoundRefs.all where map[ref.card] == nil {
            if let hit = CardCatalog.match(plainName(ref.card)), hit.score >= 0.8 {
                map[ref.card] = hit.card
            }
        }
        return map
    }()

    /// Corrélation entre deux séquences. Elle juge la FORME du spectre
    /// et non les valeurs absolues : deux sons identiques joués à des
    /// volumes différents restent parfaitement corrélés.
    /// Retourne une distance : 0 = identique, 1 = sans rapport.
    private static func distance(_ a: [[UInt8]], _ b: [[UInt8]]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 1 }

        var xs: [Double] = [], ys: [Double] = []
        for i in 0..<n {
            let ra = a[i], rb = b[i]
            let m = min(ra.count, rb.count)
            for j in 0..<m {
                xs.append(Double(ra[j]))
                ys.append(Double(rb[j]))
            }
        }
        guard xs.count >= 16 else { return 1 }

        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        var num = 0.0, dx = 0.0, dy = 0.0
        for k in 0..<xs.count {
            let a0 = xs[k] - mx, b0 = ys[k] - my
            num += a0 * b0
            dx += a0 * a0
            dy += b0 * b0
        }
        guard dx > 1e-6, dy > 1e-6 else { return 1 }
        let r = num / (dx.squareRoot() * dy.squareRoot())
        return (1 - r) / 2          // r = 1 → 0 ; r = -1 → 1
    }

    /// Cherche la meilleure correspondance. `pool` limite aux cartes plausibles.
    static func best(for frames: [[UInt8]],
                     restrictedTo pool: Set<String>? = nil) -> Match? {
        guard !frames.isEmpty, !SoundRefs.all.isEmpty else { return nil }

        var bestRef: SoundRef?
        var bestDist = Double.greatestFiniteMagnitude

        for ref in SoundRefs.all {
            if let pool, !pool.contains(ref.card) { continue }
            // On teste aussi un décalage d'une trame : l'impulsion n'est pas
            // forcément détectée exactement au même instant que dans la référence.
            for shift in 0...1 {
                let sliced = Array(frames.dropFirst(shift))
                guard sliced.count >= 4 else { continue }
                let d = distance(sliced, ref.frames)
                if d < bestDist { bestDist = d; bestRef = ref }
            }
        }

        guard let bestRef else { return nil }
        return Match(refCard: bestRef.card,
                     card: cardByFolder[bestRef.card],
                     score: max(0, 1 - bestDist * 2.0),
                     file: bestRef.file)
    }

    /// Les `n` meilleurs candidats, pour voir si la bonne carte est au moins
    /// dans le peloton de tête.
    static func top(_ n: Int, for frames: [[UInt8]]) -> [Match] {
        guard !frames.isEmpty, !SoundRefs.all.isEmpty else { return [] }

        var scored: [(SoundRef, Double)] = []
        for ref in SoundRefs.all {
            var best = Double.greatestFiniteMagnitude
            for shift in 0...1 {
                let sliced = Array(frames.dropFirst(shift))
                guard sliced.count >= 4 else { continue }
                best = min(best, distance(sliced, ref.frames))
            }
            if best < .greatestFiniteMagnitude { scored.append((ref, best)) }
        }
        scored.sort { $0.1 < $1.1 }

        // Une seule entrée par carte : les variantes d'un même son
        // ne doivent pas occuper tout le classement.
        var seen = Set<String>()
        var out: [Match] = []
        for (ref, d) in scored {
            if seen.contains(ref.card) { continue }
            seen.insert(ref.card)
            out.append(Match(refCard: ref.card,
                             card: cardByFolder[ref.card],
                             score: max(0, 1 - d * 2.0),
                             file: ref.file))
            if out.count >= n { break }
        }
        return out
    }
}
