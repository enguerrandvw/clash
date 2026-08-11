import AVFoundation

/// Encodage μ-law, identique à celui de l'extension.
enum SampleMuLaw {
    static func encode(_ sample: Int16) -> UInt8 {
        let bias: Int32 = 132
        let clip: Int32 = 32635
        var v = Int32(sample)
        let sign: Int32 = v < 0 ? 0x80 : 0
        if v < 0 { v = -v }
        if v > clip { v = clip }
        v += bias

        var exponent: Int32 = 7
        var mask: Int32 = 0x4000
        while exponent > 0 && (v & mask) == 0 {
            exponent -= 1
            mask >>= 1
        }
        let mantissa = (v >> (exponent + 3)) & 0x0F
        return UInt8(~(sign | (exponent << 4) | mantissa) & 0xFF)
    }
}

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

        // Décodage μ-law vers 16 bits signés
        var pcm16 = [Int16]()
        pcm16.reserveCapacity(samples.count)
        for b in samples { pcm16.append(Self.muLawDecode(b)) }

        // Remise à niveau : l'audio du jeu est souvent faible, on l'amplifie
        // pour qu'il soit confortable à écouter.
        let peak = pcm16.map { abs(Int($0)) }.max() ?? 0
        if peak > 200 && peak < 20000 {
            let gain = min(8.0, 26000.0 / Double(peak))
            pcm16 = pcm16.map { Int16(max(-32767, min(32767, Double($0) * gain))) }
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

    /// Décodage μ-law standard (G.711).
    static func muLawDecode(_ u: UInt8) -> Int16 {
        let x = Int32(~u & 0xFF)
        let sign = x & 0x80
        let exponent = (x >> 4) & 0x07
        let mantissa = x & 0x0F
        var sample = ((mantissa << 3) + 132) << exponent
        sample -= 132
        return Int16(clamping: sign != 0 ? -sample : sample)
    }

    /// Note pure générée dans l'app : si elle sonne juste, la lecture est
    /// saine et le défaut vient de la capture. Si elle grésille aussi,
    /// c'est la construction du fichier WAV qui est en cause.
    func playTestTone() {
        let rate = 11025
        let n = rate         // une seconde
        var samples = [UInt8]()
        samples.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / Double(rate)
            let v = sin(2 * .pi * 440 * t) * 0.6
            samples.append(SampleMuLaw.encode(Int16(v * 32767)))
        }
        play(samples, rate: rate)
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
