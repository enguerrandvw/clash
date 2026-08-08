import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: ElixirEngine

    private let costs = [1, 2, 3, 4, 5, 6, 7, 8, 9]

    var body: some View {
        VStack(spacing: 20) {

            Text("Élixir adverse")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(String(format: "%.1f", engine.elixir))
                .font(.system(size: 78, weight: .bold, design: .rounded))
                .foregroundStyle(.purple)
                .monospacedDigit()

            // Vitesse de régénération
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

            // Coût des cartes posées par l'adversaire
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(costs, id: \.self) { c in
                    Button {
                        engine.spend(c)
                    } label: {
                        Text("-\(c)")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 56)
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
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(engine.running ? Color.red : Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)

            Text(engine.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 30)
    }
}
