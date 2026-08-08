import UIKit
import AVKit
import AVFoundation
import Combine

// Génère un flux vidéo image par image et l'affiche dans la fenêtre
// flottante du système, qui reste visible au-dessus des autres apps.
@MainActor
final class PiPOverlay: NSObject, ObservableObject {

    @Published var isActive = false
    @Published var isPossible = false
    @Published var lastError: String?

    // Valeurs affichées, mises à jour librement par le moteur
    var elixir: Double = 5
    var rate: Int = 1
    var hand: [String] = []

    let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var pool: CVPixelBufferPool?
    private var timer: Timer?
    private var frameIndex: Int64 = 0

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        makePool()
    }

    // MARK: - Cycle de vie

    func prepare() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            lastError = "Audio: \(error.localizedDescription)"
        }

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            lastError = "PiP non supporté sur cet appareil"
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
        isPossible = c.isPictureInPicturePossible

        startRendering()
    }

    func start() {
        startRendering()
        guard let c = controller else { return }
        if !c.isPictureInPictureActive {
            c.startPictureInPicture()
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Rendu

    private func startRendering() {
        guard timer == nil else { return }
        // 12 images par seconde : largement suffisant, très peu coûteux
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
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &p)
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

            // CoreGraphics a l'origine en bas : on retourne pour dessiner normalement
            ctx.translateBy(x: 0, y: CGFloat(OverlayRenderer.height))
            ctx.scaleBy(x: 1, y: -1)
            OverlayRenderer.draw(into: ctx, elixir: elixir, rate: rate, hand: hand)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        guard let sample = makeSampleBuffer(from: buffer) else { return }
        displayLayer.enqueue(sample)
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
            sampleBufferOut: &sample) == noErr else { return nil }

        return sample
    }
}

// MARK: - Délégués

extension PiPOverlay: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = false }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.lastError = error.localizedDescription }
    }
}

extension PiPOverlay: AVPictureInPictureSampleBufferPlaybackDelegate {

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController, setPlaying playing: Bool) {}

    // Flux continu sans fin : pas de barre de lecture
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController) -> Bool { false }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion: @escaping () -> Void) { completion() }
}
