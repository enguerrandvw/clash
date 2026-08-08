import Foundation
import ActivityKit

// Décrit les données qui transitent entre l'app et la Dynamic Island.
struct ElixirAttributes: ActivityAttributes {

    // Ce qui change pendant la partie
    struct ContentState: Codable, Hashable {
        var elixir: Double     // élixir estimé de l'adversaire (0 à 10)
        var rate: Int          // 1 = normal, 2 = double, 3 = triple
        var startDate: Date    // début de la partie (pour le chrono auto)
    }

    // Ce qui ne change pas
    var matchName: String
}
