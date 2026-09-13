import ImmichSharedKit
import SwiftUI
import WidgetKit

/// Every widget and Live Activity this extension ships.
///
/// `@main` lives here and nowhere else: a `WidgetBundle` is all-or-nothing, so
/// the backup Live Activity that used to own it is registered as one member.
@main
struct ImmichWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BackupLiveActivity()
        ImmichHomeWidget()
        ImmichGridWidget()
        ImmichMemoriesWidget()
        ImmichFavoritesWidget()
    }
}
