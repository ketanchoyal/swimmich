import ImmichSharedKit
import SwiftUI
import WidgetKit

/// The favorites, with the heart as the subject. Views live in
/// `ImmichSharedKit`, see `ImmichGridWidget` for why.
struct ImmichFavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ImmichWidgetKind.favorites, provider: FavoritesTimelineProvider()) { entry in
            WidgetFavoritesView(wall: entry.wall)
                .widgetCanvas()
        }
        .configurationDisplayName("Immich Favorites")
        .description("The photos you kept.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}

struct FavoritesEntry: TimelineEntry {
    let date: Date
    let wall: PhotoWall
}

struct FavoritesTimelineProvider: TimelineProvider {
    private let provider = WidgetDataProvider()

    func placeholder(in context: Context) -> FavoritesEntry {
        FavoritesEntry(date: .now, wall: WidgetPlaceholder.wall(favorite: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void) {
        guard !context.isPreview else {
            completion(placeholder(in: context))
            return
        }
        Task {
            let wall = await provider.favoritePhotos(limit: context.family.photoLimit)
            completion(FavoritesEntry(date: .now, wall: wall))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void) {
        Task {
            let wall = await provider.favoritePhotos(limit: context.family.photoLimit)
            completion(Timeline(
                entries: [FavoritesEntry(date: .now, wall: wall)],
                policy: .after(.now.addingTimeInterval(60 * 60))
            ))
        }
    }
}
