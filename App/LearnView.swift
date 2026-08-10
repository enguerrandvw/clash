import SwiftUI

// Écran d'apprentissage : on choisit une carte, on la pose en jeu,
// l'app enregistre le son tel qu'elle l'entend réellement.
struct LearnView: View {
    @ObservedObject private var learned = LearnedSounds.shared
    @ObservedObject private var capture = CaptureBridge.shared
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
