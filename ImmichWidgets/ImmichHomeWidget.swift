import SwiftUI
import WidgetKit

/// Home-screen widget (P5 widgets-appintents): static "launch" tile that opens
/// the app (and triggers a backup via the `app.immich://backup` deep link).
/// The widget process cannot reach the app's view models, so it stays
/// data-free — the Live Activity covers live progress.
struct ImmichHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ImmichHomeWidget", provider: ImmichHomeTimelineProvider()) { _ in
            VStack(spacing: 8) {
                Image("AppIcon")
                    .resizable()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Immich")
                    .font(.headline)
                Text("Back up now")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) {
                Color(UIColor.systemBackground)
            }
            .widgetURL(URL(string: "app.immich://backup"))
        }
        .configurationDisplayName("Immich")
        .description("Open Immich and start a backup.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ImmichHomeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry() }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry()], policy: .never))
    }
}

private struct SimpleEntry: TimelineEntry {
    let date = Date()
}
