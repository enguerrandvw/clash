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

    /// Nombre d'exemples déjà figés dans l'app par carte. Sert à n'afficher
    /// que les nouveautés : les anciens restent en mémoire et à l'export.
    private var bankedCount: [String: Int] = [:]

    /// Statistiques mises en cache. Les recalculer à chaque redessin de
    /// l'écran coûtait des milliers de corrélations et figeait l'interface.
    private var statsCache: [String: (own: Double, other: Double,
                                      with: String, usable: Int)] = [:]

    private func invalidateStats() {
        statsCache.removeAll()
        maskCache.removeAll()
        perCardMethod.removeAll()
        maskRefCache.removeAll()
        selfLevelCache.removeAll()
        RefMatcher.clearCache()
    }

    private func stats(_ id: String)
        -> (own: Double, other: Double, with: String, usable: Int)? {
        if let c = statsCache[id] { return c }
        guard let sep = computeSeparation(for: id) else { return nil }
        let usable = computeUsableCount(for: id)
        let v = (sep.own, sep.other, sep.with, usable)
        statsCache[id] = v
        return v
    }

    /// Toutes les cartes ayant au moins un exemple, qu'elles soient ou non
    /// dans le deck déclaré. Sans ça, une banque chargée depuis le fichier
    /// compilé resterait invisible tant que le deck n'est pas redéclaré.
    /// Toutes les cartes ayant au moins un exemple. On affiche tout : le
    /// ralentissement venait des statistiques recalculées en boucle, pas du
    /// nombre de lignes, et masquer des cartes rendait l'écran trompeur.
    var learnedCards: [Card] {
        store.keys
            .compactMap { id in CardCatalog.all.first { $0.id == id } }
            .sorted { $0.cost == $1.cost ? $0.name < $1.name : $0.cost < $1.cost }
    }

    /// Exemples ajoutés depuis le dernier export, toutes cartes confondues.
    var freshExamples: Int {
        store.reduce(0) { $0 + max(0, $1.value.count - (bankedCount[$1.key] ?? 0)) }
    }

    func freshCount(for id: String) -> Int {
        max(0, (store[id]?.count ?? 0) - (bankedCount[id] ?? 0))
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
    @Published var autoLearned = 0      // conservé pour compatibilité
    @Published var labelled = 0         // exemples étiquetés à la main
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
            if !examples.isEmpty {
                store[id] = examples
                bankedCount[id] = examples.count
            }
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

        // Tolérance d'un élixir : la barre est lue avec un léger retard, si
        // bien qu'une carte à 2 peut être vue comme une baisse de 1 ou de 3.
        // Se limiter au coût exact écartait des candidats légitimes.
        let cands = myDeck.filter { abs($0.cost - drop) <= 1 }
                          .sorted { abs($0.cost - drop) < abs($1.cost - drop) }

        guard !cands.isEmpty else {
            noCandidate += 1
            lastMessage = "Baisse de \(drop) : aucune carte de ton deck"
            return
        }

        // Aucun apprentissage automatique, même lorsqu'un seul candidat
        // existe : une carte mal attribuée pollue durablement la banque
        // sans qu'on puisse s'en apercevoir. C'est toi qui tranches.
        sentToPending += 1
        pending.insert(Pending(at: Date(), drop: drop,
                               frames: frames, audio: audio,
                               candidates: cands), at: 0)
        if pending.count > 40 { pending.removeLast() }
        lastMessage = "Son à étiqueter · −\(drop) élixir · \(cands.count) candidate(s)"
    }

    func label(_ p: Pending, as card: Card) {
        labelled += 1
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
    func usableCount(for id: String) -> Int { stats(id)?.usable ?? 0 }

    func separation(for id: String) -> (own: Double, other: Double, with: String)? {
        guard let s = stats(id) else { return nil }
        return (s.own, s.other, s.with)
    }

    private func computeUsableCount(for id: String) -> Int {
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
        invalidateStats()
        guard frames.count >= 30 else {
            lastMessage = "Trop court, ignoré"
            return
        }
        let clipped = frames
        store[card.id, default: []].append(clipped)
        audioStore[card.id, default: []].append(audio)
        // Plafond large : le masque de constance devient d'autant plus fiable
        // qu'il dispose d'exemples variés. On ne jette que pour éviter une
        // croissance sans fin.
        if store[card.id]!.count > 40 {
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
    private func computeSeparation(for id: String) -> (own: Double, other: Double, with: String)? {
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
        invalidateStats()
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
        invalidateStats()
        store.removeValue(forKey: id)
        audioStore.removeValue(forKey: id)
        save()
    }

    func forgetAll() {
        invalidateStats()
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
    /// Test sans biais : la moitié des exemples sert à décider de la
    /// méthode, l'autre moitié seulement à mesurer. C'est la seule façon
    /// de savoir ce que vaudrait le mode Auto sur des sons jamais vus.
    func honestTest() -> TestReport {
        var r = TestReport()
        let ids = Array(store.keys)
        guard ids.count >= 2 else { return r }

        // Découpe : exemples de rang pair pour apprendre, impair pour tester
        var learn: [String: [[[UInt8]]]] = [:]
        var test: [String: [[[UInt8]]]] = [:]
        for (id, list) in store {
            guard list.count >= 4 else { continue }
            learn[id] = list.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            test[id]  = list.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        }
        guard learn.count >= 2 else { return r }

        // Méthode décidée sur la seule moitié d'apprentissage
        var chosen: [String: Method] = [:]
        for id in learn.keys { chosen[id] = methodFor(id, learningOn: learn) }

        for (id, probes) in test {
            for probe in probes {
                var best = ""
                var bestScore = -2.0
                for (other, exs) in learn {
                    let m = chosen[other] ?? .simple
                    var scores = exs.map { ex -> Double in
                        m == .blurred ? correlation(blur(probe), blur(ex))
                                      : correlation(probe, ex)
                    }
                    scores.sort(by: >)
                    let sc = scores.count >= 2
                        ? (scores[0] + scores[1]) / 2 : (scores.first ?? -2)
                    if sc > bestScore { bestScore = sc; best = other }
                }
                guard !best.isEmpty else { continue }
                r.total += 1
                var cell = r.perCard[id] ?? (0, 0)
                cell.n += 1
                if best == id { r.correct += 1; cell.ok += 1 }
                else { r.confusedWith[id, default: [:]][best, default: 0] += 1 }
                r.perCard[id] = cell
            }
        }
        return r
    }

    func selfTest() -> TestReport {
        var r = TestReport()
        let ids = Array(store.keys)
        guard ids.count >= 2 else { return r }

        for id in ids {
            guard let examples = store[id] else { continue }
            for (i, probe) in examples.enumerated() {

                // Meilleur score de chaque carte, l'exemple testé exclu
                var best = ""
                var bestScore = -2.0
                for other in ids {
                    guard let list = store[other] else { continue }
                    // Pour la carte testée, on retire l'exemple examiné AVANT
                    // de calculer son masque : sinon il se reconnaîtrait
                    // lui-même et le score serait flatté.
                    let pool = (other == id)
                        ? list.enumerated().filter { $0.offset != i }.map(\.element)
                        : list
                    guard !pool.isEmpty else { continue }

                    var scores = pool.map { similarity(probe, $0, for: other) }
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

        // Comparaison directe aux exemples enregistrés.
        //
        // Le masque de constance — ne comparer que les cases stables d'une
        // carte — a été essayé sous trois formes et mesuré à chaque fois :
        // 29 %, puis 15 %, contre 52 % pour la méthode simple. L'idée était
        // fondée, mais les enregistrements en partie varient trop pour qu'une
        // zone vraiment stable s'en dégage. Le code est conservé (maskOf,
        // maskedScore, maskStrength) car il reste utile pour diagnostiquer,
        // mais il ne décide plus.
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
            var scores = usable.map { similarity(probe, $0, for: id) }
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
    /// Masque de constance d'une carte : les cases du spectrogramme qui
    /// gardent la même valeur d'un enregistrement à l'autre.
    ///
    /// L'idée est celle-ci : sur dix enregistrements du Chevalier, le
    /// voisinage change à chaque fois — une sorcière ici, une boule de feu
    /// là. Seul le son du Chevalier est présent dans les dix, toujours au
    /// même endroit et à la même intensité. Une case qui varie beaucoup
    /// appartient donc au décor ; une case stable appartient à la carte.
    private var maskCache: [String: [[Double]]] = [:]

    /// Nombre de cases exploitables du masque d'une carte, et poids moyen.
    /// C'est la mesure directe de « combien de son propre reste-t-il une fois
    /// le décor écarté ». Une carte pauvre ici ne pourra pas être reconnue.
    /// Niveau que la méthode pondérée atteint entre deux exemples de la
    /// MÊME carte. Sert d'étalon : un score de 0,6 ne veut pas dire la même
    /// chose pour une carte dont les exemples se ressemblent à 0,9 et pour
    /// une autre où ils plafonnent à 0,65.
    private var selfLevelCache: [String: Double] = [:]

    func maskedSelfLevel(_ id: String) -> Double {
        if let v = selfLevelCache[id] { return v }
        guard let list = store[id], list.count >= 2,
              let m = mask(for: id), let ref = list.first else { return 0 }
        var scores: [Double] = []
        for ex in list.dropFirst() {
            let v = maskedScore(ex, against: ref, weights: m)
            if v > -1.5 { scores.append(v) }
        }
        let v = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        selfLevelCache[id] = v
        return v
    }

    /// Proportion de cases non nulles dans les exemples d'une carte.
    /// Si elle est très basse, le traitement a effacé le son au lieu de
    /// l'isoler : c'est le seuil de 45 % du pic qui est en cause, et non
    /// la carte elle-même.
    func fillRate(for id: String) -> Double {
        guard let list = store[id], !list.isEmpty else { return 0 }
        var filled = 0, total = 0
        for ex in list {
            for row in ex {
                for v in row { total += 1; if v > 0 { filled += 1 } }
            }
        }
        return total > 0 ? Double(filled) / Double(total) : 0
    }

    func maskStrength(for id: String) -> (cells: Int, avg: Double) {
        guard let m = mask(for: id) else { return (0, 0) }
        var n = 0
        var sum = 0.0
        for row in m {
            for v in row where v > 0.15 { n += 1; sum += v }
        }
        return (n, n > 0 ? sum / Double(n) : 0)
    }

    private var maskRefCache: [String: [[UInt8]]] = [:]

    func mask(for id: String) -> [[Double]]? {
        if let m = maskCache[id] { return m }
        guard let list = store[id], let r = maskOf(list) else { return nil }
        maskCache[id] = r.mask
        maskRefCache[id] = r.ref
        return r.mask
    }

    /// Recale un exemple sur une référence, puis renvoie la version alignée.
    ///
    /// C'est indispensable pour les sons brefs : la baisse d'élixir est
    /// détectée avec un retard variable, si bien qu'un son de huit trames
    /// peut tomber à des endroits différents d'un enregistrement à l'autre.
    /// Sans recalage, deux exemples ne se superposent jamais et paraissent
    /// n'avoir aucune case en commun — alors qu'ils portent le même son.
    private func aligned(_ ex: [[UInt8]], onto ref: [[UInt8]]) -> [[UInt8]] {
        var bestShift = 0
        var bestScore = -2.0
        for shift in -20...20 {
            let x = shift >= 0 ? Array(ex.dropFirst(shift)) : ex
            let y = shift >= 0 ? ref : Array(ref.dropFirst(-shift))
            let n = min(x.count, y.count)
            guard n >= 20 else { continue }
            var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, k = 0.0
            for i in 0..<n {
                let ra = x[i], rb = y[i]
                for j in 0..<min(ra.count, rb.count) {
                    let u = Double(ra[j]), v = Double(rb[j])
                    sx += u; sy += v; sxx += u * u; syy += v * v; sxy += u * v
                    k += 1
                }
            }
            guard k > 16 else { continue }
            let num = sxy - sx * sy / k
            let den = ((sxx - sx * sx / k) * (syy - sy * sy / k)).squareRoot()
            if den > 1e-6, num / den > bestScore {
                bestScore = num / den; bestShift = shift
            }
        }
        guard bestShift != 0 else { return ex }
        let bands = ex.first?.count ?? 0
        let blank = [UInt8](repeating: 0, count: bands)
        if bestShift > 0 {
            return Array(ex.dropFirst(bestShift))
                 + Array(repeating: blank, count: bestShift)
        } else {
            return Array(repeating: blank, count: -bestShift)
                 + Array(ex.dropLast(-bestShift))
        }
    }

    /// Même calcul, sur un ensemble d'exemples quelconque.
    func maskOf(_ examples: [[[UInt8]]]) -> (mask: [[Double]], ref: [[UInt8]])? {
        guard examples.count >= 3,
              let bands = examples.first?.first?.count else { return nil }

        // 1. Choisir la référence : l'exemple qui ressemble le plus aux
        //    autres, et non le premier venu. S'aligner sur un enregistrement
        //    raté ferait converger tout le monde vers du bruit.
        var refIdx = 0
        if examples.count >= 3 {
            var bestSum = -1e9
            for (i, a) in examples.enumerated() {
                var sum = 0.0
                for (j, b) in examples.enumerated() where i != j {
                    sum += correlation(a, b)
                }
                if sum > bestSum { bestSum = sum; refIdx = i }
            }
        }
        let ref = examples[refIdx]

        // 2. Ne garder que le noyau cohérent. Certains enregistrements ont
        //    manqué le bon instant ou sont noyés sous une action voisine ;
        //    les inclure ferait exploser la variance et effacerait le son
        //    commun que portent les autres.
        var scored = examples.indices.map { i -> (idx: Int, score: Double) in
            (i, i == refIdx ? 1.0 : correlation(examples[i], ref))
        }
        scored.sort { $0.score > $1.score }
        // On écarte le quart le moins représentatif : assez pour retirer les
        // enregistrements manqués, pas au point de priver le masque de matière.
        let keep = max(3, Int((Double(examples.count) * 0.75).rounded()))
        let coreIdx = scored.prefix(keep).map(\.idx)

        // 3. Recaler le noyau sur la référence
        let set = coreIdx.map { i in
            i == refIdx ? ref : aligned(examples[i], onto: ref)
        }

        let frames = set.map(\.count).min() ?? 0
        guard frames >= 20 else { return nil }

        var m = [[Double]](repeating: [Double](repeating: 0, count: bands),
                           count: frames)
        for t in 0..<frames {
            for b in 0..<bands {
                var vals: [Double] = []
                for ex in set where ex[t].count > b {
                    vals.append(Double(ex[t][b]))
                }
                guard vals.count >= 3 else { continue }
                let mean = vals.reduce(0, +) / Double(vals.count)
                // Une case vide n'apprend rien, même si elle est stable.
                // Le seuil reste bas : les petites troupes ont un son faible,
                // et l'écarter reviendrait à décider d'avance qu'elles sont
                // inreconnaissables.
                guard mean > 5 else { continue }
                let varr = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
                    / Double(vals.count)
                // Écart-type rapporté à la moyenne : petit = constant.
                // Écart-type rapporté à la moyenne. Les enregistrements en
                // partie varient beaucoup : une case parfaitement stable
                // n'existe presque jamais, donc on étale l'échelle au lieu
                // de couper net.
                let rel = varr.squareRoot() / max(mean, 1)
                m[t][b] = max(0, 1 - rel / 1.6)
            }
        }

        // Un masque presque vide ne permet aucune comparaison fiable :
        // mieux vaut prévenir l'appelant et retomber sur la méthode simple.
        var active = 0
        for row in m { for v in row where v > 0.15 { active += 1 } }
        guard active >= 40 else { return nil }
        // Le masque et l'exemple autour duquel il a été construit vont de
        // pair : comparer avec un autre exemple pondérerait des cases qui
        // ne lui correspondent pas.
        return (m, ref)
    }

    /// Comparaison pondérée : seules les cases constantes de la carte pèsent.
    func maskedScore(_ probe: [[UInt8]], id: String) -> Double {
        guard let m = mask(for: id), let ref = maskRefCache[id] else {
            return store[id].map { list in
                list.map { correlation(probe, $0) }.max() ?? -1
            } ?? -1
        }
        return maskedScore(probe, against: ref, weights: m)
    }

    /// Cœur du calcul : corrélation où chaque case est pondérée par sa
    /// constance. Une case qui varie d'un enregistrement à l'autre ne
    /// compte presque pas ; une case toujours identique compte pleinement.
    func maskedScore(_ probe: [[UInt8]], against ref: [[UInt8]],
                     weights m: [[Double]]) -> Double {
        var best = -2.0
        for shift in -20...20 {
            let x = shift >= 0 ? Array(probe.dropFirst(shift)) : probe
            let y = shift >= 0 ? ref : Array(ref.dropFirst(-shift))
            let n = min(x.count, y.count, m.count)
            guard n >= 20 else { continue }

            var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, w = 0.0
            for i in 0..<n {
                let ra = x[i], rb = y[i], wr = m[i]
                let k = min(ra.count, rb.count, wr.count)
                for j in 0..<k where wr[j] > 0.15 {
                    let g = wr[j]
                    let u = Double(ra[j]) * g, v = Double(rb[j]) * g
                    sx += u; sy += v; sxx += u * u; syy += v * v; sxy += u * v
                    w += g
                }
            }
            guard w > 12 else { continue }
            let num = sxy - sx * sy / w
            let den = ((sxx - sx * sx / w) * (syy - sy * sy / w)).squareRoot()
            if den > 1e-6 { best = max(best, num / den) }
        }
        return best
    }

    // MARK: - Méthodes de comparaison

    enum Method: String, CaseIterable, Identifiable {
        case simple      = "Corrélation"
        case blurred     = "Corrélation floutée"
        case descriptors = "Descripteurs"
        case combined    = "Combiné"
        case perCard     = "Auto"
        var id: String { rawValue }
    }

    nonisolated(unsafe) static var method: Method = .simple

    /// Méthode retenue carte par carte.
    ///
    /// Les sons brefs — squelettes, archères — gagnent au floutage, qui
    /// épaissit leur motif et lui permet de se superposer malgré un léger
    /// décalage. Les sons longs y perdent, le flou noyant leur structure.
    /// Corrélation simple et corrélation floutée produisent toutes deux des
    /// coefficients de Pearson, donc sur la même échelle : on peut choisir
    /// l'une ou l'autre selon la carte sans fausser la comparaison.
    private var perCardMethod: [String: Method] = [:]

    /// Choix de méthode fondé sur une PARTIE des exemples seulement.
    ///
    /// Le mode Auto décidait jusqu'ici en regardant tous les exemples, ceux
    /// du test compris : il connaissait donc les réponses au moment de
    /// choisir, et son score s'en trouvait flatté. En n'utilisant qu'une
    /// moitié pour décider, le test sur l'autre moitié devient honnête.
    func methodFor(_ id: String, learningOn pool: [String: [[[UInt8]]]]? = nil) -> Method {
        guard LearnedSounds.method == .perCard else { return LearnedSounds.method }
        let source = pool ?? store
        if pool == nil, let m = perCardMethod[id] { return m }

        var bestM = Method.simple
        var bestHits = -1
        for cand in [Method.simple, .blurred] {
            var hits = 0
            guard let list = source[id] else { continue }
            for (i, probe) in list.enumerated() {
                var top = ""
                var topScore = -2.0
                for (other, exs) in source {
                    for (j, ex) in exs.enumerated() {
                        if other == id && j == i { continue }
                        let v = cand == .simple
                            ? correlation(probe, ex)
                            : correlation(blur(probe), blur(ex))
                        if v > topScore { topScore = v; top = other }
                    }
                }
                if top == id { hits += 1 }
            }
            if hits > bestHits { bestHits = hits; bestM = cand }
        }
        if pool == nil { perCardMethod[id] = bestM }
        return bestM
    }


    func methodLabel(for id: String) -> String {
        switch methodFor(id) {
        case .blurred: return "flou"
        case .descriptors: return "desc"
        case .combined: return "mixte"
        default: return "corr"
        }
    }

    /// Flou léger : chaque case déborde sur ses voisines, si bien qu'un motif
    /// décalé d'une case continue de se superposer. Vise le décalage local en
    /// fréquence, celui que la recherche du meilleur décalage temporel ne
    /// rattrape pas.
    func blur(_ m: [[UInt8]]) -> [[UInt8]] {
        guard let bands = m.first?.count, bands > 2, m.count > 2 else { return m }
        var out = m
        for t in 0..<m.count {
            for b in 0..<bands {
                var sum = 0.0, w = 0.0
                for dt in -1...1 {
                    for db in -1...1 {
                        let tt = t + dt, bb = b + db
                        guard tt >= 0, tt < m.count, bb >= 0, bb < m[tt].count
                        else { continue }
                        // Centre plus lourd que les bords : on élargit le
                        // motif sans effacer sa forme.
                        let g = (dt == 0 && db == 0) ? 4.0
                              : (dt == 0 || db == 0) ? 2.0 : 1.0
                        sum += Double(m[tt][bb]) * g
                        w += g
                    }
                }
                out[t][b] = UInt8(max(0, min(255, Int(sum / max(w, 1)))))
            }
        }
        return out
    }

    /// Signature physique d'un son, insensible à sa position dans la fenêtre.
    ///
    /// Là où la corrélation demande « le pic est-il au même endroit ? », ces
    /// grandeurs demandent « quelle est la nature de ce son ? ». Un cliquetis
    /// d'os reste aigu et sec où qu'il tombe dans la fenêtre.
    struct Descriptors {
        var centroid = 0.0      // barycentre des fréquences
        var crest = 0.0         // pic sur moyenne : sec ou continu
        var attack = 0.0        // vitesse de montée
        var hfRatio = 0.0       // part de l'énergie dans les aigus
        var spread = 0.0        // étalement en fréquence

        func distance(to o: Descriptors) -> Double {
            let d = [(centroid - o.centroid) / 8,
                     (crest - o.crest) / 3,
                     (attack - o.attack) / 40,
                     (hfRatio - o.hfRatio),
                     (spread - o.spread) / 6]
            return (d.reduce(0) { $0 + $1 * $1 }).squareRoot()
        }
    }

    func descriptors(_ m: [[UInt8]]) -> Descriptors {
        var d = Descriptors()
        guard let bands = m.first?.count, bands > 0, !m.isEmpty else { return d }

        var energy = [Double](repeating: 0, count: m.count)
        var bandSum = [Double](repeating: 0, count: bands)
        var total = 0.0
        for (t, row) in m.enumerated() {
            for b in 0..<min(bands, row.count) {
                let v = Double(row[b])
                energy[t] += v
                bandSum[b] += v
                total += v
            }
        }
        guard total > 1 else { return d }

        // Centroïde et étalement spectral
        var num = 0.0
        for b in 0..<bands { num += Double(b) * bandSum[b] }
        d.centroid = num / total
        var varr = 0.0
        for b in 0..<bands {
            let dx = Double(b) - d.centroid
            varr += dx * dx * bandSum[b]
        }
        d.spread = (varr / total).squareRoot()

        // Facteur de crête : un son percussif domine sa propre fenêtre
        let peak = energy.max() ?? 0
        let mean = energy.reduce(0, +) / Double(energy.count)
        d.crest = mean > 0.01 ? peak / mean : 0

        // Pente d'attaque : plus forte montée d'une trame à la suivante
        var slope = 0.0
        for i in 1..<energy.count { slope = max(slope, energy[i] - energy[i - 1]) }
        d.attack = slope / Double(bands)

        // Répartition aigus / graves
        let half = bands / 2
        let lf = bandSum[0..<half].reduce(0, +)
        let hf = bandSum[half...].reduce(0, +)
        d.hfRatio = (lf + hf) > 0 ? hf / (lf + hf) : 0
        return d
    }

    /// Score selon la méthode retenue, toujours ramené sur l'échelle de la
    /// corrélation pour rester comparable d'une carte à l'autre.
    func similarity(_ a: [[UInt8]], _ b: [[UInt8]], for id: String? = nil) -> Double {
        let m = id.map { methodFor($0) } ?? LearnedSounds.method
        switch m {
        case .perCard:
            // methodFor ne renvoie jamais .perCard ; ce cas n'arrive que si
            // aucune carte n'est précisée, et la corrélation fait alors foi.
            return correlation(a, b)
        case .simple:
            return correlation(a, b)
        case .blurred:
            return correlation(blur(a), blur(b))
        case .descriptors:
            let dist = descriptors(a).distance(to: descriptors(b))
            return 1 - min(1, dist)          // 1 = identique
        case .combined:
            let c = correlation(a, b)
            let dist = descriptors(a).distance(to: descriptors(b))
            return 0.6 * c + 0.4 * (1 - min(1, dist))
        }
    }

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
