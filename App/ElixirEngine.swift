import Foundation
import ActivityKit

@MainActor
final class ElixirEngine: ObservableObject {

    @Published var elixir: Double = 5
    @Published var rate: Int = 1
    @Published var running: Bool = false
    @Published var status: String = "Prêt"
    @Published var lag: Double = 0        // diagnostic arrière-plan

    private let baseSeconds: Double = 2.8

    private var timer: Timer?
    private var activity: Activity<ElixirAttributes>?

    // Source de vérité unique : l'instant où l'élixir valait 0
    private var anchorDate = Date()
    private var matchStart = Date()
    private var ticks: Double = 0

    private var secondsPerElixir: Double { baseSeconds / Double(rate) }

    // MARK: - Contrôles

    func start() { Task { await beginMatch() } }
    func stop()  { Task { await endMatch() } }

    private func beginMatch() async {
        for old in Activity<ElixirAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil

        rate = 1
        matchStart = Date()
        ticks = 0
        lag = 0
        setElixir(5)              // départ à 5
        running = true

        KeepAlive.shared.start()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Live Activities désactivées dans Réglages"
            return
        }
        do {
            activity = try Activity.request(
                attributes: ElixirAttributes(matchName: "Partie"),
                content: ActivityContent(state: currentState(), staleDate: nil),
                pushType: nil
            )
            status = "En cours"
        } catch {
            status = "Erreur: \(error.localizedDescription)"
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func endMatch() async {
        running = false
        timer?.invalidate()
        timer = nil
        KeepAlive.shared.stop()

        for old in Activity<ElixirAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        status = "Arrêté"
    }

    // MARK: - Actions (ce sont les SEULS moments où l'on pousse une mise à jour)

    func spend(_ cost: Int) {
        guard running else { return }
        setElixir(max(0, currentValue() - Double(cost)))
        push()
    }

    func setRate(_ newRate: Int) {
        let keep = currentValue()
        rate = newRate
        setElixir(keep)           // on conserve la valeur, on change la pente
        push()
    }

    // MARK: - Calculs

    private func currentValue() -> Double {
        min(10, max(0, Date().timeIntervalSince(anchorDate) / secondsPerElixir))
    }

    private func setElixir(_ value: Double) {
        anchorDate = Date().addingTimeInterval(-value * secondsPerElixir)
        elixir = value
    }

    // Le tick ne sert qu'à l'affichage DANS l'app + au diagnostic.
    // Il n'envoie plus rien à la Dynamic Island.
    private func tick() {
        guard running else { return }
        elixir = currentValue()
        ticks += 0.1
        let real = Date().timeIntervalSince(matchStart)
        lag = max(0, real - ticks)
        if running {
            status = lag < 1.5
                ? "En cours — app active"
                : String(format: "App suspendue %.0fs", lag)
        }
    }

    private func currentState() -> ElixirAttributes.ContentState {
        ElixirAttributes.ContentState(
            anchorDate: anchorDate,
            secondsPerElixir: secondsPerElixir,
            rate: rate,
            snapshot: currentValue()
        )
    }

    private func push() {
        guard let activity else { return }
        let state = currentState()
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }
}
