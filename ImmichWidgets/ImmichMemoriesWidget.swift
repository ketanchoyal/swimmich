import ImmichSharedKit
import SwiftUI
import WidgetKit

/// "On this day" — one memory at a time, with a shuffle button that swaps it in
/// place (no app launch). Views live in `ImmichSharedKit`, see
/// `ImmichGridWidget` for why.
struct ImmichMemoriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ImmichWidgetKind.memories, provider: MemoriesTimelineProvider()) { entry in
            WidgetMemoriesView(feed: entry.feed)
                .widgetCanvas()
                // One widget, one `widgetURL`: a tap anywhere outside the
                // shuffle button opens the app on the Memories tab.
                .widgetURL(WidgetDeepLink.memories.url)
        }
        .configurationDisplayName("Immich Memories")
        .description("What you were doing on this day, years ago.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}

struct MemoriesEntry: TimelineEntry {
    let date: Date
    let feed: WidgetMemoryFeed
}

struct MemoriesTimelineProvider: TimelineProvider {
    private let provider = WidgetDataProvider()

    func placeholder(in context: Context) -> MemoriesEntry {
        MemoriesEntry(date: .now, feed: WidgetPlaceholder.memories())
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoriesEntry) -> Void) {
        guard !context.isPreview else {
            completion(placeholder(in: context))
            return
        }
        Task {
            completion(await entry(for: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoriesEntry>) -> Void) {
        Task {
            let entry = await entry(for: context)
            completion(Timeline(
                entries: [entry],
                // Memories only change at midnight — no point waking sooner,
                // unless the fetch failed, in which case retry in a quarter hour.
                policy: .after(entry.feed.availability == .ready
                    ? Calendar.current.startOfDay(for: .now).addingTimeInterval(24 * 60 * 60 + 60)
                    : .now.addingTimeInterval(15 * 60))
            ))
        }
    }

    /// The shuffle offset lives in the extension's defaults, so the intent can
    /// change which memory is drawn without any network round trip.
    private func entry(for context: Context) async -> MemoriesEntry {
        let feed = await provider.memories(
            limit: context.family.memoryLimit,
            offset: WidgetMemoriesShuffle.offset
        )
        return MemoriesEntry(date: .now, feed: feed)
    }
}
