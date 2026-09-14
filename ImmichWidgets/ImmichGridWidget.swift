import ImmichSharedKit
import SwiftUI
import WidgetKit

/// Newest photos — the "wall".
///
/// The composition itself lives in `ImmichSharedKit` (`WidgetPhotosView`): Xcode
/// refuses to render previews declared inside a widget-extension target, so
/// every drawable view sits in the shared framework where it can be previewed,
/// and this file is only the WidgetKit declaration + timeline plumbing.
struct ImmichGridWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ImmichWidgetKind.photos, provider: PhotosTimelineProvider()) { entry in
            WidgetPhotosView(wall: entry.wall)
                .widgetCanvas()
        }
        .configurationDisplayName("Immich Photos")
        .description("Your newest photos, with the heart to keep one.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline,
        ])
        // The mosaic is meant to bleed to the platter's edge, like the system
        // Photos widget; `WidgetCanvas` hands the system margins back to the
        // Lock Screen families, which must keep them.
        .contentMarginsDisabled()
    }
}

struct PhotosEntry: TimelineEntry {
    let date: Date
    let wall: PhotoWall
}

struct PhotosTimelineProvider: TimelineProvider {
    private let provider = WidgetDataProvider()

    func placeholder(in context: Context) -> PhotosEntry {
        PhotosEntry(date: .now, wall: WidgetPlaceholder.wall())
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotosEntry) -> Void) {
        guard !context.isPreview else {
            completion(placeholder(in: context))
            return
        }
        Task {
            let wall = await provider.recentPhotos(limit: context.family.photoLimit)
            completion(PhotosEntry(date: .now, wall: wall))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotosEntry>) -> Void) {
        Task {
            let wall = await provider.recentPhotos(limit: context.family.photoLimit)
            completion(Timeline(
                entries: [PhotosEntry(date: .now, wall: wall)],
                // A failed fetch (offline, locked, server down) retries soon:
                // half an hour of an empty widget is a long time to be wrong.
                policy: .after(.now.addingTimeInterval(wall.availability == .ready ? 30 * 60 : 5 * 60))
            ))
        }
    }
}
