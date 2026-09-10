import ActivityKit
import ImmichSharedKit
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island rendering for the backup Live Activity.
///
/// Every view lives in `ImmichSharedKit` (shared, previewable — Xcode refuses
/// to render previews declared inside a widget extension); this file is only
/// the ActivityConfiguration glue that maps them onto the island regions.
struct BackupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BackupActivityAttributes.self) { context in
            BackupLockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.3))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BackupGlyph(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BackupIslandTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    BackupIslandCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BackupIslandBottom(state: context.state)
                }
            } compactLeading: {
                // Compact: the glyph's contour fills indigo with progress.
                // The island keeps its native black — a flood-tinted pill
                // reads as an alert, a filling ring reads as progress.
                // Horizontal padding on both sides: the leading region sits
                // right against the TrueDepth sensor, and anything touching
                // its edges gets clipped by the cutout.
                BackupCompactRing(state: context.state)
                    .padding(.horizontal, 2)
            } compactTrailing: {
                BackupPercent(progress: context.state.progress, size: 14)
                    .foregroundStyle(.white)
                    .padding(.trailing, 2)
            } minimal: {
                BackupCompactRing(state: context.state, diameter: 18)
            }
            // Indigo keyline: the thin outline iOS draws around the island
            // while this activity owns it, so the whole contour is branded.
            .keylineTint(context.state.phase == .done && context.state.failed == 0
                         ? backupSuccessGreen : backupBrandEnd)
        }
    }
}

@main
struct ImmichWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BackupLiveActivity()
        ImmichHomeWidget()
    }
}
