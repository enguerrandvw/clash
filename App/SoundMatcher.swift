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

    /// Distance minimale entre une capture et une référence, en essayant
    /// plusieurs décalages : l'impulsion n'est pas repérée exactement
    /// au même instant que dans le fichier de référence.
    private static func bestDistance(_ frames: [[UInt8]], _ ref: SoundRef) -> Double {
        var best = Double.greatestFiniteMagnitude
        for shift in 0...3 {
            let sliced = Array(frames.dropFirst(shift))
            guard sliced.count >= 4 else { continue }
            best = min(best, distance(sliced, ref.frames))
        }
        return best
    }

    /// La meilleure correspondance.
    static func best(for frames: [[UInt8]]) -> Match? {
        top(1, for: frames).first
    }

    /// Les `n` meilleurs candidats, une seule entrée par carte.
    static func top(_ n: Int, for frames: [[UInt8]]) -> [Match] {
        guard !frames.isEmpty, !SoundRefs.all.isEmpty else { return [] }

        var scored: [(SoundRef, Double)] = []
        for ref in SoundRefs.all {
            let d = bestDistance(frames, ref)
            if d < .greatestFiniteMagnitude { scored.append((ref, d)) }
        }
        scored.sort { $0.1 < $1.1 }

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

    /// Vérifie que la comparaison fonctionne : on lui soumet une empreinte
    /// de référence telle quelle. Elle DOIT se reconnaître elle-même.
    /// Si l'auto-test échoue, le défaut est dans la comparaison ;
    /// s'il réussit, il est dans la capture.
    static func selfTest() -> String {
        guard SoundRefs.all.count > 30 else { return "pas assez de références" }
        let samples = [3, 17, 42, 88, 120]
        var ok = 0
        var detail = ""
        for i in samples where i < SoundRefs.all.count {
            let ref = SoundRefs.all[i]
            let res = top(1, for: ref.frames)
            let found = res.first?.refCard ?? "—"
            let pct = Int((res.first?.score ?? 0) * 100)
            if found == ref.card {
                ok += 1
            } else {
                detail += "\n\(plainName(ref.card)) → \(plainName(found)) \(pct)%"
            }
        }
        return "Auto-test : \(ok)/\(samples.count) réussis" + detail
    }
}
