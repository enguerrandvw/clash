import Foundation
import SwiftUI

@MainActor
final class ElixirEngine: ObservableObject {

    @Published var elixir: Double = 5
    @Published var rate: Int = 1
    @Published var running: Bool = false
    @Published var status: String = "Prêt"
    @Published var autoRate = true        // passage x2/x3 automatique
    @Published var elapsed: Double = 0    // secondes depuis le début du match

    // Seuils officiels : x2 à 2:00, x3 à 4:00
    private let doubleAt: Double = 120
    private let tripleAt: Double = 240
    private var matchStart = Date()

    let overlay = PiPOverlay()
    let voice = VoiceRecognizer()

    private let baseSeconds: Double = 2.8
    private var timer: Timer?
    private var anchorDate = Date()
    private var secondsPerElixir: Double { baseSeconds / Double(rate) }

    init() {
        setElixir(5)
        pushToOverlay()
        // Une carte annoncée = son coût déduit de l'élixir adverse
        voice.onCard = { [weak self] card in
            Task { @MainActor in self?.spend(card.cost) }
        }
        // « sept » → l'élixir adverse est mis à 7 et repart de là
        voice.onElixir = { [weak self] value in
            Task { @MainActor in self?.setElixirTo(value) }
        }
    }

    // MARK: - Contrôles

    func start() {
        guard !running else { return }
        rate = 1
        setElixir(5)
        matchStart = Date()
        elapsed = 0
        autoRate = true
        running = true
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
        autoRate = false          // choix manuel : on n'écrase plus
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
        elapsed = Date().timeIntervalSince(matchStart)

        if autoRate {
            let target = elapsed >= tripleAt ? 3 : (elapsed >= doubleAt ? 2 : 1)
            if target != rate {
                let keep = currentValue()
                rate = target
                setElixir(keep)      // on garde la valeur, on change la pente
            }
        }

        elixir = currentValue()
        pushToOverlay()
        refreshStatus()
    }

    /// Fixe directement l'élixir (commande vocale « sept »).
    func setElixirTo(_ value: Int) {
        guard running else { return }
        setElixir(min(10, max(0, Double(value))))
        pushToOverlay()
    }

    private func refreshStatus() {
        let m = Int(elapsed) / 60, sec = Int(elapsed) % 60
        status = String(format: "En cours · %d:%02d · x%d%@",
                        m, sec, rate, autoRate ? " auto" : " manuel")
    }

    private func pushToOverlay() {
        overlay.elixir = elixir
        overlay.rate = rate
    }
}
