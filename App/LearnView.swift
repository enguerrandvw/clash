import SwiftUI

// Apprentissage sans manipulation en jeu :
// on déclare son deck une fois, puis l'app apprend toute seule.
struct LearnView: View {
    @ObservedObject private var learned = LearnedSounds.shared
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
                            Text(c.name).font(.caption.weight(.medium))
                            ForEach(0..<learned.count(for: c.id), id: \.self) { i in
                                HStack {
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
