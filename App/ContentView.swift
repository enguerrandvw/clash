import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var engine: ElixirEngine
    @State private var showDiag = false
    @State private var showSound = false
    @State private var showLearn = false

    private let costs = [1, 2, 3, 4, 5, 6, 7, 8, 9]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                PiPPreview(overlay: engine.overlay)
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)

                Picker("Vitesse", selection: Binding(
                    get: { engine.rate },
                    set: { engine.setRate($0) }
                )) {
                    Text("x1").tag(1)
                    Text("x2").tag(2)
                    Text("x3").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(costs, id: \.self) { c in
                        Button {
                            engine.spend(c)
                        } label: {
                            Text("-\(c)")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(Color.purple.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!engine.running)
                    }
                }
                .padding(.horizontal, 24)

                Button {
                    engine.running ? engine.stop() : engine.start()
                } label: {
                    Text(engine.running ? "Arrêter" : "Démarrer la partie")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(engine.running ? Color.red : Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                VoiceSection(voice: engine.voice)

                Button {
                    showDiag = true
                } label: {
                    Label("Diagnostic de capture", systemImage: "record.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.teal.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                Button {
                    showLearn = true
                } label: {
                    Label("Apprendre les sons", systemImage: "graduationcap.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.green.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                Button {
                    showSound = true
                } label: {
                    Label("Analyse sonore", systemImage: "waveform")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.pink.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                OverlayStatus(overlay: engine.overlay, engineStatus: engine.status)
                    .padding(.bottom, 30)
            }
            .padding(.vertical, 16)
        }
        .sheet(isPresented: $showDiag) { DiagnosticView() }
        .sheet(isPresented: $showSound) { SoundView() }
        .sheet(isPresented: $showLearn) { LearnView() }
    }
}

// MARK: - Banc d'essai vocal

struct VoiceSection: View {
    @ObservedObject var voice: VoiceRecognizer

    var body: some View {
        VStack(spacing: 10) {

            Button {
                voice.toggle()
            } label: {
                HStack {
                    Image(systemName: voice.listening ? "mic.fill" : "mic.slash.fill")
                    Text(voice.listening ? "Micro actif" : "Activer le micro")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(voice.listening ? Color.orange : Color.gray.opacity(0.25))
                .foregroundStyle(voice.listening ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Text(voice.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let c = voice.lastCard {
                Text("\(c.name) — \(c.cost) élixir")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.purple)
                Text(String(format: "confiance %.0f %%", voice.lastScore * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !voice.transcript.isEmpty {
                Text(voice.transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !voice.history.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(voice.history, id: \.self) { line in
                        Text(line).font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Diagnostics

struct OverlayStatus: View {
    @ObservedObject var overlay: PiPOverlay
    let engineStatus: String

    var body: some View {
        VStack(spacing: 3) {
            Text(engineStatus)
            Text("Images rendues : \(overlay.framesSent)")
            Text(overlay.isPossible ? "PiP disponible" : "PiP indisponible")
            Text(overlay.isActive ? "Fenêtre active" : "Fenêtre fermée")
            if let err = overlay.lastError {
                Text(err).foregroundStyle(.red)
            }
            Button("Ouvrir la fenêtre flottante") { overlay.start() }
                .font(.subheadline)
                .padding(.top, 6)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
    }
}

// MARK: - Conteneur vidéo

struct PiPPreview: UIViewRepresentable {
    let overlay: PiPOverlay

    func makeUIView(context: Context) -> LayerHostView {
        let v = LayerHostView()
        v.backgroundColor = .black
        v.hosted = overlay.displayLayer
        v.layer.addSublayer(overlay.displayLayer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            overlay.attachController()
        }
        return v
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {}
}

final class LayerHostView: UIView {
    var hosted: CALayer?
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted?.frame = bounds
        CATransaction.commit()
    }
}
