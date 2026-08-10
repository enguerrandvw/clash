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

    /// Ton deck : 8 cartes déclarées une fois pour toutes.
    @Published var myDeck: [Card] = []

    /// Sons captés dont on ignore encore la carte, en attente d'étiquetage.
    struct Pending: Identifiable {
        let id = UUID()
        let at: Date
        let drop: Int
        let frames: [[UInt8]]
        let candidates: [Card]
    }
    @Published var pending: [Pending] = []

    @Published var lastMessage = ""
    /// Conservé pour l'ancien mode manuel
    @Published var target: Card?

    init() { load(); loadDeck() }

    // MARK: - Deck

    func setDeck(_ cards: [Card]) {
        myDeck = cards
        UserDefaults.standard.set(cards.map(\.id), forKey: "myDeck.v1")
    }

    func toggleDeck(_ card: Card) {
        if let i = myDeck.firstIndex(where: { $0.id == card.id }) {
            myDeck.remove(at: i)
        } else if myDeck.count < 8 {
            myDeck.append(card)
        }
        setDeck(myDeck)
    }

    private func loadDeck() {
        let ids = UserDefaults.standard.stringArray(forKey: "myDeck.v1") ?? []
        myDeck = ids.compactMap { id in CardCatalog.all.first { $0.id == id } }
    }

    /// Appelé quand TON élixir a baissé : on déduit la carte si possible.
    func observeMyPlay(drop: Int, frames: [[UInt8]]) {
        guard drop >= 1, frames.count >= 20 else { return }
        // Coût exact d'abord : une baisse de 2 ne peut etre que La Buche.
        // On n'elargit que si rien ne correspond exactement.
        var cands = myDeck.filter { $0.cost == drop }
        if cands.isEmpty { cands = myDeck.filter { abs($0.cost - drop) == 1 } }

        if cands.count == 1 {
            add(frames, for: cands[0])
        } else if cands.count > 1 {
            pending.insert(Pending(at: Date(), drop: drop,
                                   frames: Array(frames.prefix(26)),
                                   candidates: cands), at: 0)
            if pending.count > 25 { pending.removeLast() }
            lastMessage = "Son mis de côté : \(cands.count) cartes à \(drop) élixirs"
        } else {
            lastMessage = "Baisse de \(drop) : aucune carte de ton deck"
        }
    }

    func label(_ p: Pending, as card: Card) {
        add(p.frames, for: card)
        pending.removeAll { $0.id == p.id }
    }

    func discard(_ p: Pending) {
        pending.removeAll { $0.id == p.id }
    }

    var totalExamples: Int { store.values.reduce(0) { $0 + $1.count } }
    var cardCount: Int { store.keys.count }
    var isUsable: Bool { cardCount >= 2 }

    func count(for id: String) -> Int { store[id]?.count ?? 0 }

    func add(_ frames: [[UInt8]], for card: Card) {
        guard frames.count >= 20 else {
            lastMessage = "Trop court, ignoré"
            return
        }
        let clipped = Array(frames.suffix(40))
        store[card.id, default: []].append(clipped)
        if store[card.id]!.count > 8 { store[card.id]!.removeFirst() }
        lastMessage = "\(card.name) : \(store[card.id]!.count) exemple(s)"
        save()
    }

    /// Supprime un exemple précis d'une carte.
    func remove(_ id: String, at index: Int) {
        guard var list = store[id], index < list.count else { return }
        list.remove(at: index)
        if list.isEmpty { store.removeValue(forKey: id) } else { store[id] = list }
        save()
    }

    /// Cohérence d'un exemple avec les autres de la même carte.
    /// Un enregistrement parasité ressort avec un score bas.
    func consistency(_ id: String, at index: Int) -> Double? {
        guard let list = store[id], list.count >= 2, index < list.count else { return nil }
        var total = 0.0, n = 0.0
        for (k, other) in list.enumerated() where k != index {
            total += correlation(list[index], other)
            n += 1
        }
        guard n > 0 else { return nil }
        return max(0, min(1, (total / n + 1) / 2))
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
        let probe = Array(frames.suffix(40))

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
    /// Repere la trame la plus mouvementee : c'est la qu'est le son.
    private func peakFrame(_ w: [[UInt8]]) -> Int {
        var bestIdx = 0, bestVar = -1.0
        for (i, f) in w.enumerated() where !f.isEmpty {
            let m = f.reduce(0.0) { $0 + Double($1) } / Double(f.count)
            var v = 0.0
            for x in f { v += (Double(x) - m) * (Double(x) - m) }
            v /= Double(f.count)
            if v > bestVar { bestVar = v; bestIdx = i }
        }
        return bestIdx
    }

    /// Extrait 16 trames centrees sur la partie active : on compare ainsi
    /// les sons entre eux, et non les ambiances qui les entourent.
    private func core(_ w: [[UInt8]]) -> [[UInt8]] {
        guard w.count > 16 else { return w }
        let p = peakFrame(w)
        let start = max(0, min(w.count - 16, p - 3))
        return Array(w[start..<(start + 16)])
    }

    func correlation(_ raw1: [[UInt8]], _ raw2: [[UInt8]]) -> Double {
        let a = core(raw1), b = core(raw2)
        var best = -2.0
        // La baisse d'élixir est détectée avec un retard variable : le son
        // peut se trouver décalé d'une dizaine de trames d'un enregistrement
        // à l'autre. On cherche donc le meilleur alignement sur toute la plage.
        for shift in -4...4 {
            let x = shift >= 0 ? Array(a.dropFirst(shift)) : a
            let y = shift >= 0 ? b : Array(b.dropFirst(-shift))
            let n = min(x.count, y.count)
            guard n >= 10 else { continue }

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
