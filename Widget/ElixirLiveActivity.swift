import ActivityKit
import WidgetKit
import SwiftUI

struct ElixirLiveActivity: Widget {
    var body: some WidgetConfiguration {

        ActivityConfiguration(for: ElixirAttributes.self) { context in

            // --- Écran verrouillé / bannière ---
            HStack {
                VStack(alignment: .leading) {
                    Text("Élixir adverse").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.1f", context.state.elixir))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("x\(context.state.rate)").font(.caption)
                    Text(context.state.startDate, style: .timer)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .frame(width: 110, alignment: .trailing)
                }
            }
            .padding()

        } dynamicIsland: { context in

            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(String(format: "%.1f", context.state.elixir))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("x\(context.state.rate)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.startDate, style: .timer)
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: "drop.fill").foregroundStyle(.purple)
            } compactTrailing: {
                Text(String(format: "%.1f", context.state.elixir))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } minimal: {
                Text(String(format: "%.0f", context.state.elixir))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
            }
        }
    }
}
