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
    @Published var autoLearned = 0      // appris sans intervention
    @Published var sentToPending = 0    // coût partagé, à étiqueter
    @Published var noCandidate = 0      // coût absent du deck
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
            autoLearned += 1
            add(frames, for: cands[0])
        } else if cands.count > 1 {
            sentToPending += 1
            pending.insert(Pending(at: Date(), drop: drop,
                                   frames: Array(frames.prefix(26)),
                                   candidates: cands), at: 0)
            if pending.count > 25 { pending.removeLast() }
            lastMessage = "Son mis de côté : \(cands.count) cartes à \(drop) élixirs"
        } else {
            noCandidate += 1
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

    /// Un exemple précis, pour inspection visuelle.
    func example(_ id: String, at index: Int) -> [[UInt8]]? {
        guard let list = store[id], index < list.count else { return nil }
        return list[index]
    }

    func add(_ frames: [[UInt8]], for card: Card) {
        guard frames.count >= 30 else {
            lastMessage = "Trop court, ignoré"
            return
        }
        let clipped = frames
        store[card.id, default: []].append(clipped)
        if store[card.id]!.count > 8 { store[card.id]!.removeFirst() }
        lastMessage = "\(card.name) : \(store[card.id]!.count) exemple(s)"
        save()
    }


    /// Mesure décisive : une carte est reconnaissable si ses exemples se
    /// ressemblent PLUS entre eux qu'ils ne ressemblent aux autres cartes.
    /// Retourne la ressemblance interne, la confusion maximale, et avec qui.
    func separation(for id: String) -> (own: Double, other: Double, with: String)? {
        guard let mine = store[id], mine.count >= 2 else { return nil }

        var own = 0.0, n = 0.0
        for i in 0..<mine.count {
            for j in (i + 1)..<mine.count {
                own += correlation(mine[i], mine[j]); n += 1
            }
        }
        guard n > 0 else { return nil }
        own = (own / n + 1) / 2

        // Comparaison honnête : MOYENNE contre MOYENNE.
        // Prendre le maximum des paires croisées gonflait artificiellement
        // la confusion, puisqu'un maximum sur des dizaines de tirages est
        // toujours élevé.
        var worst = -1.0, worstId = ""
        for (other, examples) in store where other != id {
            var sum = 0.0, k = 0.0
            for a in mine { for b in examples { sum += correlation(a, b); k += 1 } }
            guard k > 0 else { continue }
            let v = (sum / k + 1) / 2
            if v > worst { worst = v; worstId = other }
        }
        let name = CardCatalog.all.first { $0.id == worstId }?.name ?? "—"
        return (max(0, min(1, own)), max(0, min(1, worst)), name)
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


    // MARK: - Traitement du signal

    /// Convertit une valeur transmise (0-255) en décibels absolus.
    private static func toDb(_ v: UInt8) -> Double {
        Double(v) / 255.0 * 100.0 - 80.0
    }

    /// Prépare une fenêtre pour la comparaison :
    /// 1. soustraction de l'ambiance mesurée juste avant,
    /// 2. porte de bruit sur les tranches trop faibles,
    /// 3. normalisation sur le pic de TOUTE la fenêtre, ce qui préserve
    ///    l'enveloppe du son — l'attaque puis le déclin.
    /// Bond d'énergie minimal pour considérer qu'un son a démarré.
    nonisolated(unsafe) static var jumpThreshold = 3.0
    /// Dernier bond mesuré, pour pouvoir régler le seuil au lieu de le deviner.
    nonisolated(unsafe) static var lastJump = 0.0

    static func process(window: [[UInt8]], ambience: [[UInt8]]) -> [[UInt8]] {
        guard let bands = window.first?.count, bands > 0, window.count >= 20
        else { return window }

        // Énergie de chaque tranche : on prend la BANDE LA PLUS FORTE.
        // Un son de carte concentre son énergie sur quelques fréquences ;
        // moyenné sur 32 bandes, un pic net devient imperceptible.
        let energy: [Double] = window.map { f in
            toDb(f.max() ?? 0)
        }

        // On cherche l'ÉVÉNEMENT : l'endroit où l'énergie bondit le plus
        // au-dessus de ce qui la précède. Aucune zone n'est interdite —
        // le son peut arriver tôt (sorts) ou tard (troupes lourdes).
        var bestIdx = -1, bestJump = 0.0
        let look = 8
        for i in look..<(window.count - 12) {
            let base = energy[(i - look)..<i].reduce(0, +) / Double(look)
            let jump = energy[i] - base
            if jump > bestJump { bestJump = jump; bestIdx = i }
        }

        // Pas d'événement franc : on renvoie une fenêtre vide plutôt que
        // du bruit, pour que l'enregistrement soit écarté.
        lastJump = bestJump
        guard bestIdx >= 0, bestJump > jumpThreshold else { return [] }

        // 60 tranches (≈ 0,70 s) : de quoi contenir en ENTIER les sons
        // longs comme l'Arc-X ou La Bûche, dont la durée est justement
        // ce qui les distingue des sons brefs.
        let from = max(0, bestIdx - 4)
        var tail = Array(window[from...])
        if tail.count > 60 { tail = Array(tail.prefix(60)) }
        guard tail.count >= 30 else { return [] }

        // Normalisation douce sur le pic de cette portion, sans soustraction :
        // la soustraction d'ambiance écrasait le signal utile.
        var peak = 0.0
        for f in tail { for v in f { peak = max(peak, toDb(v)) } }
        guard peak > -70 else { return [] }

        var out: [[UInt8]] = []
        for f in tail {
            out.append(f.map { v in
                UInt8(max(0, min(255, Int((toDb(v) - peak + 40) / 40 * 255))))
            })
        }
        return out
    }

    // MARK: - Reconnaissance par plus proche voisin

    struct Hit {
        let card: Card
        let score: Double        // 0 à 1
        let runnerUp: String
    }

    /// Compare aux exemples appris. Retourne la carte la plus ressemblante.
    func recognise(_ frames: [[UInt8]]) -> Hit? {
        guard isUsable, frames.count >= 30 else { return nil }
        let probe = frames

        var best: (String, Double) = ("", -2)
        var second: (String, Double) = ("", -2)

        for (id, examples) in store {
            // Moyenne des deux meilleures correspondances : plus stable
            // qu'un simple record, qui favorise les cartes ayant le plus
            // d'exemples enregistrés.
            var scores = examples.map { correlation(probe, $0) }
            scores.sort(by: >)
            let take = min(2, scores.count)
            let bestForCard = scores.prefix(take).reduce(0, +) / Double(take)
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
    /// Corrélation sur la séquence chronologique COMPLÈTE : c'est
    /// l'évolution des bandes dans le temps qui identifie une carte.
    func correlation(_ a: [[UInt8]], _ b: [[UInt8]]) -> Double {
        var best = -2.0
        // La baisse d'élixir est détectée avec un retard variable : le son
        // peut se trouver décalé d'une dizaine de trames d'un enregistrement
        // à l'autre. On cherche donc le meilleur alignement sur toute la plage.
        // Les séquences sont déjà calées sur l'attaque détectée : un
        // glissement large laisserait un son long se superposer à
        // n'importe quoi et effacerait la différence de durée.
        for shift in -3...3 {
            let x = shift >= 0 ? Array(a.dropFirst(shift)) : a
            let y = shift >= 0 ? b : Array(b.dropFirst(-shift))
            let n = min(x.count, y.count)
            guard n >= 20 else { continue }

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
