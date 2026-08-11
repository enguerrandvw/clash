import AVFoundation

/// Rejoue l'audio brut capté avec un exemple, pour vérifier à l'oreille
/// que c'est bien le son de la carte et non un tir de tour.
@MainActor
final class AudioPlayback: ObservableObject {

    static let shared = AudioPlayback()
    private var player: AVAudioPlayer?
    @Published var playing = false

    /// `samples` : audio 8 bits non signé, 11025 Hz.
    func play(_ samples: [UInt8], rate: Int = 11025) {
        guard samples.count > 100 else { return }
        stop()

        // Conversion en 16 bits signés, format attendu dans un WAV
        var pcm16 = [Int16]()
        pcm16.reserveCapacity(samples.count)
        for b in samples {
            pcm16.append(Int16((Int(b) - 128) * 256))
        }

        guard let wav = Self.makeWAV(pcm16, rate: rate) else { return }
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: wav)
            player?.volume = 1.0
            player?.play()
            playing = true
            let duration = Double(samples.count) / Double(rate)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000) + 200_000_000)
                self.playing = false
            }
        } catch {
            playing = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playing = false
    }

    /// Construit un fichier WAV mono 16 bits en mémoire.
    private static func makeWAV(_ samples: [Int16], rate: Int) -> Data? {
        var d = Data()
        let dataBytes = samples.count * 2
        let byteRate = rate * 2

        func append32(_ v: Int) {
            var x = UInt32(truncatingIfNeeded: v).littleEndian
            withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }
        func append16(_ v: Int) {
            var x = UInt16(truncatingIfNeeded: v).littleEndian
            withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }

        d.append(contentsOf: Array("RIFF".utf8))
        append32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        append32(16)            // taille du bloc de format
        append16(1)             // PCM non compressé
        append16(1)             // mono
        append32(rate)
        append32(byteRate)
        append16(2)             // octets par échantillon
        append16(16)            // bits par échantillon
        d.append(contentsOf: Array("data".utf8))
        append32(dataBytes)

        for s in samples {
            var x = UInt16(bitPattern: s).littleEndian
            withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }
        return d
    }
}
