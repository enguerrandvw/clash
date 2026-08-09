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

    /// Distance entre deux séquences de trames. Plus c'est bas, plus ça se ressemble.
    private static func distance(_ a: [[UInt8]], _ b: [[UInt8]]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 1 }
        var total = 0.0, count = 0
        for i in 0..<n {
            let ra = a[i], rb = b[i]
            let m = min(ra.count, rb.count)
            for j in 0..<m {
                total += abs(Double(ra[j]) - Double(rb[j]))
                count += 1
            }
        }
        guard count > 0 else { return 1 }
        return total / Double(count) / 255.0
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
                     score: max(0, 1 - bestDist * 2.2),
                     file: bestRef.file)
    }
}
