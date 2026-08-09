import SwiftUI
import ReplayKit
import Network

// Reçoit les mesures de l'extension de capture par socket locale.
@MainActor
final class CaptureBridge: ObservableObject {

    /// Instance unique : l'écoute doit survivre à la fermeture du diagnostic.
    static let shared = CaptureBridge()

    /// Élixir lu sur TA barre. -1 tant qu'aucune mesure fiable n'est arrivée.
    @Published var myElixir: Int = -1

    @Published var note = "—"
    @Published var frames = 0
    @Published var audioBuffers = 0
    @Published var audioPeak: Float = 0
    @Published var audioPeakMax: Float = 0
    @Published var band: [Int] = []
    @Published var rowProfile: [Int] = []
    @Published var digitImage: UIImage?
    @Published var bestRowFrac: Double = 0
    @Published var pixelFormat = "?"
    @Published var audioFormat = "?"
    @Published var memoryMB: Double = 0
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

    // nonisolated : les rappels réseau n'arrivent pas sur le fil principal.
    // Les mises à jour d'interface repassent explicitement par @MainActor.
    private nonisolated func receive(on c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, _ in
            if let data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Task { @MainActor in
                    guard let self else { return }
                    self.note         = j["note"] as? String ?? "—"
                    self.frames       = j["frames"] as? Int ?? 0
                    self.audioBuffers = j["audioBuffers"] as? Int ?? 0
                    self.audioPeak    = j["audioPeak"] as? Float ?? 0
                    self.audioPeakMax = j["audioPeakMax"] as? Float ?? 0
                    self.band         = j["band"] as? [Int] ?? []
                    self.rowProfile   = j["rowProfile"] as? [Int] ?? []
                    if let spec = j["spec"] as? String, !spec.isEmpty,
                       let raw = Data(base64Encoded: spec) {
                        let lev = (j["lev"] as? String).flatMap { Data(base64Encoded: $0) }
                        SoundAnalyzer.shared.ingest([UInt8](raw),
                                                    levels: [UInt8](lev ?? Data()),
                                                    bands: j["bands"] as? Int ?? 16,
                                                    myElixir: self.myElixir)
                    }
                    if let b64 = j["digit"] as? String, !b64.isEmpty,
                       let raw = Data(base64Encoded: b64), raw.count == 640 {
                        self.digitImage = CaptureBridge.grayImage(raw, w: 32, h: 20)
                    }
                    // Un segment est considéré rempli si sa couleur est vive
                    let filled = (j["band"] as? [Int] ?? []).filter { $0 > 18 }.count
                    self.myElixir = (j["band"] as? [Int] ?? []).isEmpty ? -1 : filled
                    self.bestRowFrac  = j["bestRowFrac"] as? Double ?? 0
                    self.pixelFormat  = j["pixelFormat"] as? String ?? "?"
                    self.audioFormat  = j["audioFormat"] as? String ?? "?"
                    self.memoryMB     = j["memoryMB"] as? Double ?? 0
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

extension CaptureBridge {
    /// Reconstruit une image à partir de pixels en niveaux de gris.
    static func grayImage(_ data: Data, w: Int, h: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: w, height: h,
                               bitsPerComponent: 8, bitsPerPixel: 8,
                               bytesPerRow: w,
                               space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: 0),
                               provider: provider, decode: nil,
                               shouldInterpolate: false,
                               intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg)
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
