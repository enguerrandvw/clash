import ReplayKit
import CoreImage
import AVFoundation

// Extension de capture. Contrainte iOS : 50 Mo de RAM maximum.
// Elle ne fait donc AUCUNE analyse : elle mesure, réduit, et transmet.
class SampleHandler: RPBroadcastSampleHandler {

    private let group = "group.com.monprojet.clashelixir"
    private lazy var shared: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: group)

    // Un seul contexte réutilisé : en créer un par image ferait exploser la mémoire
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    private var frameCount = 0
    private var audioCount = 0
    private var audioPeak: Float = 0
    private var lastWrite = Date.distantPast
    private var startedAt = Date()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        startedAt = Date()
        writeState(note: "démarré")
    }

    override func broadcastFinished() {
        writeState(note: "terminé")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {

        case .video:
            frameCount += 1
            // 1 image sur 6 environ : suffisant pour le diagnostic, léger en mémoire
            if frameCount % 6 == 0 { handleVideo(sampleBuffer) }

        case .audioApp:
            audioCount += 1
            audioPeak = max(audioPeak, peakLevel(sampleBuffer))

        case .audioMic:
            break   // on ignore le micro ici

        @unknown default:
            break
        }

        // Écriture de l'état 4 fois par seconde
        if Date().timeIntervalSince(lastWrite) > 0.25 {
            lastWrite = Date()
            writeState(note: "en cours")
        }
    }

    // MARK: - Vidéo

    private func handleVideo(_ sb: CMSampleBuffer) {
        guard let shared,
              let pb = CMSampleBufferGetImageBuffer(sb) else { return }

        autoreleasepool {
            let ci = CIImage(cvPixelBuffer: pb)
            let w = ci.extent.width, h = ci.extent.height

            // Vignette de l'écran entier, largeur 200 px
            let scale = 200.0 / w
            let small = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            // Bande du bas en pleine largeur : c'est là que se trouve ta barre d'élixir
            let bandH = h * 0.16
            let band = ci.cropped(to: CGRect(x: 0, y: 0, width: w, height: bandH))
                         .transformed(by: CGAffineTransform(scaleX: 320/w, y: 320/w))

            write(image: small, to: shared.appendingPathComponent("frame.jpg"))
            write(image: band,  to: shared.appendingPathComponent("band.jpg"))
        }
    }

    private func write(image: CIImage, to url: URL) {
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return }
        let ui = UIImage(cgImage: cg)
        guard let data = ui.jpegData(compressionQuality: 0.5) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Audio

    /// Niveau crête du tampon audio, entre 0 et 1.
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
            for i in 0..<count { peak = max(peak, abs(p[i])) }
        }
        return Float(peak) / Float(Int16.max)
    }

    // MARK: - Transmission

    private func writeState(note: String) {
        guard let shared else { return }
        let state: [String: Any] = [
            "note": note,
            "elapsed": Date().timeIntervalSince(startedAt),
            "frames": frameCount,
            "audioBuffers": audioCount,
            "audioPeak": audioPeak,
            "at": Date().timeIntervalSince1970
        ]
        audioPeak = 0     // remis à zéro à chaque écriture
        if let d = try? JSONSerialization.data(withJSONObject: state) {
            try? d.write(to: shared.appendingPathComponent("state.json"), options: .atomic)
        }
    }
}
