import ReplayKit
import AVFoundation
import Network

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
    private var bestRowFrac: Double = 0
    private var pixelFormat = ""
    private var audioFormat = ""

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        startedAt = Date()
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
                if frameCount % 15 == 0 { readBand(sb) }
            case .audioApp:
                audioCount += 1
                let p = readPeak(sb)
                audioPeak = max(audioPeak, p)
                audioPeakMax = max(audioPeakMax, p)
            default:
                break
            }

            if Date().timeIntervalSince(lastSend) > 0.25 {
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
                    let frac = 0.66 + 0.34 * Double(k) / 23.0
                    let row = min(ch - 1, Int(Double(ch) * frac))
                    var sum = 0, n = 0
                    for i in 0..<20 {
                        let x = Int(Double(cw) * (0.10 + 0.04 * Double(i)))
                        let off = row * cbpr + x * 2
                        guard x < cw, off >= 0, off + 1 < ctotal else { continue }
                        sum += abs(Int(cbuf[off]) - 128) + abs(Int(cbuf[off + 1]) - 128)
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
                    let x = Int(Double(cw) * (0.10 + 0.08 * Double(i)))
                    let off = bestRow * cbpr + x * 2
                    guard x < cw, off >= 0, off + 1 < ctotal else { continue }
                    let cb = Int(cbuf[off]) - 128
                    let cr = Int(cbuf[off + 1]) - 128
                    out.append(abs(cb) + abs(cr))
                }
            }
        }

        if !out.isEmpty { bandSamples = out }
    }

    // MARK: - Audio, sans hypothèse sur le format

    private func readPeak(_ sb: CMSampleBuffer) -> Float {
        guard let fd = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee
        else { return 0 }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        audioFormat = (isFloat ? "float" : "int") + "\(asbd.mBitsPerChannel)"
            + " \(Int(asbd.mSampleRate))Hz"

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
            for i in stride(from: 0, to: n, by: 4) { m = max(m, abs(Int32(p[i]))) }
            peak = Float(m) / Float(Int16.max)
        }
        return min(1, peak)
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
            "bestRowFrac": bestRowFrac,
            "pixelFormat": pixelFormat,
            "audioFormat": audioFormat,
            "memoryMB": memoryMB(),
            "at": Date().timeIntervalSince1970
        ]
        audioPeak = 0
        guard let d = try? JSONSerialization.data(withJSONObject: state) else { return }
        conn?.send(content: d, completion: .idempotent)
    }
}
