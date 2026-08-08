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
    @Published var sessions = 0          // diagnostic : nombre de sessions ouvertes

    /// Appelé à chaque carte reconnue avec un score suffisant.
    var onCard: ((Card) -> Void)?

    /// Seuil d'acceptation. Plus bas = plus permissif, plus d'erreurs.
    var threshold: Double = 0.72

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?

    // Chaque session porte un numéro : les réponses des sessions périmées sont ignorées.
    private var generation = 0
    private var restarting = false

    private var processedSegments = 0
    private var pending: [String] = []
    private var lastEmit: (String, Date) = ("", .distantPast)

    // MARK: - Autorisations

    func requestPermissions(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { st in
            guard st == .authorized else {
                Task { @MainActor in self.status = "Reconnaissance vocale refusée" }
                done(false); return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    if !granted { self.status = "Micro refusé" }
                    done(granted)
                }
            }
        }
    }

    // MARK: - Contrôle

    func toggle() { listening ? stop() : start() }

    func start() {
        guard !listening else { return }
        requestPermissions { ok in
            guard ok else { return }
            Task { @MainActor in
                self.listening = true
                self.beginSession()
            }
        }
    }

    func stop() {
        listening = false
        restartTimer?.invalidate()
        restartTimer = nil
        generation += 1          // invalide toutes les réponses en vol
        teardown()
        status = "Micro inactif"
    }

    // MARK: - Session

    private func beginSession() {
        guard listening else { return }
        guard let recognizer, recognizer.isAvailable else {
            status = "Reconnaissance indisponible (français installé ?)"
            listening = false
            return
        }

        generation += 1
        let gen = generation
        restarting = false

        do {
            let s = AVAudioSession.sharedInstance()
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
            req.requiresOnDeviceRecognition = true
        }
        request = req

        processedSegments = 0
        pending = []

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch {
                status = "Micro: \(error.localizedDescription)"
                return
            }
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }   // session périmée
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.handle(result.bestTranscription.segments)
                    if result.isFinal {
                        self.flushPending()
                        self.scheduleRestart()
                    }
                } else if error != nil {
                    self.scheduleRestart()
                }
            }
        }

        sessions += 1
        status = "À l'écoute"
    }

    /// Un seul redémarrage à la fois, jamais réentrant.
    private func scheduleRestart() {
        guard listening, !restarting else { return }
        restarting = true
        generation += 1                  // les réponses de l'ancienne tâche seront ignorées
        teardown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.listening else { return }
            self.beginSession()
        }
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
        // Nouvelle session ou transcription révisée à la baisse : on repart de zéro
        if segments.count < processedSegments {
            processedSegments = 0
            pending = []
        }
        guard segments.count > processedSegments else { return }

        for i in processedSegments..<segments.count {
            pending.append(segments[i].substring)
        }
        processedSegments = segments.count
        matchPending(keepTail: true)
    }

    /// Vide la file en fin de session, sans garder de mots en attente.
    private func flushPending() {
        matchPending(keepTail: false)
        pending = []
        processedSegments = 0
    }

    /// Teste des fenêtres de 3, 2 puis 1 mot depuis le début de la file.
    /// `keepTail` garde les derniers mots au cas où la phrase serait incomplète.
    private func matchPending(keepTail: Bool) {
        while !pending.isEmpty {
            var matched = false
            var len = min(3, pending.count)
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
                // Mot inutile : on l'abandonne, sauf s'il peut compléter une phrase
                if keepTail && pending.count <= 2 { break }
                pending.removeFirst()
            }
        }
    }

    private func emit(_ card: Card, _ score: Double, heard: String) {
        // Anti-doublon : la même carte deux fois en moins de 1,2 s
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
