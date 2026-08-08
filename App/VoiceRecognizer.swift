import Foundation
import Speech
import AVFoundation

@MainActor
final class VoiceRecognizer: ObservableObject {

    @Published var listening = false
    @Published var transcript = ""
    @Published var status = "Micro inactif"
    @Published var lastCard: Card?
    @Published var lastScore: Double = 0
    @Published var history: [String] = []

    /// Appelé à chaque carte reconnue avec un score suffisant.
    var onCard: ((Card) -> Void)?

    /// Seuil d'acceptation. Plus bas = plus permissif, plus d'erreurs.
    var threshold: Double = 0.74

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?

    private var processedSegments = 0
    private var pending: [String] = []
    private var lastEmit: (String, Date) = ("", .distantPast)

    // MARK: - Autorisations

    func requestPermissions(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { auth in
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                Task { @MainActor in
                    let ok = (auth == .authorized) && mic
                    self.status = ok ? "Autorisations OK" : "Autorisations refusées"
                    done(ok)
                }
            }
        }
    }

    // MARK: - Marche / arrêt

    func toggle() { listening ? stop() : start() }

    func start() {
        requestPermissions { [weak self] ok in
            guard ok else { return }
            self?.beginSession()
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            status = "Reconnaissance indisponible (français installé ?)"
            return
        }

        do {
            let s = AVAudioSession.sharedInstance()
            // playAndRecord : le micro écoute SANS couper le son du jeu ni le PiP
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try s.setActive(true)
        } catch {
            status = "Session audio: \(error.localizedDescription)"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true   // aucun envoi réseau
        }
        request = req
        processedSegments = 0
        pending = []

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        engine.prepare()
        do { try engine.start() } catch {
            status = "Micro: \(error.localizedDescription)"
            return
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.handle(result.bestTranscription.segments)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.restartSession()
                }
            }
        }

        listening = true
        status = "À l'écoute"

        // Redémarrage périodique : évite l'essoufflement des sessions longues
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.restartSession() }
        }
    }

    private func restartSession() {
        guard listening else { return }
        teardown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.listening else { return }
            self.beginSession()
        }
    }

    func stop() {
        listening = false
        restartTimer?.invalidate()
        restartTimer = nil
        teardown()
        status = "Micro inactif"
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    // MARK: - Analyse

    private func handle(_ segments: [SFTranscriptionSegment]) {
        guard segments.count > processedSegments else { return }
        for i in processedSegments..<segments.count {
            pending.append(segments[i].substring)
        }
        processedSegments = segments.count
        matchPending()
    }

    private func matchPending() {
        while !pending.isEmpty {
            var matched = false
            let maxLen = min(3, pending.count)
            var len = maxLen
            while len >= 1 {
                let phrase = pending.prefix(len).joined(separator: " ")
                if let (card, score) = CardCatalog.match(phrase), score >= threshold {
                    emit(card, score, heard: phrase)
                    pending.removeFirst(len)
                    matched = true
                    break
                }
                len -= 1
            }
            if !matched {
                if pending.count > 3 { pending.removeFirst() } else { break }
            }
        }
    }

    private func emit(_ card: Card, _ score: Double, heard: String) {
        // Anti-doublon : même carte deux fois en moins de 1,2 s
        let now = Date()
        if lastEmit.0 == card.id, now.timeIntervalSince(lastEmit.1) < 1.2 { return }
        lastEmit = (card.id, now)

        lastCard = card
        lastScore = score
        history.insert("\(card.name) (\(card.cost)) ← « \(heard) »", at: 0)
        if history.count > 12 { history.removeLast() }
        onCard?(card)
    }
}
