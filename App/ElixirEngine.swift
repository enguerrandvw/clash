import Foundation
import ActivityKit

@MainActor
final class ElixirEngine: ObservableObject {

    @Published var elixir: Double = 5
    @Published var rate: Int = 1
    @Published var running: Bool = false
    @Published var status: String = "Prêt"

    // 1 point d'élixir toutes les 2,8 secondes en vitesse normale
    private let secondsPerElixir: Double = 2.8

    private var timer: Timer?
    private var activity: Activity<ElixirAttributes>?
    private var startDate = Date()
    private var lastPush = Date.distantPast

    // MARK: - Contrôles

    func start() {
        guard !running else { return }
        elixir = 5
        rate = 1
        startDate = Date()
        running = true

        KeepAlive.shared.start()
        startActivity()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(0.1) }
        }
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        KeepAlive.shared.stop()
        status = "Arrêté"

        let current = activity
        activity = nil
        Task { await current?.end(nil, dismissalPolicy: .immediate) }
    }

    // L'adversaire pose une carte qui coûte `cost`
    func spend(_ cost: Int) {
        guard running else { return }
        elixir = max(0, elixir - Double(cost))
        push(force: true)
    }

    func setRate(_ newRate: Int) {
        rate = newRate
        push(force: true)
    }

    // MARK: - Boucle

    private func tick(_ dt: Double) {
        guard running else { return }
        elixir = min(10, elixir + dt * Double(rate) / secondsPerElixir)
        push(force: false)
    }

    // MARK: - Live Activity

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Live Activities désactivées dans Réglages"
            return
        }
        let attributes = ElixirAttributes(matchName: "Partie")
        let state = ElixirAttributes.ContentState(elixir: elixir, rate: rate, startDate: startDate)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            status = "Live Activity active"
        } catch {
            status = "Erreur: \(error.localizedDescription)"
        }
    }

    // On limite les mises à jour à environ 1 par seconde (iOS bride au-delà)
    private func push(force: Bool) {
        let now = Date()
        if !force && now.timeIntervalSince(lastPush) < 1.0 { return }
        lastPush = now

        guard let activity else { return }
        let state = ElixirAttributes.ContentState(elixir: elixir, rate: rate, startDate: startDate)
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}
