import ActivityKit
import WidgetKit
import SwiftUI

struct ElixirLiveActivity: Widget {
    var body: some WidgetConfiguration {

        ActivityConfiguration(for: ElixirAttributes.self) { context in

            // --- Écran verrouillé ---
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Élixir adverse").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("x\(context.state.rate)").font(.caption.bold())
                }
                ProgressView(timerInterval: context.state.fillRange, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(.purple)
            }
            .padding()

        } dynamicIsland: { context in

            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(.purple)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("x\(context.state.rate)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        // Barre auto-animée : 0 à 10 élixir
                        ProgressView(timerInterval: context.state.fillRange, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(.purple)

                        // Temps restant avant 10 élixir (auto-animé aussi)
                        Text(timerInterval: context.state.fillRange, countsDown: true)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.purple)
            } compactTrailing: {
                ProgressView(timerInterval: context.state.fillRange, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(.purple)
                .frame(width: 22)
            } minimal: {
                ProgressView(timerInterval: context.state.fillRange, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(.purple)
            }
        }
    }
}
