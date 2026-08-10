import Foundation

/// Empreintes enregistrées par l'app elle-même, pendant tes parties.
/// Elles sont calculées par le même code que la reconnaissance : aucun
/// écart possible entre ce qui est appris et ce qui est reconnu.
@MainActor
final class LearnedSounds: ObservableObject {

    static let shared = LearnedSounds()
    private let key = "learnedSounds.v1"

    /// identifiant de carte → liste d'exemples (chaque exemple = 26 trames)
    @Published private(set) var store: [String: [[[UInt8]]]] = [:]

    /// Carte en cours d'apprentissage, choisie par l'utilisateur.
    @Published var target: Card?
    @Published var lastMessage = ""

    init() { load() }

    var totalExamples: Int { store.values.reduce(0) { $0 + $1.count } }
    var cardCount: Int { store.keys.count }
    var isUsable: Bool { cardCount >= 2 }

    func count(for id: String) -> Int { store[id]?.count ?? 0 }

    func add(_ frames: [[UInt8]], for card: Card) {
        guard frames.count >= 20 else {
            lastMessage = "Trop court, ignoré"
            return
        }
        let clipped = Array(frames.prefix(26))
        store[card.id, default: []].append(clipped)
        if store[card.id]!.count > 8 { store[card.id]!.removeFirst() }
        lastMessage = "\(card.name) : \(store[card.id]!.count) exemple(s)"
        save()
    }

    func forget(_ id: String) {
        store.removeValue(forKey: id)
        save()
    }

    func forgetAll() {
        store.removeAll()
        save()
    }

    // MARK: - Reconnaissance par plus proche voisin

    struct Hit {
        let card: Card
        let score: Double        // 0 à 1
        let runnerUp: String
    }

    /// Compare aux exemples appris. Retourne la carte la plus ressemblante.
    func recognise(_ frames: [[UInt8]]) -> Hit? {
        guard isUsable, frames.count >= 20 else { return nil }
        let probe = Array(frames.prefix(26))

        var best: (String, Double) = ("", -2)
        var second: (String, Double) = ("", -2)

        for (id, examples) in store {
            var bestForCard = -2.0
            for ex in examples {
                bestForCard = max(bestForCard, correlation(probe, ex))
            }
            if bestForCard > best.1 {
                second = best
                best = (id, bestForCard)
            } else if bestForCard > second.1 {
                second = (id, bestForCard)
            }
        }

        guard let card = CardCatalog.all.first(where: { $0.id == best.0 })
        else { return nil }

        // La corrélation va de -1 à 1 : on la ramène sur 0 à 1
        let score = max(0, min(1, (best.1 + 1) / 2))
        var runner = ""
        if let s = CardCatalog.all.first(where: { $0.id == second.0 }) {
            runner = "\(s.name) \(Int(max(0, (second.1 + 1) / 2) * 100))%"
        }
        return Hit(card: card, score: score, runnerUp: runner)
    }

    /// Corrélation entre deux séquences de trames, avec un léger décalage
    /// temporel toléré dans les deux sens.
    private func correlation(_ a: [[UInt8]], _ b: [[UInt8]]) -> Double {
        var best = -2.0
        for shift in -2...2 {
            let x = shift >= 0 ? Array(a.dropFirst(shift)) : a
            let y = shift >= 0 ? b : Array(b.dropFirst(-shift))
            let n = min(x.count, y.count)
            guard n >= 12 else { continue }

            var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, k = 0.0
            for i in 0..<n {
                let ra = x[i], rb = y[i]
                let m = min(ra.count, rb.count)
                for j in 0..<m {
                    let u = Double(ra[j]), v = Double(rb[j])
                    sx += u; sy += v; sxx += u * u; syy += v * v; sxy += u * v
                    k += 1
                }
            }
            guard k > 16 else { continue }
            let num = sxy - sx * sy / k
            let den = ((sxx - sx * sx / k) * (syy - sy * sy / k)).squareRoot()
            if den > 1e-6 { best = max(best, num / den) }
        }
        return best
    }

    // MARK: - Sauvegarde

    private func save() {
        var flat: [String: [String]] = [:]
        for (id, examples) in store {
            flat[id] = examples.map { ex in
                Data(ex.flatMap { $0 }).base64EncodedString()
            }
        }
        if let d = try? JSONEncoder().encode(flat) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let flat = try? JSONDecoder().decode([String: [String]].self, from: d)
        else { return }

        let bands = SoundModel.bands
        for (id, list) in flat {
            var examples: [[[UInt8]]] = []
            for s in list {
                guard let raw = Data(base64Encoded: s), raw.count % bands == 0
                else { continue }
                let bytes = [UInt8](raw)
                var frames: [[UInt8]] = []
                for i in stride(from: 0, to: bytes.count, by: bands) {
                    frames.append(Array(bytes[i..<(i + bands)]))
                }
                examples.append(frames)
            }
            if !examples.isEmpty { store[id] = examples }
        }
    }
}
