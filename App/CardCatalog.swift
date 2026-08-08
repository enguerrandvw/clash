import Foundation

struct Card: Identifiable, Hashable {
    let id: String
    let name: String
    let cost: Int
    let aliases: [String]
}

enum CardCatalog {

    // 122 cartes jouables — liste et coûts vérifiés en août 2026.
    // Le Miroir a un coût variable : représenté par 0.
    // Les cartes Héros sont des variantes des cartes ci-dessous (même coût de base).
    static let all: [Card] = [
        // --- coût variable ---
        Card(id: "miroir", name: "Miroir", cost: 0, aliases: ["mirror"]),

        // --- 1 élixir ---
        Card(id: "esprit-de-feu", name: "Esprit de feu", cost: 1, aliases: ["esprit feu", "fire spirit"]),
        Card(id: "esprit-de-glace", name: "Esprit de glace", cost: 1, aliases: ["esprit glace", "ice spirit"]),
        Card(id: "esprit-de-soin", name: "Esprit de soin", cost: 1, aliases: ["esprit soin", "heal spirit"]),
        Card(id: "esprit-electrique", name: "Esprit électrique", cost: 1, aliases: ["esprit electrique", "electro spirit"]),
        Card(id: "squelettes", name: "Squelettes", cost: 1, aliases: ["skarmy non", "squelette", "skeletons"]),

        // --- 2 élixir ---
        Card(id: "berserker", name: "Berserker", cost: 2, aliases: []),
        Card(id: "bombardier", name: "Bombardier", cost: 2, aliases: ["bomber"]),
        Card(id: "boule-de-neige-geante", name: "Boule de neige géante", cost: 2, aliases: ["boule neige", "snowball", "giant snowball"]),
        Card(id: "buisson-suspect", name: "Buisson suspect", cost: 2, aliases: ["buisson", "suspicious bush"]),
        Card(id: "casseurs-de-murs", name: "Casseurs de murs", cost: 2, aliases: ["casseurs murs", "wall breakers"]),
        Card(id: "chauves-souris", name: "Chauves-souris", cost: 2, aliases: ["bats", "chauve souris"]),
        Card(id: "decharge", name: "Décharge", cost: 2, aliases: ["zap", "decharge"]),
        Card(id: "fut-a-barbares", name: "Fût à barbares", cost: 2, aliases: ["fut barbares", "barb barrel", "barbarian barrel"]),
        Card(id: "gobelins", name: "Gobelins", cost: 2, aliases: ["gob", "goblins"]),
        Card(id: "gobelins-a-lances", name: "Gobelins à lances", cost: 2, aliases: ["gobelins lances", "spear", "spear goblins"]),
        Card(id: "golem-de-glace", name: "Golem de glace", cost: 2, aliases: ["golem glace", "ice golem"]),
        Card(id: "la-buche", name: "La Bûche", cost: 2, aliases: ["buche", "log", "la buche", "the log"]),
        Card(id: "malediction-gobeline", name: "Malédiction gobeline", cost: 2, aliases: ["malediction", "goblin curse"]),
        Card(id: "rage", name: "Rage", cost: 2, aliases: []),

        // --- 3 élixir ---
        Card(id: "archeres", name: "Archères", cost: 3, aliases: ["archers", "archere"]),
        Card(id: "armee-de-squelettes", name: "Armée de squelettes", cost: 3, aliases: ["armee squelettes", "skarmy", "skeleton army"]),
        Card(id: "bandite", name: "Bandite", cost: 3, aliases: ["bandit"]),
        Card(id: "baril-de-gobelins", name: "Baril de gobelins", cost: 3, aliases: ["baril gobelins", "goblin barrel", "baril"]),
        Card(id: "baril-de-squelettes", name: "Baril de squelettes", cost: 3, aliases: ["baril squelettes", "skeleton barrel"]),
        Card(id: "canon", name: "Canon", cost: 3, aliases: ["cannon"]),
        Card(id: "chevalier", name: "Chevalier", cost: 3, aliases: ["knight"]),
        Card(id: "clonage", name: "Clonage", cost: 3, aliases: ["clone"]),
        Card(id: "fantome-royal", name: "Fantôme royal", cost: 3, aliases: ["fantome royal", "ghost", "royal ghost"]),
        Card(id: "fleches", name: "Flèches", cost: 3, aliases: ["fleches", "arrows"]),
        Card(id: "gang-de-gobelins", name: "Gang de gobelins", cost: 3, aliases: ["gang", "goblin gang"]),
        Card(id: "gardes", name: "Gardes", cost: 3, aliases: ["guards"]),
        Card(id: "gargouilles", name: "Gargouilles", cost: 3, aliases: ["minions"]),
        Card(id: "gobelin-a-sarbacane", name: "Gobelin à sarbacane", cost: 3, aliases: ["sarbacane", "dart goblin"]),
        Card(id: "golem-d-elixir", name: "Golem d'élixir", cost: 3, aliases: ["golem elixir", "elixir golem"]),
        Card(id: "lianes", name: "Lianes", cost: 3, aliases: ["vines"]),
        Card(id: "livraison-royale", name: "Livraison royale", cost: 3, aliases: ["livraison", "royal delivery"]),
        Card(id: "mineur", name: "Mineur", cost: 3, aliases: ["miner"]),
        Card(id: "mega-gargouille", name: "Méga gargouille", cost: 3, aliases: ["mega gargouille", "mega minion"]),
        Card(id: "petit-prince", name: "Petit prince", cost: 3, aliases: ["petit prince", "little prince"]),
        Card(id: "pierre-tombale", name: "Pierre tombale", cost: 3, aliases: ["tombale", "tombstone"]),
        Card(id: "princesse", name: "Princesse", cost: 3, aliases: ["princess"]),
        Card(id: "petardiere", name: "Pétardière", cost: 3, aliases: ["petardiere", "firecracker"]),
        Card(id: "pecheur", name: "Pêcheur", cost: 3, aliases: ["pecheur", "fisherman"]),
        Card(id: "sorcier-de-glace", name: "Sorcier de glace", cost: 3, aliases: ["sorcier glace", "ice wizard"]),
        Card(id: "seisme", name: "Séisme", cost: 3, aliases: ["seisme", "earthquake"]),
        Card(id: "tornade", name: "Tornade", cost: 3, aliases: ["tornado", "nado"]),

        // --- 4 élixir ---
        Card(id: "archer-magique", name: "Archer magique", cost: 4, aliases: ["archer magique", "magic archer"]),
        Card(id: "boule-de-feu", name: "Boule de feu", cost: 4, aliases: ["boule feu", "fireball"]),
        Card(id: "bebe-dragon", name: "Bébé dragon", cost: 4, aliases: ["bebe dragon", "baby dragon"]),
        Card(id: "belier-de-combat", name: "Bélier de combat", cost: 4, aliases: ["belier", "battle ram"]),
        Card(id: "bucheron", name: "Bûcheron", cost: 4, aliases: ["bucheron", "lumberjack"]),
        Card(id: "cabane-de-gobelins", name: "Cabane de gobelins", cost: 4, aliases: ["cabane gobelins", "goblin hut"]),
        Card(id: "cage-a-gobelins", name: "Cage à gobelins", cost: 4, aliases: ["cage gobelins", "goblin cage"]),
        Card(id: "chasseur", name: "Chasseur", cost: 4, aliases: ["hunter"]),
        Card(id: "chevalier-d-or", name: "Chevalier d'or", cost: 4, aliases: ["chevalier or", "golden knight"]),
        Card(id: "chevaucheur-de-cochon", name: "Chevaucheur de cochon", cost: 4, aliases: ["cochon", "hog", "chevaucheur", "hog rider"]),
        Card(id: "dragon-de-l-inferno", name: "Dragon de l'inferno", cost: 4, aliases: ["dragon inferno", "inferno dragon"]),
        Card(id: "dragons-squelettes", name: "Dragons squelettes", cost: 4, aliases: ["dragons squelette", "skeleton dragons"]),
        Card(id: "foreuse-gobeline", name: "Foreuse gobeline", cost: 4, aliases: ["foreuse", "drill", "goblin drill"]),
        Card(id: "fournaise", name: "Fournaise", cost: 4, aliases: ["furnace"]),
        Card(id: "gel", name: "Gel", cost: 4, aliases: ["freeze"]),
        Card(id: "gobelin-demolisseur", name: "Gobelin démolisseur", cost: 4, aliases: ["demolisseur", "goblin demolisher"]),
        Card(id: "geant-runique", name: "Géant runique", cost: 4, aliases: ["geant runique", "rune giant"]),
        Card(id: "machine-volante", name: "Machine volante", cost: 4, aliases: ["machine volante", "flying machine"]),
        Card(id: "mineur-costaud", name: "Mineur costaud", cost: 4, aliases: ["mineur costaud", "mighty miner"]),
        Card(id: "mini-p-e-k-k-a", name: "Mini P.E.K.K.A", cost: 4, aliases: ["mini pekka", "mini peka"]),
        Card(id: "mortier", name: "Mortier", cost: 4, aliases: ["mortar"]),
        Card(id: "mousquetaire", name: "Mousquetaire", cost: 4, aliases: ["mousquet", "musketeer"]),
        Card(id: "phenix", name: "Phénix", cost: 4, aliases: ["phenix", "phoenix"]),
        Card(id: "poison", name: "Poison", cost: 4, aliases: []),
        Card(id: "prince-tenebreux", name: "Prince ténébreux", cost: 4, aliases: ["prince tenebreux", "dark prince"]),
        Card(id: "roi-squelette", name: "Roi squelette", cost: 4, aliases: ["roi squelette", "skeleton king"]),
        Card(id: "soigneuse", name: "Soigneuse", cost: 4, aliases: ["healer", "soigneur", "battle healer"]),
        Card(id: "sorcier-electrique", name: "Sorcier électrique", cost: 4, aliases: ["sorcier electrique", "ewiz", "electro wizard"]),
        Card(id: "sorciere-mere", name: "Sorcière mère", cost: 4, aliases: ["sorciere mere", "mother witch"]),
        Card(id: "sorciere-noire", name: "Sorcière noire", cost: 4, aliases: ["sorciere noire", "night witch"]),
        Card(id: "tesla", name: "Tesla", cost: 4, aliases: []),
        Card(id: "tour-de-bombes", name: "Tour de bombes", cost: 4, aliases: ["tour bombes", "bomb tower"]),
        Card(id: "valkyrie", name: "Valkyrie", cost: 4, aliases: ["valk"]),
        Card(id: "zappy", name: "Zappy", cost: 4, aliases: ["zappies"]),

        // --- 5 élixir ---
        Card(id: "ballon", name: "Ballon", cost: 5, aliases: ["balloon"]),
        Card(id: "barbares", name: "Barbares", cost: 5, aliases: ["barbarians"]),
        Card(id: "bouliste", name: "Bouliste", cost: 5, aliases: ["bowler"]),
        Card(id: "bourreau", name: "Bourreau", cost: 5, aliases: ["executioner", "exe"]),
        Card(id: "canon-a-roulettes", name: "Canon à roulettes", cost: 5, aliases: ["canon roulettes", "cannon cart"]),
        Card(id: "chenapans", name: "Chenapans", cost: 5, aliases: ["rascals"]),
        Card(id: "chevaucheuse-de-belier", name: "Chevaucheuse de bélier", cost: 5, aliases: ["chevaucheuse belier", "ram rider"]),
        Card(id: "cimetiere", name: "Cimetière", cost: 5, aliases: ["cimetiere", "graveyard", "gy"]),
        Card(id: "cochons-royaux", name: "Cochons royaux", cost: 5, aliases: ["cochons royaux", "royal hogs"]),
        Card(id: "dragon-electrique", name: "Dragon électrique", cost: 5, aliases: ["dragon electrique", "edrag", "electro dragon"]),
        Card(id: "goblinstein", name: "Goblinstein", cost: 5, aliases: []),
        Card(id: "geant", name: "Géant", cost: 5, aliases: ["geant", "giant"]),
        Card(id: "horde-de-gargouilles", name: "Horde de gargouilles", cost: 5, aliases: ["horde", "minion horde"]),
        Card(id: "machine-gobeline", name: "Machine gobeline", cost: 5, aliases: ["machine gobeline", "goblin machine"]),
        Card(id: "moine", name: "Moine", cost: 5, aliases: ["monk"]),
        Card(id: "prince", name: "Prince", cost: 5, aliases: []),
        Card(id: "reine-des-archers", name: "Reine des archers", cost: 5, aliases: ["reine archers", "archer queen"]),
        Card(id: "ronin", name: "Ronin", cost: 5, aliases: []),
        Card(id: "sorcier", name: "Sorcier", cost: 5, aliases: ["wizard"]),
        Card(id: "sorciere", name: "Sorcière", cost: 5, aliases: ["witch"]),
        Card(id: "tour-de-l-inferno", name: "Tour de l'inferno", cost: 5, aliases: ["tour inferno", "inferno tower"]),
        Card(id: "vide", name: "Vide", cost: 5, aliases: ["void"]),

        // --- 6 élixir ---
        Card(id: "arc-x", name: "Arc-X", cost: 6, aliases: ["arc x", "xbow", "x-bow"]),
        Card(id: "barbares-d-elite", name: "Barbares d'élite", cost: 6, aliases: ["elite", "ebarbs", "elite barbarians"]),
        Card(id: "boss-bandite", name: "Boss bandite", cost: 6, aliases: ["boss bandit"]),
        Card(id: "extracteur-d-elixir", name: "Extracteur d'élixir", cost: 6, aliases: ["extracteur", "pompe", "elixir collector"]),
        Card(id: "foudre", name: "Foudre", cost: 6, aliases: ["lightning"]),
        Card(id: "gobelin-geant", name: "Gobelin géant", cost: 6, aliases: ["gobelin geant", "goblin giant"]),
        Card(id: "geant-royal", name: "Géant royal", cost: 6, aliases: ["gr", "geant royal", "royal giant"]),
        Card(id: "imperatrice-des-esprits", name: "Impératrice des esprits", cost: 6, aliases: ["imperatrice", "spirit empress"]),
        Card(id: "roquette", name: "Roquette", cost: 6, aliases: ["rocket"]),
        Card(id: "sparky", name: "Sparky", cost: 6, aliases: []),
        Card(id: "squelette-geant", name: "Squelette géant", cost: 6, aliases: ["squelette geant", "giant skeleton"]),

        // --- 7 élixir ---
        Card(id: "cabane-de-barbares", name: "Cabane de barbares", cost: 7, aliases: ["cabane barbares", "barbarian hut"]),
        Card(id: "geant-electrique", name: "Géant électrique", cost: 7, aliases: ["geant electrique", "electro giant"]),
        Card(id: "molosse-de-lave", name: "Molosse de lave", cost: 7, aliases: ["molosse", "lava hound", "lavaloon non"]),
        Card(id: "mega-chevalier", name: "Méga-chevalier", cost: 7, aliases: ["mega chevalier", "mega knight", "mk"]),
        Card(id: "p-e-k-k-a", name: "P.E.K.K.A", cost: 7, aliases: ["pekka", "peka"]),
        Card(id: "recrues-royales", name: "Recrues royales", cost: 7, aliases: ["recrues", "royal recruits"]),

        // --- 8 élixir ---
        Card(id: "golem", name: "Golem", cost: 8, aliases: []),

        // --- 9 élixir ---
        Card(id: "trois-mousquetaires", name: "Trois mousquetaires", cost: 9, aliases: ["trois mousquet", "3 mousquetaires", "three musketeers"]),
    ]

    // MARK: - Correspondance approximative

    /// Renvoie la carte la plus proche d'une phrase et un score de 0 à 1.
    static func match(_ phrase: String) -> (card: Card, score: Double)? {
        let needle = normalize(phrase)
        guard needle.count >= 3 else { return nil }
        let needleWords = needle.split(separator: " ").map(String.init)

        var best: (Card, Double)?
        for card in all {
            var candidates = [card.name] + card.aliases
            candidates.append(card.id.replacingOccurrences(of: "-", with: " "))
            for c in candidates {
                let form = normalize(c)
                guard form.count >= 3 else { continue }
                var s = similarity(needle, form)

                // La forme apparaît telle quelle dans la phrase entendue
                if form.count >= 4 && needle.contains(form) { s = max(s, 0.96) }

                // Tous les mots de la forme sont présents, même dispersés
                let formWords = form.split(separator: " ").map(String.init)
                if !formWords.isEmpty,
                   formWords.allSatisfy({ needleWords.contains($0) }) {
                    s = max(s, 0.93)
                }

                // Comparaison mot à mot : encaisse les pluriels et petites erreurs
                for nw in needleWords where nw.count >= 4 {
                    for fw in formWords where fw.count >= 4 {
                        s = max(s, similarity(nw, fw) * 0.95)
                    }
                }

                if s > (best?.1 ?? 0) { best = (card, s) }
            }
        }
        return best
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr"))
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let d = levenshtein(Array(a), Array(b))
        return 1.0 - Double(d) / Double(max(a.count, b.count))
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1,
                             cur[j - 1] + 1,
                             prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
