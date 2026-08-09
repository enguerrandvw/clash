import ReplayKit
import CoreImage
import AVFoundation
import Network

// Extension de capture. Limite iOS : 50 Mo de RAM.
// Communication avec l'app par socket locale (127.0.0.1) : aucune autorisation
// Apple requise, contrairement aux App Groups.
class SampleHandler: RPBroadcastSampleHandler {

    private var conn: NWConnection?
    private let port: NWEndpoint.Port = 45678

    private var frameCount = 0
    private var audioCount = 0
    private var audioPeak: Float = 0
    private var lastSend = Date.distantPast
    private var startedAt = Date()

    // Échantillons de la bande basse : serviront à lire ta barre d'élixir
    private var bandSamples: [Int] = []

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        startedAt = Date()
        openSocket()
        send(note: "démarré")
    }

    override func broadcastFinished() {
        send(note: "terminé")
        conn?.cancel()
        conn = nil
    }

    private func openSocket() {
        let c = NWConnection(host: "127.0.0.1", port: port, using: .udp)
        c.start(queue: .global(qos: .userInitiated))
        conn = c
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            frameCount += 1
            if frameCount % 6 == 0 { sampleBand(sampleBuffer) }
        case .audioApp:
            audioCount += 1
            audioPeak = max(audioPeak, peakLevel(sampleBuffer))
        case .audioMic:
            break
        @unknown default:
            break
        }

        if Date().timeIntervalSince(lastSend) > 0.25 {
            lastSend = Date()
            send(note: "en cours")
        }
    }

    // MARK: - Lecture de la bande basse

    /// Échantillonne 10 points sur la largeur, dans la zone de ta barre d'élixir.
    /// On n'envoie que 10 nombres : rien à voir avec le transfert d'une image.
    private func sampleBand(_ sb: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        autoreleasepool {
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

            let w = CVPixelBufferGetWidth(pb)
            let h = CVPixelBufferGetHeight(pb)
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
            let buf = base.assumingMemoryBound(to: UInt8.self)

            // Ligne à 88 % de la hauteur : approximation de la barre d'élixir.
            // On ajustera la valeur exacte une fois qu'on verra les mesures.
            let y = Int(Double(h) * 0.88)
            var out: [Int] = []
            for i in 0..<10 {
                let x = Int(Double(w) * (0.10 + 0.08 * Double(i)))
                guard x < w, y < h else { continue }
                let off = y * bpr + x * 4
                let b = Int(buf[off]), g = Int(buf[off+1]), r = Int(buf[off+2])
                // Indice de « violet » : rouge et bleu forts, vert faible
                out.append(max(0, (r + b) / 2 - g))
            }
            bandSamples = out
        }
    }

    // MARK: - Audio

    private func peakLevel(_ sb: CMSampleBuffer) -> Float {
        guard let bb = CMSampleBufferGetDataBuffer(sb) else { return 0 }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length,
                                          dataPointerOut: &ptr) == noErr,
              let ptr else { return 0 }
        let count = length / MemoryLayout<Int16>.size
        guard count > 0 else { return 0 }
        var peak: Int16 = 0
        ptr.withMemoryRebound(to: Int16.self, capacity: count) { p in
            for i in stride(from: 0, to: count, by: 2) { peak = max(peak, abs(p[i])) }
        }
        return Float(peak) / Float(Int16.max)
    }

    // MARK: - Envoi

    private func send(note: String) {
        let state: [String: Any] = [
            "note": note,
            "elapsed": Date().timeIntervalSince(startedAt),
            "frames": frameCount,
            "audioBuffers": audioCount,
            "audioPeak": audioPeak,
            "band": bandSamples,
            "at": Date().timeIntervalSince1970
        ]
        audioPeak = 0
        guard let d = try? JSONSerialization.data(withJSONObject: state) else { return }
        conn?.send(content: d, completion: .idempotent)
    }
}
