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

    // Diagnostics affichés dans le statut
    @Published var sessions = 0        // sessions de reconnaissance ouvertes
    @Published var heardWords = 0      // mots reçus du micro depuis le début
    @Published var lastAttempt = ""    // dernier essai de correspondance, même refusé

    var onCard: ((Card) -> Void)?
    /// Appelé quand l'utilisateur annonce un nombre : « sept » → 7
    var onElixir: ((Int) -> Void)?
    var threshold: Double = 0.72

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))

    // Le moteur audio tourne en continu ; seule la requête change.
    private var currentRequest: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioReady = false

    private var generation = 0
    private var restarting = false

    private var lastWords: [String] = []   // dernière transcription vue, mot à mot
    private var pending: [String] = []
    private var lastEmit: (String, Date) = ("", .distantPast)

    // Nombres reconnus à l'oral pour recaler l'élixir
    private static let numberWords: [String: Int] = [
        "zero": 0, "0": 0, "un": 1, "1": 1, "une": 1,
        "deux": 2, "2": 2, "trois": 3, "3": 3, "quatre": 4, "4": 4,
        "cinq": 5, "5": 5, "six": 6, "6": 6, "sept": 7, "7": 7,
        "huit": 8, "8": 8, "neuf": 9, "9": 9, "dix": 10, "10": 10
    ]
    // « trois » peut commencer « Trois mousquetaires » : on attend la suite
    private static let ambiguousNumbers: Set<String> = ["trois", "3"]

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
                guard self.setupAudioOnce() else { self.listening = false; return }
                self.beginSession()
            }
        }
    }

    func stop() {
        listening = false
        generation += 1
        task?.cancel(); task = nil
        currentRequest?.endAudio(); currentRequest = nil
        stopAudio()
        status = "Micro inactif"
    }

    // MARK: - Audio (démarré une seule fois, jamais interrompu ensuite)

    private func setupAudioOnce() -> Bool {
        guard !audioReady else { return true }

        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try s.setActive(true)
        } catch {
            status = "Session audio: \(error.localizedDescription)"
            return false
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            status = "Format micro invalide"
            return false
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // On alimente la requête courante, quelle qu'elle soit
            self?.currentRequest?.append(buffer)
        }

        engine.prepare()
        do { try engine.start() } catch {
            status = "Micro: \(error.localizedDescription)"
            return false
        }

        audioReady = true
        return true
    }

    private func stopAudio() {
        guard audioReady else { return }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        audioReady = false
    }

    // MARK: - Session de reconnaissance

    private func beginSession() {
        guard listening, audioReady else { return }
        guard let recognizer, recognizer.isAvailable else {
            status = "Reconnaissance indisponible (français installé ?)"
            listening = false
            return
        }

        generation += 1
        let gen = generation
        restarting = false

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        currentRequest = req

        lastWords = []
        pending = []
        transcript = ""

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.handle(result.bestTranscription.segments)
                    if result.isFinal {
                        self.flushPending()
                        self.scheduleRestart(reason: "fin")
                    }
                } else if let error {
                    self.scheduleRestart(reason: "err \((error as NSError).code)")
                }
            }
        }

        sessions += 1
        refreshStatus()
    }

    private func scheduleRestart(reason: String) {
        guard listening, !restarting else { return }
        restarting = true
        generation += 1
        task?.cancel(); task = nil
        currentRequest?.endAudio(); currentRequest = nil
        // Le moteur audio continue de tourner : rien d'autre à démonter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.listening else { return }
            self.beginSession()
        }
    }

    private func refreshStatus() {
        var s = "À l'écoute · S\(sessions) · \(heardWords) mots"
        if !lastAttempt.isEmpty { s += " · \(lastAttempt)" }
        status = s
    }

    // MARK: - Analyse

    private func handle(_ segments: [SFTranscriptionSegment]) {
        let words = segments.map { $0.substring }

        // iOS ne rallonge pas toujours la phrase : après une pause il la REMPLACE.
        // On compare donc mot à mot et on ne traite que ce qui a réellement changé.
        var common = 0
        while common < min(words.count, lastWords.count),
              words[common].caseInsensitiveCompare(lastWords[common]) == .orderedSame {
            common += 1
        }
        let fresh = Array(words[common...])
        lastWords = words

        guard !fresh.isEmpty else { return }
        pending.append(contentsOf: fresh)
        heardWords += fresh.count

        matchPending(keepTail: true)
        refreshStatus()
    }

    private func flushPending() {
        matchPending(keepTail: false)
        pending = []
        lastWords = []
    }

    private func matchPending(keepTail: Bool) {
        while !pending.isEmpty {
            var matched = false
            var len = min(3, pending.count)
            while len >= 1 {
                let phrase = pending.prefix(len).joined(separator: " ")
                if let (card, score) = CardCatalog.match(phrase) {
                    if len == 1 || score >= threshold {
                        lastAttempt = String(format: "%@→%@ %.2f", phrase, card.name, score)
                    }
                    if score >= threshold {
                        emit(card, score, heard: phrase)
                        pending.removeFirst(len)
                        matched = true
                        break
                    }
                }
                len -= 1
            }
            // Aucun nom de carte : le mot est-il un nombre ?
            if !matched, let first = pending.first {
                let w = CardCatalog.normalize(first)
                if let value = Self.numberWords[w] {
                    let risky = Self.ambiguousNumbers.contains(w)
                    // « trois » seul en fin de phrase : on patiente, ce peut être
                    // le début de « trois mousquetaires »
                    if !(risky && keepTail && pending.count == 1) {
                        lastAttempt = "\(first) → élixir \(value)"
                        onElixir?(value)
                        pending.removeFirst()
                        matched = true
                    }
                }
            }

            if !matched {
                if keepTail && pending.count <= 2 { break }
                pending.removeFirst()
            }
        }
    }

    private func emit(_ card: Card, _ score: Double, heard: String) {
        let now = Date()
        if lastEmit.0 == card.id, now.timeIntervalSince(lastEmit.1) < 1.5 { return }
        lastEmit = (card.id, now)

        lastCard = card
        lastScore = score
        history.insert("\(card.name) (\(card.cost)) ← « \(heard) »", at: 0)
        if history.count > 12 { history.removeLast() }
        onCard?(card)
    }
}
