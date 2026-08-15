import SwiftUI

// Apprentissage sans manipulation en jeu :
// on déclare son deck une fois, puis l'app apprend toute seule.
struct LearnView: View {
    @ObservedObject private var learned = LearnedSounds.shared
    @ObservedObject private var sound = SoundAnalyzer.shared
    @ObservedObject private var capture = CaptureBridge.shared
    @State private var search = ""
    @State private var editingDeck = false
    @State private var exportURL: URL?
    @State private var testReport: LearnedSounds.TestReport?
    @State private var method: LearnedSounds.Method = .simple
    @State private var expanded: String?
    @State private var showShare = false

    /// Écrit la banque dans un fichier temporaire, prêt à être partagé.
    private func writeExport() -> URL? {
        let text = learned.exportSwift()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BankedSounds.swift")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch { return nil }
    }

    private var results: [Card] {
        let q = CardCatalog.normalize(search)
        guard !q.isEmpty else { return [] }
        return CardCatalog.all.filter {
            CardCatalog.normalize($0.name).contains(q)
                || $0.aliases.contains { CardCatalog.normalize($0).contains(q) }
        }.prefix(12).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                deckSection
                captureSection
                Divider()
                pendingSection
                Divider()
                summarySection
            }
            .padding(.vertical, 16)
        }
        .sheet(isPresented: $showShare) {
            if let u = exportURL { ShareSheet(items: [u]) }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                Text("Apprentissage des sons")
                    .font(.headline)

                VStack(spacing: 2) {
                    Text("Cartes détectées comme jouées par toi : \(sound.myPlays)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(sound.myPlays > 0 ? .green : .orange)
                    Text("dernière : \(sound.lastPlayInfo)")
                        .font(.caption2).foregroundStyle(.secondary)
                    // Le son arrive-t-il seulement jusqu'ici ?
                    Text(capture.audioPeakMax > 0.01
                         ? String(format: "SON REÇU · crête %.2f · max %.2f",
                                  capture.audioPeak, capture.audioPeakMax)
                         : "AUCUN SON REÇU — vérifie les effets sonores du jeu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(capture.audioPeakMax > 0.01 ? .green : .red)

                    Text(capture.rawPeek.isEmpty ? "échantillons bruts : —" : capture.rawPeek)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Text("Motif reconnu : \(sound.lastTemplateHit)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    Text(RefMatcher.isReady
                         ? "\(SoundRefs.all.count) sons de référence · \(RefMatcher.cardByRef.count) reliés à une carte"
                         : "Aucun son de référence chargé")
                        .font(.caption)
                        .foregroundStyle(RefMatcher.isReady ? .green : .orange)
                        .multilineTextAlignment(.center)

                    Text("débit audio : \(sound.pcmRateMeasured) éch/s (attendu 11025)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sound.pcmRateMeasured > 9000 ? .green
                                         : (sound.pcmRateMeasured > 100 ? .orange : .red))

                    Text("tampon \(sound.framesInBuffer) trames · reçues \(sound.totalFrames) au total")
                        .font(.caption2)
                        .foregroundStyle(sound.framesInBuffer > 100 ? .green : .red)

                    Text("étiquetés \(learned.labelled) · en attente \(learned.sentToPending)"
                         + " · sans événement \(sound.rejectedNoEvent)"
                         + " · hors deck \(learned.noCandidate)")
                        .font(.caption2).foregroundStyle(.blue)
                        .multilineTextAlignment(.center)
                }

        }
    }

    @ViewBuilder
    private var deckSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                // --- 1. Ton deck ---
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Ton deck — \(learned.myDeck.count)/8")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(editingDeck ? "Terminé" : "Modifier") {
                            editingDeck.toggle(); search = ""
                        }
                        .font(.footnote)
                    }

                    if learned.myDeck.isEmpty {
                        Text("Déclare tes 8 cartes : l'app saura ensuite deviner "
                             + "seule ce que tu poses, à partir de ton élixir dépensé.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2),
                              spacing: 6) {
                        ForEach(learned.myDeck) { c in
                            HStack {
                                Text(c.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text("\(c.cost)").font(.caption.bold())
                                    .foregroundStyle(.purple)
                                Text("· \(learned.usableCount(for: c.id))/\(learned.count(for: c.id))")
                                    .font(.caption2)
                                    .foregroundStyle(learned.count(for: c.id) >= 3
                                                     ? .green : .orange)
                                if editingDeck {
                                    Button { learned.toggleDeck(c) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if editingDeck {
                        TextField("Chercher une carte à ajouter…", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        ForEach(results) { c in
                            Button {
                                learned.toggleDeck(c); search = ""
                            } label: {
                                HStack {
                                    Text(c.name)
                                    Spacer()
                                    Text("\(c.cost)").foregroundStyle(.purple)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

        }
    }

    @ViewBuilder
    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                // --- Inspection visuelle de la dernière capture ---
                VStack(alignment: .leading, spacing: 5) {
                    Text("Dernière capture — brut")
                        .font(.caption.weight(.medium))
                    SpectroView(frames: sound.lastRaw, height: 90)
                    Text(SpectroStats(sound.lastRaw).summary)
                        .font(.caption2).foregroundStyle(.secondary)

                    Button {
                        AudioPlayback.shared.playTestTone()
                    } label: {
                        Label("Tester le son (note pure)", systemImage: "tuningfork")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 4)

                    Button {
                        AudioPlayback.shared.play(sound.lastAudio)
                    } label: {
                        Label("Écouter la dernière capture",
                              systemImage: "speaker.wave.2.fill")
                            .font(.caption.weight(.medium))
                    }
                    .disabled(sound.lastAudio.count < 100)
                    .padding(.top, 4)

                    Text("Après soustraction et normalisation")
                        .font(.caption.weight(.medium)).padding(.top, 4)
                    SpectroView(frames: sound.lastProcessed, height: 90)
                    Text(SpectroStats(sound.lastProcessed).summary)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "Seuil de détection : %.1f dB",
                                LearnedSounds.jumpThreshold))
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { LearnedSounds.jumpThreshold },
                        set: { LearnedSounds.jumpThreshold = $0 }),
                        in: 0.5...12, step: 0.5)
                }
                .padding(.horizontal, 20)

                Divider()

        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                // --- 2. Sons à étiqueter ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("À étiqueter — \(learned.pending.count)")
                        .font(.subheadline.weight(.semibold))
                    Text("Quand plusieurs cartes de ton deck ont le même coût, "
                         + "l'app ne peut pas trancher seule. Choisis ici, après la partie.")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(learned.pending) { p in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(p.at, style: .time)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text("−\(p.drop) élixir")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.purple)
                                Spacer()
                                Button {
                                    learned.discard(p)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            // Le spectrogramme accompagne l'écoute : deux sons
                            // proches à l'oreille ont souvent une allure
                            // nettement différente à l'image.
                            SpectroView(frames: p.frames, height: 40)

                            Button {
                                AudioPlayback.shared.play(p.audio)
                            } label: {
                                Label("Écouter", systemImage: "play.circle.fill")
                                    .font(.caption)
                            }
                            .disabled(p.audio.count < 100)

                            HStack(spacing: 6) {
                                ForEach(p.candidates) { c in
                                    Button {
                                        learned.label(p, as: c)
                                    } label: {
                                        Text(c.name)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(Color.green.opacity(0.18))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color.gray.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 20)

                Divider()

        }
    }

    @ViewBuilder
    private var testReportView: some View {
        if let r = testReport, r.total > 0 {
                        VStack(spacing: 6) {
                            Text("\(r.correct) bonnes réponses sur \(r.total)")
                                .font(.headline)
                                .foregroundStyle(r.rate > 0.4 ? .green
                                                 : r.rate > 0.25 ? .orange : .red)
                            Text("soit \(Int(r.rate * 100)) % — le hasard donnerait "
                                 + "\(Int(100.0 / Double(max(1, r.perCard.count)))) %")
                                .font(.caption).foregroundStyle(.secondary)

                            ForEach(r.perCard.sorted { $0.value.ok > $1.value.ok },
                                    id: \.key) { id, cell in
                                let name = CardCatalog.all.first { $0.id == id }?.name ?? id
                                let conf = r.confusedWith[id]?
                                    .max { $0.value < $1.value }
                                HStack {
                                    Text(name).font(.caption)
                                    Spacer()
                                    if let c = conf, cell.ok < cell.n {
                                        Text("↔ " + (CardCatalog.all.first {
                                            $0.id == c.key }?.name ?? c.key))
                                            .font(.caption2).foregroundStyle(.orange)
                                    }
                                    Text("\(cell.ok)/\(cell.n)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(
                                            cell.ok * 2 >= cell.n ? .green : .red)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
    }

    /// Liste des cartes apprises. Toucher une ligne déplie ses exemples,
    /// avec écoute et spectrogramme : c'est le seul moyen de vérifier que
    /// la capture contient bien le son de la carte et non celui d'à côté.
    @ViewBuilder
    private var cardList: some View {
        ForEach(learned.learnedCards) { c in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button {
                        expanded = (expanded == c.id) ? nil : c.id
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: expanded == c.id
                                  ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9))
                            Text(c.name).font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.primary)
                    }

                    Spacer()

                    if let sep = learned.separation(for: c.id) {
                        let gap = sep.own - sep.other
                        Text("\(Int(sep.own * 100))/\(Int(sep.other * 100))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(gap > 0.12 ? .green
                                             : (gap > 0.05 ? .orange : .red))
                    }

                    Text("\(Int(learned.fillRate(for: c.id) * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.blue)

                    Text("\(learned.maskStrength(for: c.id).cells)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button { learned.forget(c.id) } label: {
                        Image(systemName: "trash").font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                if expanded == c.id {
                    exampleRows(for: c)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Les exemples d'une carte, avec lecture audio et spectrogramme.
    @ViewBuilder
    private func exampleRows(for c: Card) -> some View {
        ForEach(0..<learned.count(for: c.id), id: \.self) { i in
            if let ex = learned.example(c.id, at: i) {
                SpectroView(frames: ex, height: 38)
                // L'audio n'accompagne que les exemples enregistrés depuis
                // la dernière réinstallation : l'export ne contient que les
                // spectrogrammes, bien plus légers.
                let hasAudio = (learned.audio(c.id, at: i)?.count ?? 0) > 100

                HStack(spacing: 10) {
                    Button {
                        if let a = learned.audio(c.id, at: i) {
                            AudioPlayback.shared.play(a)
                        }
                    } label: {
                        Image(systemName: hasAudio ? "play.circle.fill"
                                                   : "speaker.slash.circle")
                            .font(.title3)
                            .foregroundStyle(hasAudio ? .blue : .gray)
                    }
                    .disabled(!hasAudio)

                    Text("#\(i + 1)").font(.caption2)
                    if let cons = learned.consistency(c.id, at: i) {
                        Text("cohérence \(Int(cons * 100)) %")
                            .font(.caption2)
                            .foregroundStyle(cons >= 0.60 ? .green : .red)
                    }
                    Spacer()
                    Button { learned.remove(c.id, at: i) } label: {
                        Image(systemName: "trash").font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
                // --- 3. Bilan ---
                VStack(spacing: 6) {
                    Text("\(learned.cardCount) cartes apprises · \(learned.totalExamples) exemples")
                        .font(.caption)
                        .foregroundStyle(learned.isUsable ? .green : .orange)
                    Text(learned.lastMessage)
                        .font(.caption2).foregroundStyle(.blue)

                    // Résumé compact : afficher les spectrogrammes de dizaines
                    // d'exemples rendait l'écran inutilisable. On ne garde que
                    // l'essentiel ; les sons restent en mémoire et partent
                    // intégralement à l'export.
                    if learned.myDeck.isEmpty {
                        Text("Déclare ton deck ci-dessus : sans lui, l'app ne peut "
                             + "pas savoir quelle carte associer à une baisse d'élixir, "
                             + "et n'enregistre donc rien.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }

                    cardList
                    }

                    // Le choix de méthode se mesure, il ne se devine pas :
                    // change ici puis relance le test pour comparer.
                    Picker("Méthode", selection: $method) {
                        ForEach(LearnedSounds.Method.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: method) { newValue in
                        LearnedSounds.method = newValue
                        testReport = nil
                    }

                    Button {
                        LearnedSounds.method = method
                        testReport = learned.selfTest()
                    } label: {
                        Label("Tester la reconnaissance", systemImage: "checkmark.seal")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.green.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 12)

                    testReportView

                    Button {
                        exportURL = writeExport()
                        showShare = exportURL != nil
                    } label: {
                        Label("Exporter tout (\(learned.totalExamples) dont \(learned.freshExamples) nouveaux)",
                              systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.blue.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 8)

                    Text("Les exemples restaurés depuis le fichier n'ont pas de son : "
                         + "seuls les spectrogrammes sont exportés. Les nouveaux "
                         + "enregistrements restent écoutables jusqu'à la prochaine "
                         + "réinstallation.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Dépose le fichier dans App/BankedSounds.swift sur GitHub : "
                         + "tes exemples seront compilés dans l'app et ne se perdront plus.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Tout oublier", role: .destructive) { learned.forgetAll() }
                        .font(.footnote).padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
        }
    }


/// Passerelle vers la feuille de partage d'iOS.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}