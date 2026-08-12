import SwiftUI

// Apprentissage sans manipulation en jeu :
// on déclare son deck une fois, puis l'app apprend toute seule.
struct LearnView: View {
    @ObservedObject private var learned = LearnedSounds.shared
    @ObservedObject private var sound = SoundAnalyzer.shared
    @ObservedObject private var capture = CaptureBridge.shared
    @State private var search = ""
    @State private var editingDeck = false

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
                    Text("\(SoundTemplates.all.count) motifs de référence")
                        .font(.caption2).foregroundStyle(.secondary)

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

                    Text("appris \(learned.autoLearned) · en attente \(learned.sentToPending)"
                         + " · sans événement \(sound.rejectedNoEvent)"
                         + " · hors deck \(learned.noCandidate)")
                        .font(.caption2).foregroundStyle(.blue)
                        .multilineTextAlignment(.center)
                }

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
                                Text("· \(learned.count(for: c.id))")
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

                // --- 3. Bilan ---
                VStack(spacing: 6) {
                    Text("\(learned.cardCount) cartes apprises · \(learned.totalExamples) exemples")
                        .font(.caption)
                        .foregroundStyle(learned.isUsable ? .green : .orange)
                    Text(learned.lastMessage)
                        .font(.caption2).foregroundStyle(.blue)

                    ForEach(learned.myDeck.filter { learned.count(for: $0.id) > 0 }) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(c.name).font(.caption.weight(.medium))
                                if let sep = learned.separation(for: c.id) {
                                    let gap = sep.own - sep.other
                                    Text("propre \(Int(sep.own * 100)) % · confusion \(Int(sep.other * 100)) % (\(sep.with))")
                                        .font(.caption2)
                                        .foregroundStyle(gap > 0.12 ? .green
                                                         : (gap > 0.05 ? .orange : .red))
                                }
                            }
                            ForEach(0..<learned.count(for: c.id), id: \.self) { i in
                                if let ex = learned.example(c.id, at: i) {
                                    SpectroView(frames: ex, height: 44)

                                    // Référence du dépôt la plus proche :
                                    // on la montre pour comparer à l'œil.
                                    if let hit = RefMatcher.cachedBest(
                                            key: "\(c.id)-\(i)", capture: ex),
                                       let rf = RefMatcher.frames(for: hit.refCard) {
                                        Text("réf. la plus proche : "
                                             + (hit.card?.name
                                                ?? hit.refCard.replacingOccurrences(
                                                    of: "_", with: " "))
                                             + " \(Int(hit.score * 100)) %")
                                            .font(.caption2)
                                            .foregroundStyle(
                                                hit.card?.id == c.id ? .green : .orange)
                                        SpectroView(frames: rf, height: 34)
                                            .opacity(0.85)
                                    }
                                }
                                HStack {
                                    Button {
                                        if let a = learned.audio(c.id, at: i) {
                                            AudioPlayback.shared.play(a)
                                        }
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(
                                                (learned.audio(c.id, at: i)?.count ?? 0) > 100
                                                ? .blue : .gray)
                                    }
                                    Text("#\(i + 1)").font(.caption2.monospaced())
                                    if let s = learned.consistency(c.id, at: i) {
                                        Text("cohérence \(Int(s * 100)) %")
                                            .font(.caption2)
                                            .foregroundStyle(s > 0.75 ? .green
                                                             : (s > 0.55 ? .orange : .red))
                                    }
                                    Spacer()
                                    Button { learned.remove(c.id, at: i) } label: {
                                        Image(systemName: "trash").font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button("Tout oublier", role: .destructive) { learned.forgetAll() }
                        .font(.footnote).padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .padding(.top, 16)
        }
    }
}
