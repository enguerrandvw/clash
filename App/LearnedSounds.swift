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
    /// Audio brut correspondant, pour vérification à l'oreille
    @Published private(set) var audioStore: [String: [[UInt8]]] = [:]

    /// Ton deck : 8 cartes déclarées une fois pour toutes.
    @Published var myDeck: [Card] = []

    /// Toutes les cartes ayant au moins un exemple, qu'elles soient ou non
    /// dans le deck déclaré. Sans ça, une banque chargée depuis le fichier
    /// compilé resterait invisible tant que le deck n'est pas redéclaré.
    var learnedCards: [Card] {
        store.keys.compactMap { id in CardCatalog.all.first { $0.id == id } }
            .sorted { $0.cost == $1.cost ? $0.name < $1.name : $0.cost < $1.cost }
    }

    /// Sons captés dont on ignore encore la carte, en attente d'étiquetage.
    struct Pending: Identifiable {
        let id = UUID()
        let at: Date
        let drop: Int
        let frames: [[UInt8]]
        let audio: [UInt8]
        let candidates: [Card]
    }
    @Published var pending: [Pending] = []

    @Published var lastMessage = ""
    @Published var autoLearned = 0      // appris sans intervention
    @Published var sentToPending = 0    // coût partagé, à étiqueter
    @Published var noCandidate = 0      // coût absent du deck
    /// Conservé pour l'ancien mode manuel
    @Published var target: Card?

    init() { load(); loadDeck(); loadBanked() }

    /// Fusionne la banque figée dans l'app avec ce qui est stocké localement.
    /// Les exemples embarqués ne sont ajoutés que s'ils manquent, pour ne
    /// jamais écraser un enregistrement plus récent.
    private func loadBanked() {
        let bands = SoundModel.bands
        if myDeck.isEmpty, !BankedSounds.deck.isEmpty {
            setDeck(BankedSounds.deck.compactMap { id in
                CardCatalog.all.first { $0.id == id }
            })
        }
        for (id, list) in BankedSounds.data {
            guard store[id] == nil || store[id]!.isEmpty else { continue }
            var examples: [[[UInt8]]] = []
            for b64 in list {
                guard let raw = Data(base64Encoded: b64),
                      raw.count % bands == 0 else { continue }
                let bytes = [UInt8](raw)
                var frames: [[UInt8]] = []
                for i in stride(from: 0, to: bytes.count, by: bands) {
                    frames.append(Array(bytes[i..<(i + bands)]))
                }
                if frames.count >= 30 { examples.append(frames) }
            }
            if !examples.isEmpty { store[id] = examples }
        }
    }

    /// Produit le contenu d'un fichier Swift à déposer sur GitHub.
    func exportSwift() -> String {
        var out = "// Banque de sons figée dans l'app.\n"
        out += "// Généré depuis l'écran d'apprentissage.\n\n"
        out += "enum BankedSounds {\n"
        let deckIds = myDeck.map { "\"\($0.id)\"" }.joined(separator: ", ")
        out += "    static let deck: [String] = [\(deckIds)]\n\n"
        out += "    static let data: [String: [String]] = [\n"
        for (id, examples) in store.sorted(by: { $0.key < $1.key }) {
            let encoded = examples.map { ex in
                "\"" + Data(ex.flatMap { $0 }).base64EncodedString() + "\""
            }
            out += "        \"\(id)\": [\n"
            for e in encoded { out += "            \(e),\n" }
            out += "        ],\n"
        }
        out += "    ]\n}\n"
        return out
    }

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
    func observeMyPlay(drop: Int, frames: [[UInt8]], audio: [UInt8] = []) {
        guard drop >= 1, frames.count >= 20 else { return }
        // Coût exact d'abord : une baisse de 2 ne peut etre que La Buche.
        // On n'elargit que si rien ne correspond exactement.
        var cands = myDeck.filter { $0.cost == drop }
        if cands.isEmpty { cands = myDeck.filter { abs($0.cost - drop) == 1 } }

        if cands.count == 1 {
            autoLearned += 1
            add(frames, for: cands[0], audio: audio)
        } else if cands.count > 1 {
            sentToPending += 1
            pending.insert(Pending(at: Date(), drop: drop,
                                   frames: frames, audio: audio,
                                   candidates: cands), at: 0)
            if pending.count > 25 { pending.removeLast() }
            lastMessage = "Son mis de côté : \(cands.count) cartes à \(drop) élixirs"
        } else {
            noCandidate += 1
            lastMessage = "Baisse de \(drop) : aucune carte de ton deck"
        }
    }

    func label(_ p: Pending, as card: Card) {
        add(p.frames, for: card, audio: p.audio)
        pending.removeAll { $0.id == p.id }
    }

    func discard(_ p: Pending) {
        pending.removeAll { $0.id == p.id }
    }

    var totalExamples: Int { store.values.reduce(0) { $0 + $1.count } }
    var cardCount: Int { store.keys.count }
    var isUsable: Bool { cardCount >= 2 }

    func count(for id: String) -> Int { store[id]?.count ?? 0 }

    /// Exemples jugés assez cohérents pour servir à la reconnaissance.
    func usableCount(for id: String) -> Int {
        guard let list = store[id] else { return 0 }
        if list.count < 3 { return list.count }
        return (0..<list.count).filter { (consistency(id, at: $0) ?? 1) >= 0.60 }.count
    }

    /// Un exemple précis, pour inspection visuelle.
    func example(_ id: String, at index: Int) -> [[UInt8]]? {
        guard let list = store[id], index < list.count else { return nil }
        return list[index]
    }

    func audio(_ id: String, at index: Int) -> [UInt8]? {
        guard let list = audioStore[id], index < list.count else { return nil }
        return list[index]
    }

    func add(_ frames: [[UInt8]], for card: Card, audio: [UInt8] = []) {
        guard frames.count >= 30 else {
            lastMessage = "Trop court, ignoré"
            return
        }
        let clipped = frames
        store[card.id, default: []].append(clipped)
        audioStore[card.id, default: []].append(audio)
        if store[card.id]!.count > 8 {
            store[card.id]!.removeFirst()
            if !(audioStore[card.id]?.isEmpty ?? true) {
                audioStore[card.id]!.removeFirst()
            }
        }
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
        if var a = audioStore[id], index < a.count {
            a.remove(at: index)
            if a.isEmpty { audioStore.removeValue(forKey: id) } else { audioStore[id] = a }
        }
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
        audioStore.removeValue(forKey: id)
        save()
    }

    func forgetAll() {
        store.removeAll()
        audioStore.removeAll()
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
    nonisolated(unsafe) static var jumpThreshold = 1.0
    /// Dernier bond mesuré, pour pouvoir régler le seuil au lieu de le deviner.
    nonisolated(unsafe) static var lastJump = 0.0

    static func process(window: [[UInt8]], ambience: [[UInt8]]) -> [[UInt8]] {
        guard let bands = window.first?.count, bands > 0, window.count >= 40
        else { return [] }

        // --- 1. Retrait du fond stationnaire, sur TOUTE la fenêtre ---
        // Pour chaque bande, on retire sa médiane temporelle. La musique et
        // l'ambiance, constantes, s'annulent ; seuls les événements brefs
        // subsistent. On le fait AVANT de découper, pour que l'événement
        // soit déjà visible au moment de le localiser.
        var medians = [Double](repeating: 0, count: bands)
        for b in 0..<bands {
            var col = window.compactMap { $0.count > b ? toDb($0[b]) : nil }
            guard !col.isEmpty else { continue }
            col.sort()
            medians[b] = col[col.count / 2]
        }

        var clean: [[Double]] = []
        for f in window {
            var row = [Double](repeating: 0, count: bands)
            for b in 0..<bands where f.count > b {
                row[b] = max(0, toDb(f[b]) - medians[b])
            }
            clean.append(row)
        }

        // --- 2. Localiser l'événement, maintenant qu'il est dégagé ---
        // On lisse l'énergie résiduelle sur 5 trames pour ne pas s'accrocher
        // à un pic isolé, puis on prend le maximum.
        let energy = clean.map { $0.reduce(0, +) / Double(bands) }
        var smooth = [Double](repeating: 0, count: energy.count)
        for i in 0..<energy.count {
            let lo = max(0, i - 2), hi = min(energy.count - 1, i + 2)
            smooth[i] = energy[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }

        // On ne cherche l'événement que dans la zone où il peut se trouver :
        // le son de la carte arrive environ une seconde après la baisse
        // d'élixir, donc vers le milieu de la fenêtre. Chercher partout
        // ferait s'accrocher l'algorithme à un tir de tour ou une explosion.
        let lo = Int(Double(smooth.count) * 0.25)
        let hi = Int(Double(smooth.count) * 0.80)
        var peakIdx = lo, peakVal = -1.0
        for i in lo..<max(lo + 1, hi) where smooth[i] > peakVal {
            peakVal = smooth[i]; peakIdx = i
        }
        lastJump = peakVal
        guard peakVal > 0.5 else { return [] }

        // --- 3. Découper 60 trames centrées sur l'événement ---
        let want = 60
        var from = max(0, peakIdx - 12)
        if from + want > clean.count { from = max(0, clean.count - want) }
        var tail = Array(clean[from...])
        if tail.count > want { tail = Array(tail.prefix(want)) }
        guard tail.count >= 40 else { return [] }

        // --- 4. Normaliser ---
        var peak = 0.0
        for row in tail { for v in row { peak = max(peak, v) } }
        guard peak > 2 else { return [] }

        // On ne garde que le sommet de l'événement : tout ce qui est en
        // dessous de 45 % du pic est mis à zéro. Quand la partie est agitée,
        // le retrait du fond laisse encore beaucoup de matière parasite ;
        // ce seuil ne conserve que le son dominant.
        let floor = peak * 0.45
        var out: [[UInt8]] = []
        for row in tail {
            out.append(row.map { v in
                v < floor ? 0
                    : UInt8(max(0, min(255, Int((v - floor) / (peak - floor) * 255))))
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
    /// Résultat d'un test de reconnaissance en conditions réelles.
    struct TestReport {
        var total = 0
        var correct = 0
        var perCard: [String: (ok: Int, n: Int)] = [:]
        var confusedWith: [String: [String: Int]] = [:]
        var rate: Double { total > 0 ? Double(correct) / Double(total) : 0 }
    }

    /// Teste la reconnaissance honnêtement : chaque exemple est présenté à
    /// l'app COMME S'IL ÉTAIT INCONNU, en le retirant de la banque. C'est
    /// la seule mesure qui prédise le comportement réel en partie.
    func selfTest() -> TestReport {
        var r = TestReport()
        let ids = Array(store.keys)
        guard ids.count >= 2 else { return r }

        for id in ids {
            guard let examples = store[id] else { continue }
            for (i, probe) in examples.enumerated() {

                // Meilleur score de chaque carte, l'exemple testé exclu
                var best = ""
                var bestScore = -1.0
                for other in ids {
                    guard let list = store[other] else { continue }
                    var scores: [Double] = []
                    for (j, ex) in list.enumerated() {
                        if other == id && j == i { continue }   // on se cache
                        scores.append(correlation(probe, ex))
                    }
                    guard !scores.isEmpty else { continue }
                    scores.sort(by: >)
                    let sc = scores.count >= 2
                        ? (scores[0] + scores[1]) / 2 : scores[0]
                    if sc > bestScore { bestScore = sc; best = other }
                }
                guard !best.isEmpty else { continue }

                r.total += 1
                var cell = r.perCard[id] ?? (0, 0)
                cell.n += 1
                if best == id {
                    r.correct += 1
                    cell.ok += 1
                } else {
                    r.confusedWith[id, default: [:]][best, default: 0] += 1
                }
                r.perCard[id] = cell
            }
        }
        return r
    }

    func recognise(_ frames: [[UInt8]]) -> Hit? {
        guard isUsable, frames.count >= 30 else { return nil }
        let probe = frames

        var best: (String, Double) = ("", -2)
        var second: (String, Double) = ("", -2)

        for (id, examples) in store {
            // On écarte les exemples trop peu cohérents avec les autres :
            // ce sont des captures polluées par le bruit de combat, et
            // les garder dégraderait la reconnaissance.
            var usable: [[[UInt8]]] = []
            for (i, ex) in examples.enumerated() {
                if examples.count < 3 || (consistency(id, at: i) ?? 1) >= 0.60 {
                    usable.append(ex)
                }
            }
            if usable.isEmpty { usable = examples }

            // Moyenne des deux meilleures correspondances : plus stable
            // qu'un simple record, qui favorise les cartes ayant le plus
            // d'exemples enregistrés.
            var scores = usable.map { correlation(probe, $0) }
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
        for shift in -20...20 {
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
        var au: [String: [String]] = [:]
        for (id, list) in audioStore {
            au[id] = list.map { Data($0).base64EncodedString() }
        }
        if let d = try? JSONEncoder().encode(au) {
            UserDefaults.standard.set(d, forKey: key + ".audio")
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

        if let ad = UserDefaults.standard.data(forKey: key + ".audio"),
           let au = try? JSONDecoder().decode([String: [String]].self, from: ad) {
            for (id, list) in au {
                audioStore[id] = list.map { [UInt8](Data(base64Encoded: $0) ?? Data()) }
            }
        }
    }
}
