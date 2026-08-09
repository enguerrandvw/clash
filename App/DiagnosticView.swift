import SwiftUI

// Écran de validation de la capture. Il répond à trois questions :
// l'App Group fonctionne-t-il, l'image arrive-t-elle, l'audio du jeu arrive-t-il.
struct DiagnosticView: View {
    @StateObject private var bridge = CaptureBridge()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                Text("Diagnostic de capture")
                    .font(.headline)

                // 1. App Group
                ligne("Espace partagé",
                      bridge.groupOK ? "OK" : "INDISPONIBLE",
                      bridge.groupOK ? .green : .red)

                // 2. Fraîcheur des données
                ligne("Flux", bridge.freshness,
                      bridge.freshness.hasPrefix("en direct") ? .green : .orange)

                ligne("État extension", bridge.note, .secondary)
                ligne("Images reçues", "\(bridge.frames)",
                      bridge.frames > 0 ? .green : .red)
                ligne("Tampons audio", "\(bridge.audioBuffers)",
                      bridge.audioBuffers > 0 ? .green : .red)

                // 3. Niveau sonore : LE test décisif
                VStack(alignment: .leading, spacing: 6) {
                    Text("Niveau audio du jeu")
                        .font(.subheadline.weight(.medium))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(bridge.audioPeak > 0.02 ? Color.green : Color.gray)
                                .frame(width: geo.size.width * CGFloat(min(1, bridge.audioPeak * 3)))
                        }
                    }
                    .frame(height: 22)
                    Text(String(format: "crête %.3f", bridge.audioPeak))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                // 4. Ce que voit l'extension
                if let img = bridge.screenshot {
                    VStack(spacing: 4) {
                        Text("Écran capturé").font(.caption).foregroundStyle(.secondary)
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if let b = bridge.band {
                    VStack(spacing: 4) {
                        Text("Bande basse — ta barre d'élixir doit être visible ici")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Image(uiImage: b)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 12)
                }

                // Commandes
                VStack(spacing: 10) {
                    HStack {
                        Text("Lancer / arrêter la capture")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        BroadcastButton().frame(width: 56, height: 56)
                    }
                    Button("Remettre les compteurs à zéro") { bridge.reset() }
                        .font(.footnote)
                }
                .padding(.horizontal, 20)

                Text("Appuie sur le bouton, choisis « Capture Elixir », puis Démarrer. "
                     + "Va dans Clash Royale quelques secondes et reviens ici.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
            }
            .padding(.top, 16)
        }
        .onAppear { bridge.startWatching() }
        .onDisappear { bridge.stopWatching() }
    }

    private func ligne(_ titre: String, _ valeur: String, _ couleur: Color) -> some View {
        HStack {
            Text(titre).font(.subheadline)
            Spacer()
            Text(valeur).font(.subheadline.weight(.semibold)).foregroundStyle(couleur)
        }
        .padding(.horizontal, 20)
    }
}
