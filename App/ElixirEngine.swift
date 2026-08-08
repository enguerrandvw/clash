import Foundation
import ActivityKit

@MainActor
final class ElixirEngine: ObservableObject {

    @Published var elixir: Double = 5
    @Published var rate: Int = 1
    @Published var running: Bool = false
    @Published var status: String = "Prêt"

    private let secondsPerElixir: Double = 2.8

    private var timer: Timer?
    private var activity: Activity<ElixirAttributes>?
    private var startDate = Date()
    private var lastPush = Date.distantPast

    // MARK: - Contrôles

    func start() {
        guard !running else { return }
        Task { await beginMatch() }
    }

    func stop() {
        Task { await endMatch() }
    }

    private func beginMatch() async {
        // 1. On ferme TOUTES les activités encore en vie, et on attend vraiment
        for old in Activity<ElixirAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil

        // 2. Remise à zéro
        elixir = 5
        rate = 1
        startDate = Date()
        lastPush = .distantPast
        running = true

        KeepAlive.shared.start()

        // 3. Nouvelle Live Activity
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Live Activities désactivées dans Réglages"
            return
        }
        do {
            activity = try Activity.request(
                attributes: ElixirAttributes(matchName: "Partie"),
                content: ActivityContent(
                    state: ElixirAttributes.ContentState(
                        elixir: elixir, rate: rate, startDate: startDate),
                    staleDate: nil),
                pushType: nil
            )
            status = "En cours"
        } catch {
            status = "Erreur: \(error.localizedDescription)"
        }

        // 4. Chrono
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(0.1) }
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

    func spend(_ cost: Int) {
        guard running else { return }
        elixir = max(0, elixir - Double(cost))
        push(force: true)
    }

    func setRate(_ newRate: Int) {
        rate = newRate
        push(force: true)
    }

    private func tick(_ dt: Double) {
        guard running else { return }
        elixir = min(10, elixir + dt * Double(rate) / secondsPerElixir)
        push(force: false)
    }

    private func push(force: Bool) {
        let now = Date()
        if !force && now.timeIntervalSince(lastPush) < 1.0 { return }
        lastPush = now

        guard let activity else { return }
        let state = ElixirAttributes.ContentState(elixir: elixir, rate: rate, startDate: startDate)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }
}
