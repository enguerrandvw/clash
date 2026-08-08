import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var engine: ElixirEngine
    @ObservedObject private var dummy = DummyObserver()

    private let costs = [1, 2, 3, 4, 5, 6, 7, 8, 9]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                PiPPreview(overlay: engine.overlay)
                    .frame(height: 105)
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
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 50)
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

                Button {
                    engine.overlay.start()
                } label: {
                    Text("Ouvrir la fenêtre flottante")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                VStack(spacing: 3) {
                    Text(engine.status)
                    Text("Images rendues : \(engine.overlay.framesSent)")
                    Text(engine.overlay.isPossible ? "PiP disponible" : "PiP indisponible")
                    Text(engine.overlay.isActive ? "Fenêtre active" : "Fenêtre fermée")
                    if let err = engine.overlay.lastError {
                        Text(err).foregroundStyle(.red)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .padding(.vertical, 16)
        }
    }
}

private final class DummyObserver: ObservableObject {}

// Conteneur qui garde la couche vidéo à la bonne taille
struct PiPPreview: UIViewRepresentable {
    let overlay: PiPOverlay

    func makeUIView(context: Context) -> LayerHostView {
        let v = LayerHostView()
        v.backgroundColor = .black
        v.hosted = overlay.displayLayer
        v.layer.addSublayer(overlay.displayLayer)
        // Le contrôleur PiP ne peut être créé qu'une fois la couche en place
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
