import ActivityKit
import ImmichSharedKit
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island rendering for the backup Live Activity.
struct BackupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BackupActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label("Immich Backup", systemImage: "square.and.arrow.up")
                    .font(.headline)
                ProgressView(value: context.state.progress)
                    .tint(Color(red: 0.259, green: 0.314, blue: 0.686))
                Text("\(context.state.uploaded) of \(context.state.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.25))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(percentLabel(context.state.progress))
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.uploaded) / \(context.state.total)")
                        .font(.caption2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(Color(red: 0.259, green: 0.314, blue: 0.686))
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "square.and.arrow.up")
            } compactTrailing: {
                Text(percentLabel(context.state.progress))
            } minimal: {
                Text(percentLabel(context.state.progress))
            }
        }
    }

    private func percentLabel(_ progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }
}

@main
struct ImmichWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BackupLiveActivity()
        ImmichHomeWidget()
    }
}