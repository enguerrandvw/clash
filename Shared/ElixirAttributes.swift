import Foundation
import ActivityKit

// Le principe : on ne transmet plus la valeur d'élixir, mais la DATE
// à laquelle l'élixir valait 0. Le widget en déduit tout seul la valeur
// courante et s'anime sans consommer le quota de mises à jour d'iOS.
struct ElixirAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var anchorDate: Date          // instant théorique où l'élixir valait 0
        var secondsPerElixir: Double  // 2.8 en x1, 1.4 en x2, 0.933 en x3
        var rate: Int                 // 1, 2 ou 3 (affichage seulement)
        var snapshot: Double          // valeur au moment de l'envoi (repli)
    }

    var matchName: String
}

extension ElixirAttributes.ContentState {

    // Intervalle sur lequel la barre se remplit de 0 à 10
    var fillRange: ClosedRange<Date> {
        let end = anchorDate.addingTimeInterval(10 * secondsPerElixir)
        return anchorDate...max(end, anchorDate.addingTimeInterval(0.1))
    }

    // Valeur au moment du rendu
    func value(at date: Date) -> Double {
        min(10, max(0, date.timeIntervalSince(anchorDate) / secondsPerElixir))
    }
}
