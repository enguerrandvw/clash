import SwiftUI

// Écran d'apprentissage : on choisit une carte, on la pose en jeu,
// l'app enregistre le son tel qu'elle l'entend réellement.
struct LearnView: View {
    @ObservedObject private var learned = LearnedSounds.shared
    @ObservedObject private var capture = CaptureBridge.shared
    @ObservedObject private var sound = SoundAnalyzer.shared
    @State private var search = ""

    private var results: [Card] {
        let q = CardCatalog.normalize(search)
        if q.isEmpty {
            return CardCatalog.all.filter { learned.count(for: $0.id) > 0 }
        }
        return CardCatalog.all.filter {
            CardCatalog.normalize($0.name).contains(q)
                || $0.aliases.contains { CardCatalog.normalize($0).contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 12) {

            Text("Apprentissage des sons")
                .font(.headline)

            // Carte en cours
            if let t = learned.target {
                VStack(spacing: 4) {
                    Text("Pose maintenant : \(t.name) (\(t.cost))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("Ton élixir doit baisser de \(t.cost)")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Annuler") { learned.target = nil }
                        .font(.caption)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            } else {
                Text("Choisis une carte, puis pose-la en jeu")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Enregistrement manuel : le plus fiable
            if let t = learned.target {
                let age = Date().timeIntervalSince(sound.lastCaptureAt)
                Button {
                    if sound.lastCapture.count >= 20 {
                        learned.add(sound.lastCapture, for: t)
                    } else {
                        learned.lastMessage = "Aucune impulsion récente"
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text("Enregistrer la dernière impulsion")
                            .font(.subheadline.weight(.semibold))
                        Text(sound.lastCapture.isEmpty ? "aucune"
                             : String(format: "il y a %.1f s", age))
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(age < 5 ? Color.blue.opacity(0.25)
                                        : Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)

                // Exemples déjà enregistrés pour cette carte
                if learned.count(for: t.id) > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Exemples enregistrés — supprime ceux dont la cohérence est basse")
                            .font(.caption2).foregroundStyle(.secondary)
                        ForEach(0..<learned.count(for: t.id), id: \.self) { i in
                            HStack(spacing: 10) {
                                Text("#\(i + 1)").font(.caption.monospaced())
                                if let c = learned.consistency(t.id, at: i) {
                                    Text("cohérence \(Int(c * 100)) %")
                                        .font(.caption)
                                        .foregroundStyle(c > 0.75 ? .green
                                                         : (c > 0.55 ? .orange : .red))
                                } else {
                                    Text("—").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    learned.remove(t.id, at: i)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.gray.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Text(learned.lastMessage)
                .font(.caption).foregroundStyle(.blue)

            HStack {
                Text("Ton élixir : \(capture.myElixir)")
                Spacer()
                Text("\(learned.cardCount) cartes · \(learned.totalExamples) exemples")
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 20)

            TextField("Chercher une carte…", text: $search)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding(.horizontal, 20)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(results) { card in
                        Button {
                            learned.target = card
                            learned.lastMessage = "En attente de \(card.name)…"
                        } label: {
                            HStack {
                                Text(card.name)
                                    .foregroundStyle(.primary)
                                Text("(\(card.cost))")
                                    .foregroundStyle(.purple)
                                Spacer()
                                let n = learned.count(for: card.id)
                                if n > 0 {
                                    Text("\(n) appris")
                                        .font(.caption)
                                        .foregroundStyle(n >= 3 ? .green : .orange)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(learned.target?.id == card.id
                                        ? Color.green.opacity(0.2)
                                        : Color.gray.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .contextMenu {
                            if learned.count(for: card.id) > 0 {
                                Button("Oublier cette carte", role: .destructive) {
                                    learned.forget(card.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Button("Tout oublier", role: .destructive) { learned.forgetAll() }
                .font(.footnote)
                .padding(.bottom, 14)
        }
        .padding(.top, 16)
    }
}
