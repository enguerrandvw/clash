import UIKit
import AVKit
import AVFoundation

@MainActor
final class PiPOverlay: NSObject, ObservableObject {

    @Published var isActive = false
    @Published var isPossible = false
    @Published var lastError: String?
    @Published var framesSent = 0

    var elixir: Double = 5
    var rate: Int = 1
    var hand: [String] = []
    var myElixir: Int = -1      // ton élixir, mesuré à l'écran

    let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var possibleObs: NSKeyValueObservation?
    private var pool: CVPixelBufferPool?
    private var timer: Timer?
    private var frameIndex: Int64 = 0

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        makePool()
        configureAudio()
        startRendering()
    }

    private func configureAudio() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try s.setActive(true)
        } catch {
            lastError = "Audio: \(error.localizedDescription)"
        }
    }

    // Appelé UNE FOIS la couche insérée dans la hiérarchie de vues.
    func attachController() {
        guard controller == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            lastError = "PiP non supporté"
            return
        }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        c.canStartPictureInPictureAutomaticallyFromInline = true
        controller = c

        possibleObs = c.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
            [weak self] ctrl, _ in
            Task { @MainActor in self?.isPossible = ctrl.isPictureInPicturePossible }
        }
    }

    func start() {
        attachController()
        startRendering()
        guard let c = controller else { lastError = "Contrôleur absent"; return }
        guard c.isPictureInPicturePossible else {
            lastError = "PiP pas encore prêt, réessaie dans 1 s"
            return
        }
        if !c.isPictureInPictureActive { c.startPictureInPicture() }
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    // MARK: - Rendu

    private func startRendering() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderFrame() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func makePool() {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: OverlayRenderer.width,
            kCVPixelBufferHeightKey as String: OverlayRenderer.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
        ]
        var p: CVPixelBufferPool?
        let st = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &p)
        if st != kCVReturnSuccess { lastError = "Pool image: \(st)" }
        pool = p
    }

    private func renderFrame() {
        guard let pool else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        guard displayLayer.isReadyForMoreMediaData else { return }

        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess,
              let buffer = pb else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer),
           let ctx = CGContext(
               data: base,
               width: OverlayRenderer.width,
               height: OverlayRenderer.height,
               bitsPerComponent: 8,
               bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
               space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                   | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.translateBy(x: 0, y: CGFloat(OverlayRenderer.height))
            ctx.scaleBy(x: 1, y: -1)
            OverlayRenderer.draw(into: ctx, elixir: elixir, rate: rate,
                                 hand: hand, myElixir: myElixir)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        guard let sample = makeSampleBuffer(from: buffer) else { return }
        displayLayer.enqueue(sample)
        framesSent += 1
    }

    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &format) == noErr, let format else { return nil }

        frameIndex += 1
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 12),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: 12),
            decodeTimeStamp: .invalid
        )

        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sample) == noErr, let sample else { return nil }

        // SANS CECI, RIEN NE S'AFFICHE : on force l'affichage immédiat
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0),
                                     to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sample
    }
}

extension PiPOverlay: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ c: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = true; self.lastError = nil }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ c: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = false }
    }

    nonisolated func pictureInPictureController(
        _ c: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.lastError = error.localizedDescription }
    }
}

extension PiPOverlay: AVPictureInPictureSampleBufferPlaybackDelegate {

    nonisolated func pictureInPictureController(
        _ c: AVPictureInPictureController, setPlaying playing: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ c: AVPictureInPictureController) -> Bool { false }

    nonisolated func pictureInPictureController(
        _ c: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(
        _ c: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion: @escaping () -> Void) { completion() }
}
