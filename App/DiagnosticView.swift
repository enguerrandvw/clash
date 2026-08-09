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

                // 1. Canal de communication
                ligne("Socket locale",
                      bridge.listening ? "à l'écoute" : "inactive",
                      bridge.listening ? .green : .red)

                Text("Extension attendue : \(CaptureBridge.extensionID)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                // 2. Fraîcheur des données
                ligne("Flux", bridge.freshness,
                      bridge.freshness.hasPrefix("en direct") ? .green : .orange)

                ligne("État extension", bridge.note, .secondary)
                ligne("Images reçues", "\(bridge.frames)",
                      bridge.frames > 0 ? .green : .red)
                ligne("Tampons audio", "\(bridge.audioBuffers)",
                      bridge.audioBuffers > 0 ? .green : .red)
                ligne("Format image", bridge.pixelFormat, .secondary)
                ligne("Format audio", bridge.audioFormat, .secondary)
                ligne("Mémoire extension",
                      String(format: "%.1f Mo / 50", bridge.memoryMB),
                      bridge.memoryMB > 40 ? .red
                        : (bridge.memoryMB > 25 ? .orange : .green))

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
                    Text(String(format: "crête %.3f · maximum atteint %.3f",
                                bridge.audioPeak, bridge.audioPeakMax))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                // 4. Échantillons de la bande basse
                if !bridge.band.isEmpty {
                    VStack(spacing: 6) {
                        Text("Barre d'élixir — 10 points échantillonnés")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            ForEach(Array(bridge.band.enumerated()), id: \.offset) { _, v in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(v > 40 ? Color.purple : Color.gray.opacity(0.25))
                                    .frame(height: 34)
                                    .overlay(Text("\(v)").font(.system(size: 9))
                                                .foregroundStyle(.white))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                if !bridge.rowProfile.isEmpty {
                    VStack(spacing: 4) {
                        Text(String(format: "Profil vertical — ligne la plus colorée à %.0f %% de la hauteur",
                                    bridge.bestRowFrac * 100))
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(Array(bridge.rowProfile.enumerated()), id: \.offset) { _, v in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(v > 25 ? Color.purple : Color.gray.opacity(0.3))
                                    .frame(height: max(3, CGFloat(min(v, 90))))
                            }
                        }
                        .frame(height: 90, alignment: .bottom)
                        .padding(.horizontal, 20)
                    }
                }

                if let e = bridge.lastError {
                    Text(e).font(.caption).foregroundStyle(.red)
                        .padding(.horizontal, 20)
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
        .onAppear { bridge.startListening() }
        .onDisappear { bridge.stopListening() }
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
