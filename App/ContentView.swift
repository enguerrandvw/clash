import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var engine: ElixirEngine

    private let costs = [1, 2, 3, 4, 5, 6, 7, 8, 9]

    var body: some View {
        VStack(spacing: 18) {

            // Aperçu réel de la fenêtre flottante
            PiPPreview(layer: engine.overlay.displayLayer)
                .frame(height: 110)
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
                            .frame(maxWidth: .infinity, minHeight: 52)
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
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(engine.running ? Color.red : Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)

            VStack(spacing: 3) {
                Text(engine.status)
                Text(engine.overlay.isActive ? "Fenêtre flottante active" : "Fenêtre en attente")
                if let err = engine.overlay.lastError {
                    Text(err).foregroundStyle(.red)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
    }
}

// Affiche la couche vidéo dans l'app pour pouvoir la contrôler
struct PiPPreview: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        v.layer.addSublayer(layer)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = uiView.bounds
        CATransaction.commit()
    }
}
