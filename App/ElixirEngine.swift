import Foundation
import SwiftUI

@MainActor
final class ElixirEngine: ObservableObject {

    @Published var elixir: Double = 5
    @Published var rate: Int = 1
    @Published var running: Bool = false
    @Published var status: String = "Prêt"

    let overlay = PiPOverlay()

    private let baseSeconds: Double = 2.8
    private var timer: Timer?
    private var anchorDate = Date()
    private var secondsPerElixir: Double { baseSeconds / Double(rate) }

    init() {
        setElixir(5)
        pushToOverlay()
    }

    // MARK: - Contrôles

    func start() {
        guard !running else { return }
        rate = 1
        setElixir(5)
        running = true
        status = "En cours"
        overlay.start()

        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        overlay.stop()
        status = "Arrêté"
    }

    func spend(_ cost: Int) {
        guard running else { return }
        setElixir(max(0, currentValue() - Double(cost)))
        pushToOverlay()
    }

    func setRate(_ newRate: Int) {
        let keep = currentValue()
        rate = newRate
        setElixir(keep)
        pushToOverlay()
    }

    // MARK: - Calculs

    private func currentValue() -> Double {
        min(10, max(0, Date().timeIntervalSince(anchorDate) / secondsPerElixir))
    }

    private func setElixir(_ value: Double) {
        anchorDate = Date().addingTimeInterval(-value * secondsPerElixir)
        elixir = value
    }

    private func tick() {
        guard running else { return }
        elixir = currentValue()
        pushToOverlay()
    }

    private func pushToOverlay() {
        overlay.elixir = elixir
        overlay.rate = rate
    }
}
