import ReplayKit
import AVFoundation
import Network
import Accelerate

// Extension de capture. Limite iOS : 50 Mo de RAM.
// Cette version ne suppose RIEN sur le format des tampons : elle le détecte,
// s'y adapte, et le rapporte pour diagnostic.
class SampleHandler: RPBroadcastSampleHandler {

    private var conn: NWConnection?

    private var frameCount = 0
    private var audioCount = 0
    private var audioPeak: Float = 0
    private var audioPeakMax: Float = 0
    private var lastSend = Date.distantPast
    private var startedAt = Date()

    private var bandSamples: [Int] = []
    private var rowProfile: [Int] = []
    private var digitB64 = ""          // imagette du chiffre d'élixir

    // Audio brut décimé à 11025 Hz sur 8 bits : assez pour reconnaître
    // un son à l'oreille, assez léger pour tenir dans un datagramme.
    private var pcm: [UInt8] = []
    private var pcmPhase = 0
    private var pcmAcc: Float = 0

    // --- Analyse spectrale ---
    private let fftSize = 1024
    private let bandCount = 32
    private var fftSetup: FFTSetup?
    private var window = [Float]()
    private var pending = [Float]()      // échantillons en attente
    private var frames: [UInt8] = []     // formes spectrales normalisées
    private var levels: [UInt8] = []     // niveau absolu de chaque trame
    private var channels = 1
    private var bestRowFrac: Double = 0
    private var pixelFormat = ""
    private var audioFormat = ""

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        startedAt = Date()
        fftSetup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        let c = NWConnection(host: "127.0.0.1", port: 45678, using: .udp)
        c.start(queue: .global(qos: .utility))
        conn = c
        send(note: "démarré")
    }

    override func broadcastFinished() {
        send(note: "terminé")
        conn?.cancel()
        conn = nil
    }

    override func processSampleBuffer(_ sb: CMSampleBuffer,
                                      with type: RPSampleBufferType) {
        autoreleasepool {
            switch type {
            case .video:
                frameCount += 1
                // 1 image sur 15 : suffisant, et deux fois moins de travail
                if frameCount % 5 == 0 { readBand(sb) }
            case .audioApp:
                audioCount += 1
                let p = readPeak(sb)
                audioPeak = max(audioPeak, p)
                audioPeakMax = max(audioPeakMax, p)
            default:
                break
            }

            if Date().timeIntervalSince(lastSend) > 0.1 {
                lastSend = Date()
                send(note: "en cours")
            }
        }
    }

    // MARK: - Vidéo, sans hypothèse sur le format

    private func readBand(_ sb: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }

        let fmt = CVPixelBufferGetPixelFormatType(pb)
        pixelFormat = fourCC(fmt)

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 0, h > 0 else { return }

        var out: [Int] = []

        if fmt == kCVPixelFormatType_32BGRA {
            // BGRA : on peut mesurer la teinte violette
            guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            let total = bpr * h
            let y = min(h - 1, Int(Double(h) * 0.88))
            let buf = base.assumingMemoryBound(to: UInt8.self)
            for i in 0..<10 {
                let x = Int(Double(w) * (0.10 + 0.08 * Double(i)))
                let off = y * bpr + x * 4
                guard x < w, off >= 0, off + 2 < total else { continue }
                let b = Int(buf[off]), g = Int(buf[off + 1]), r = Int(buf[off + 2])
                out.append(max(0, (r + b) / 2 - g))
            }
        } else if CVPixelBufferIsPlanar(pb) {
            // Plan 1 : chroma Cb/Cr entrelacée, demi-résolution.
            // L'écart à 128 mesure la saturation : élevé pour le violet,
            // proche de zéro pour le blanc, le gris et le noir.
            if CVPixelBufferGetPlaneCount(pb) > 1,
               let cbase = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
                let cbpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
                let cw = CVPixelBufferGetWidthOfPlane(pb, 1)
                let ch = CVPixelBufferGetHeightOfPlane(pb, 1)
                let ctotal = cbpr * ch
                let cbuf = cbase.assumingMemoryBound(to: UInt8.self)

                // --- Calibrage : on balaie le tiers inférieur de l'écran ---
                // Pour chaque ligne, on mesure la saturation moyenne.
                // La barre d'élixir, très violette, ressortira nettement.
                var profile: [Int] = []
                var bestRow = 0
                var bestScore = -1
                for k in 0..<24 {
                    // Zone réelle de la barre : entre 92 % et 99 % de la hauteur
                    let frac = 0.92 + 0.07 * Double(k) / 23.0
                    let row = min(ch - 1, Int(Double(ch) * frac))
                    var sum = 0, n = 0
                    for i in 0..<20 {
                        // La barre s'étend de 32 % à 96 % de la largeur
                        let x = Int(Double(cw) * (0.29 + 0.67 * Double(i) / 19.0))
                        let off = row * cbpr + x * 2
                        guard x < cw, off >= 0, off + 1 < ctotal else { continue }
                        // Indice ROSE : les deux chromas doivent dépasser le neutre.
                        // Le bleu du bandeau a Cr en dessous, il est donc exclu.
                        let cb = Int(cbuf[off]) - 128
                        let cr = Int(cbuf[off + 1]) - 128
                        sum += max(0, min(cb, cr))
                        n += 1
                    }
                    let avg = n > 0 ? sum / n : 0
                    profile.append(avg)
                    if avg > bestScore { bestScore = avg; bestRow = row }
                }
                rowProfile = profile
                bestRowFrac = ch > 0 ? Double(bestRow) / Double(ch) : 0

                // --- Lecture des 10 segments sur la ligne la plus saturée ---
                for i in 0..<10 {
                    // Centre de chacun des 10 segments d'élixir
                    // On resserre : 0.30 à 0.945, et on vise légèrement
                    // vers l'intérieur pour ne pas déborder du dernier segment.
                    let t = (Double(i) + 0.5) / 10.0
                    let x = Int(Double(cw) * (0.30 + 0.645 * t))
                    // On échantillonne 3 lignes autour de la meilleure et on
                    // garde la plus rose : robuste à un léger décalage vertical.
                    var best = 0
                    for dy in [-2, 0, 2] {
                        let row = max(0, min(ch - 1, bestRow + dy))
                        let off = row * cbpr + x * 2
                        guard x < cw, off >= 0, off + 1 < ctotal else { continue }
                        let cb = Int(cbuf[off]) - 128
                        let cr = Int(cbuf[off + 1]) - 128
                        best = max(best, max(0, min(cb, cr)))
                    }
                    out.append(best)
                }
            }
        }

        if !out.isEmpty { bandSamples = out }

        readDigit(pb)
    }

    // Découpe la zone du chiffre d'élixir et la réduit à 32x20 en niveaux de gris.
    // 640 octets seulement : ça tient largement dans un datagramme.
    private func readDigit(_ pb: CVPixelBuffer) {
        guard CVPixelBufferIsPlanar(pb),
              let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return }

        let bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let pw  = CVPixelBufferGetWidthOfPlane(pb, 0)
        let ph  = CVPixelBufferGetHeightOfPlane(pb, 0)
        guard pw > 0, ph > 0, bpr > 0 else { return }
        let buf = base.assumingMemoryBound(to: UInt8.self)
        let total = bpr * ph

        // Zone du chiffre, mesurée sur capture réelle
        let x0 = Int(Double(pw) * 0.23), x1 = Int(Double(pw) * 0.36)
        let y0 = Int(Double(ph) * 0.935), y1 = Int(Double(ph) * 0.973)
        let rw = max(1, x1 - x0), rh = max(1, y1 - y0)

        let ow = 32, oh = 20
        var px = [UInt8](repeating: 0, count: ow * oh)
        for j in 0..<oh {
            let sy = y0 + j * rh / oh
            for i in 0..<ow {
                let sx = x0 + i * rw / ow
                let off = sy * bpr + sx
                guard sx >= 0, sx < pw, sy >= 0, sy < ph, off < total else { continue }
                px[j * ow + i] = buf[off]
            }
        }
        digitB64 = Data(px).base64EncodedString()
    }

    // MARK: - Audio, sans hypothèse sur le format

    private func readPeak(_ sb: CMSampleBuffer) -> Float {
        guard let fd = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee
        else { return 0 }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        // Canaux séparés ou entrelacés : ça change complètement la façon
        // de parcourir les échantillons.
        let nonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        audioFormat = (isFloat ? "float" : "int") + "\(asbd.mBitsPerChannel)"
            + " \(Int(asbd.mSampleRate))Hz "
            + "\(asbd.mChannelsPerFrame)ch "
            + (nonInterleaved ? "séparés" : "entrelacés")

        var block: CMBlockBuffer?
        var abl = AudioBufferList()
        let st = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb,
            bufferListSizeNeededOut: nil,
            bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &block)
        guard st == noErr, let data = abl.mBuffers.mData else { return 0 }

        channels = max(1, Int(asbd.mChannelsPerFrame))
        let bytes = Int(abl.mBuffers.mDataByteSize)
        var peak: Float = 0

        if isFloat && asbd.mBitsPerChannel == 32 {
            let n = bytes / 4
            guard n > 0 else { return 0 }
            let p = data.assumingMemoryBound(to: Float.self)
            for i in stride(from: 0, to: n, by: 4) { peak = max(peak, abs(p[i])) }
        } else if asbd.mBitsPerChannel == 16 {
            let n = bytes / 2
            guard n > 0 else { return 0 }
            let p = data.assumingMemoryBound(to: Int16.self)
            var m: Int32 = 0
            for i in stride(from: 0, to: n, by: 2) { m = max(m, abs(Int32(p[i]))) }
            peak = Float(m) / Float(Int16.max)

            // On empile les échantillons pour l'analyse spectrale.
            // En canaux SÉPARÉS, ce tampon ne contient déjà qu'un seul canal :
            // il ne faut surtout pas sauter d'échantillons, sinon la fréquence
            // d'échantillonnage est divisée par deux et tout le spectre se décale.
            let step = nonInterleaved ? 1 : channels
            var i = 0
            while i < n {
                let v = Float(p[i]) / 32768.0
                pending.append(v)

                // 44100 → 11025 Hz, en moyennant quatre échantillons pour
                // éviter que les aigus se replient dans les graves.
                pcmAcc += v
                pcmPhase += 1
                if pcmPhase >= 4 {
                    let c = max(-1, min(1, pcmAcc / 4))
                    // Encodage μ-law : 8 bits logarithmiques valent environ
                    // 14 bits linéaires. Indispensable ici, car un son de jeu
                    // n'occupe qu'une fraction de l'échelle et serait noyé
                    // sous le bruit de quantification en 8 bits linéaires.
                    pcm.append(Self.muLawEncode(Int16(c * 32767)))
                    pcmPhase = 0
                    pcmAcc = 0
                }
                i += step
            }
            if pcm.count > 11025 * 3 { pcm.removeFirst(pcm.count - 11025 * 3) }
            analysePending()
        }
        return min(1, peak)
    }

    /// Encodage μ-law standard (G.711).
    static func muLawEncode(_ sample: Int16) -> UInt8 {
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

    // MARK: - Spectre

    /// Découpe les échantillons en trames de 1024 (~23 ms) et calcule
    /// l'énergie dans 16 bandes réparties logarithmiquement.
    private func analysePending() {
        guard let setup = fftSetup else { return }
        let half = fftSize / 2

        while pending.count >= fftSize {
            var chunk = Array(pending.prefix(fftSize))
            // Avance de 512 seulement : les trames se chevauchent de moitié,
            // exactement comme dans le calcul des empreintes de référence.
            pending.removeFirst(fftSize / 2)

            vDSP_vmul(chunk, 1, window, 1, &chunk, 1, vDSP_Length(fftSize))

            var real = [Float](repeating: 0, count: half)
            var imag = [Float](repeating: 0, count: half)
            var mags = [Float](repeating: 0, count: half)

            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    chunk.withUnsafeBufferPointer { cp in
                        cp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, 10, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
                }
            }

            // 16 bandes logarithmiques entre 200 Hz et 11 kHz
            let binHz = 44100.0 / Double(fftSize)
            var dbs = [Float](repeating: -120, count: bandCount)
            for b in 0..<bandCount {
                let f0 = 200.0 * pow(11000.0 / 200.0, Double(b) / Double(bandCount))
                let f1 = 200.0 * pow(11000.0 / 200.0, Double(b + 1) / Double(bandCount))
                let i0 = max(1, Int(f0 / binHz))
                let i1 = min(half - 1, max(i0 + 1, Int(f1 / binHz)))
                var sum: Float = 0
                for i in i0..<i1 { sum += mags[i] }
                let avg = sum / Float(max(1, i1 - i0))
                dbs[b] = 20 * log10(max(avg, 1e-6))
            }

            // Niveau absolu : sert à repérer les impulsions
            let peakDb = dbs.max() ?? -120
            levels.append(UInt8(max(0, min(255, Int((peakDb + 60) / 100 * 255)))))

            // Niveaux ABSOLUS par bande : -80 dB à +20 dB ramenés sur 0-255.
            // Indispensable pour pouvoir soustraire l'ambiance côté app :
            // une normalisation par tranche détruirait l'enveloppe du son.
            for b in 0..<bandCount {
                let v = max(0, min(255, Int((dbs[b] + 80) / 100 * 255)))
                frames.append(UInt8(v))
            }
            // Sécurité : on ne laisse pas la file grossir sans fin
            if frames.count > bandCount * 40 {
                frames.removeFirst(frames.count - bandCount * 40)
                if levels.count > 40 { levels.removeFirst(levels.count - 40) }
            }
        }
        if pending.count > fftSize * 4 { pending.removeFirst(pending.count - fftSize * 2) }
    }

    // MARK: - Outils

    private func fourCC(_ v: OSType) -> String {
        let b = [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255),
                 UInt8((v >> 8) & 255), UInt8(v & 255)]
        let s = String(bytes: b, encoding: .ascii) ?? "?"
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Mémoire utilisée par l'extension, en Mo. Au-delà de 50, iOS la tue.
    private func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    private func send(note: String) {
        let state: [String: Any] = [
            "note": note,
            "elapsed": Date().timeIntervalSince(startedAt),
            "frames": frameCount,
            "audioBuffers": audioCount,
            "audioPeak": audioPeak,
            "audioPeakMax": audioPeakMax,
            "band": bandSamples,
            "rowProfile": rowProfile,
            "digit": digitB64,
            "spec": Data(frames).base64EncodedString(),
            "lev": Data(levels).base64EncodedString(),
            "pcm": Data(pcm).base64EncodedString(),
            "pcmRate": 11025,
            "bands": bandCount,
            "bestRowFrac": bestRowFrac,
            "pixelFormat": pixelFormat,
            "audioFormat": audioFormat,
            "memoryMB": memoryMB(),
            "at": Date().timeIntervalSince1970
        ]
        audioPeak = 0
        frames.removeAll(keepingCapacity: true)
        levels.removeAll(keepingCapacity: true)
        pcm.removeAll(keepingCapacity: true)
        guard let d = try? JSONSerialization.data(withJSONObject: state) else { return }
        conn?.send(content: d, completion: .idempotent)
    }
}
