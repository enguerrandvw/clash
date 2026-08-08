import Foundation
import AVFoundation

// Joue un son quasi inaudible en boucle pour qu'iOS laisse l'app
// tourner en arrière-plan pendant que tu joues à Clash Royale.
final class KeepAlive {

    static let shared = KeepAlive()
    private var player: AVAudioPlayer?

    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .mixWithOthers : le son de Clash Royale continue normalement
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            player = try AVAudioPlayer(data: KeepAlive.silentWAV(seconds: 1))
            player?.numberOfLoops = -1
            player?.volume = 0.01
            player?.play()
        } catch {
            print("KeepAlive erreur: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Génère un fichier WAV quasi silencieux en mémoire (pas de fichier à ajouter au projet)
    private static func silentWAV(seconds: Int) -> Data {
        let sampleRate = 44100
        let channels = 1
        let bits = 16
        let frames = sampleRate * seconds
        let dataSize = frames * channels * bits / 8

        var d = Data()
        func ascii(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }

        ascii("RIFF"); u32(UInt32(36 + dataSize)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * channels * bits / 8))
        u16(UInt16(channels * bits / 8)); u16(UInt16(bits))
        ascii("data"); u32(UInt32(dataSize))

        for i in 0..<frames {
            let v: Int16 = (i % 2 == 0) ? 1 : -1   // amplitude minimale, inaudible
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        return d
    }
}
