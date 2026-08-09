import SwiftUI
import ReplayKit
import Network

// Reçoit les mesures de l'extension de capture par socket locale.
@MainActor
final class CaptureBridge: ObservableObject {

    @Published var note = "—"
    @Published var frames = 0
    @Published var audioBuffers = 0
    @Published var audioPeak: Float = 0
    @Published var band: [Int] = []
    @Published var freshness = "aucune donnée"
    @Published var listening = false
    @Published var lastError: String?

    /// Identifiant réel de l'extension, calculé à l'exécution.
    /// Indispensable : Ksign réécrit souvent l'identifiant à la resignature.
    static var extensionID: String {
        (Bundle.main.bundleIdentifier ?? "com.monprojet.clashelixir") + ".broadcast"
    }

    private var listener: NWListener?
    private var lastPacket = Date.distantPast
    private var tick: Timer?

    func startListening() {
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: .udp, on: 45678)
            l.newConnectionHandler = { [weak self] c in
                c.start(queue: .main)
                self?.receive(on: c)
            }
            l.stateUpdateHandler = { [weak self] st in
                Task { @MainActor in
                    switch st {
                    case .ready:  self?.listening = true;  self?.lastError = nil
                    case .failed(let e): self?.listening = false
                                         self?.lastError = e.localizedDescription
                    default: break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            lastError = "Écoute impossible : \(error.localizedDescription)"
        }

        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateFreshness() }
        }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    func stopListening() {
        listener?.cancel(); listener = nil
        tick?.invalidate(); tick = nil
        listening = false
    }

    func reset() {
        frames = 0; audioBuffers = 0; audioPeak = 0; band = []; note = "—"
    }

    private func receive(on c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, _ in
            if let data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Task { @MainActor in
                    guard let self else { return }
                    self.note         = j["note"] as? String ?? "—"
                    self.frames       = j["frames"] as? Int ?? 0
                    self.audioBuffers = j["audioBuffers"] as? Int ?? 0
                    self.audioPeak    = j["audioPeak"] as? Float ?? 0
                    self.band         = j["band"] as? [Int] ?? []
                    self.lastPacket   = Date()
                }
            }
            self?.receive(on: c)
        }
    }

    private func updateFreshness() {
        let age = Date().timeIntervalSince(lastPacket)
        freshness = age < 2
            ? String(format: "en direct (%.1f s)", age)
            : (lastPacket == .distantPast ? "aucun paquet reçu"
                                          : String(format: "figé depuis %.0f s", age))
    }
}

// Bouton système de diffusion. L'identifiant de l'extension est résolu à l'exécution.
struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = CaptureBridge.extensionID
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
