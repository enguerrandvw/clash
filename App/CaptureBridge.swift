import SwiftUI
import ReplayKit

// Côté app : lit ce que l'extension de capture dépose dans l'espace partagé.
@MainActor
final class CaptureBridge: ObservableObject {

    static let groupID = "group.com.monprojet.clashelixir"

    @Published var note = "—"
    @Published var frames = 0
    @Published var audioBuffers = 0
    @Published var audioPeak: Float = 0
    @Published var elapsed: Double = 0
    @Published var freshness = "aucune donnée"
    @Published var screenshot: UIImage?
    @Published var band: UIImage?
    @Published var groupOK = false

    private var timer: Timer?

    private var dir: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupID)
    }

    init() {
        // Test décisif : l'App Group a-t-il survécu à la resignature ?
        groupOK = dir != nil
    }

    func startWatching() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopWatching() {
        timer?.invalidate(); timer = nil
    }

    func reset() {
        guard let dir else { return }
        for f in ["state.json", "frame.jpg", "band.jpg"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
        frames = 0; audioBuffers = 0; audioPeak = 0
        screenshot = nil; band = nil; note = "—"
    }

    private func refresh() {
        guard let dir else { freshness = "App Group indisponible"; return }

        if let d = try? Data(contentsOf: dir.appendingPathComponent("state.json")),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            note          = j["note"] as? String ?? "—"
            frames        = j["frames"] as? Int ?? 0
            audioBuffers  = j["audioBuffers"] as? Int ?? 0
            audioPeak     = j["audioPeak"] as? Float ?? 0
            elapsed       = j["elapsed"] as? Double ?? 0
            if let at = j["at"] as? Double {
                let age = Date().timeIntervalSince1970 - at
                freshness = age < 1.5
                    ? String(format: "en direct (%.1f s)", age)
                    : String(format: "figé depuis %.0f s", age)
            }
        } else {
            freshness = "aucun fichier reçu"
        }

        if let d = try? Data(contentsOf: dir.appendingPathComponent("frame.jpg")) {
            screenshot = UIImage(data: d)
        }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("band.jpg")) {
            band = UIImage(data: d)
        }
    }
}

// Bouton système qui lance ou arrête la diffusion d'écran
struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = "com.monprojet.clashelixir.broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
