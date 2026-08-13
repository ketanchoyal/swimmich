import SwiftUI

/// Memories tab — Photos-style "On this day" cards, one per server memory.
/// Each card shows the year + an asset grid; tapping opens the photo viewer
/// paging through that memory's assets. Empty state when the server has no
/// memories (e.g. a fresh library).
struct MemoriesView: View {
    @Bindable var vm: MemoriesViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.openProfile) private var openProfile

    @State private var viewerItem: PhotoViewerItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if vm.memories.isEmpty && vm.isLoading {
                    ProgressView("Loading memories…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = vm.errorMessage, vm.memories.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't load memories", systemImage: "sparkles.rectangle.stack")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await vm.load() } }
                            .buttonStyle(PVPrimaryButtonStyle())
                    }
                } else if vm.memories.isEmpty {
                    ContentUnavailableView(
                        "No Memories Yet",
                        systemImage: "sparkles.rectangle.stack",
                        description: Text("Photos from this day in past years will appear here.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: PVSpacing.s16) {
                            // Refresh failures keep the stale list (try-then-mutate)
                            // — surface the error instead of hiding it.
                            if let error = vm.errorMessage {
                                refreshErrorBanner(error)
                            }
                            LazyVStack(spacing: PVSpacing.s24) {
                                ForEach(vm.memories, id: \.id) { memory in
                                    MemoryCard(
                                        memory: memory,
                                        baseURL: baseURL,
                                        token: auth.accessToken,
                                        onOpen: { index in openViewer(memory: memory, at: index) }
                                    )
                                }
                            }
                        }
                        .padding(PVSpacing.s16)
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileAvatarButton { openProfile() }
                }
            }
            .task { await vm.load() }
            .photoViewer(
                item: $viewerItem,
                baseURL: baseURL,
                token: auth.accessToken,
                onDataChanged: { Task { await vm.load() } }
            )
        }
    }

    /// `auth.baseURL` is guaranteed non-nil while authenticated (codebase-wide
    /// convention — see TimelineView/TrashView/SearchView). Fallback never
    /// renders a card in practice.
    private var baseURL: URL {
        auth.baseURL ?? URL(string: "https://example.com")!
    }

    private func openViewer(memory: MemoryResponseDto, at index: Int) {
        let items = memory.assets.map { AssetReactItem(from: $0) }
        guard !items.isEmpty else { return }
        // Clamp: "+N more" opens at the first hidden asset; grid taps pass
        // their own index (Photos parity).
        let clamped = min(max(index, 0), items.count - 1)
        viewerItem = PhotoViewerItem(assets: items, index: clamped)
    }

    private func refreshErrorBanner(_ message: String) -> some View {
        HStack(spacing: PVSpacing.s8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.immichWarning)
            Text(message)
                .font(.pvCaption)
                .foregroundStyle(Color.textSecondaryPV)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Try Again") { Task { await vm.load() } }
                .font(.pvCaption.weight(.semibold))
                .foregroundStyle(Color.immichPrimary)
        }
        .padding(PVSpacing.s12)
        .background(Color.bgTertiary.opacity(0.5), in: RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One "On this day" card: exact day + years-ago header, the memory's assets in a
/// 3-column square mosaic (Photos-style, fill-cropped — no letterboxing), and
/// a footer with photo/video counts, location and a "+N more" affordance.
/// Tapping a photo opens the viewer at that photo; "+N more" at the first
/// hidden one.
private struct MemoryCard: View {
    let memory: MemoryResponseDto
    let baseURL: URL
    let token: String?
    let onOpen: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    /// First 9 assets rendered in the mosaic; the rest live behind "+N more".
    private var visibleAssets: [AssetResponseDto] {
        Array(memory.assets.prefix(9))
    }

    private var hiddenCount: Int {
        max(memory.assets.count - 9, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PVSpacing.s12) {
            header
            LazyVGrid(columns: columns, spacing: PVSpacing.s2) {
                ForEach(Array(visibleAssets.enumerated()), id: \.element.id) { index, dto in
                    Button {
                        onOpen(index)
                    } label: {
                        thumbnailCell(dto)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Memory photo from \(memory.data.year)"))
                }
            }
            footer
        }
        .padding(PVSpacing.s16)
        .background(Color.bgTertiary.opacity(0.5), in: RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: PVSpacing.s8) {
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                if let day = MemoryCardPresentation.dayLabel(for: memory) {
                    Text(day)
                        .font(.pvBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimaryPV)
                }
                if let count = MemoryCardPresentation.yearsAgoCount(year: memory.data.year),
                   let ago = MemoryCardPresentation.yearsAgoText(count: count) {
                    Text(ago)
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }
            }
            Spacer(minLength: 0)
            Text(String(memory.data.year))
                .font(.pvTitle)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimaryPV)
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: PVSpacing.s8) {
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                if let media = MemoryCardPresentation.mediaCountLabel(for: memory) {
                    Text(media)
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }
                if let location = MemoryCardPresentation.locationLabel(for: memory) {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }
            }
            Spacer(minLength: PVSpacing.s8)
            if hiddenCount > 0 {
                Button {
                    onOpen(visibleAssets.count)
                } label: {
                    Text(String(localized: "+\(hiddenCount) more"))
                        .font(.pvCaption.weight(.semibold))
                        .foregroundStyle(Color.immichPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Square fill-cropped thumbnail (AssetThumbnailCell pattern). The square
    /// frame comes from `Color.clear.aspectRatio(1,.fit)`; the image overlays
    /// and crops with `.fill` — no letterboxing on mixed aspect ratios.
    private func thumbnailCell(_ dto: AssetResponseDto) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AuthenticatedAsyncImage(
                    url: ImmichAssetURL.thumbnail(assetId: dto.id, thumbhash: dto.thumbhash ?? "", baseURL: baseURL),
                    token: token
                )
            }
            .overlay(alignment: .topTrailing) { favoriteBadge(dto) }
            .overlay(alignment: .bottomTrailing) { videoBadge(dto) }
            .clipShape(RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func favoriteBadge(_ dto: AssetResponseDto) -> some View {
        if dto.isFavorite {
            badge {
                Image(systemName: "heart.fill")
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func videoBadge(_ dto: AssetResponseDto) -> some View {
        if dto.type == "VIDEO" {
            badge {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 8)) // DS-exempt: badge micro-glyph §8.6
                    if let d = dto.duration, d > 0 {
                        Text(AssetThumbnailCell.formattedDuration(d)).monospacedDigit()
                    }
                }
            }
            .padding(4)
        }
    }

    /// Shared capsule treatment — mirrors AssetThumbnailCell's uniform badge
    /// language (V4). `.ultraThinMaterial` + thin border.
    @ViewBuilder
    private func badge<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .font(.pvCaption)
            .foregroundStyle(.white) // DS-exempt: badge contrast on material
            .padding(.horizontal, PVSpacing.s8)
            .padding(.vertical, 3) // DS-exempt: badge micro-padding
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5) // DS-exempt: micro-badge shadow
    }
}

/// Pure presentation helpers for the memory card (date/location/count labels).
/// No SwiftUI state — unit-testable.
enum MemoryCardPresentation {

    /// Parses a UTC `memoryAt` timestamp; tolerates both fractional
    /// ("…00.000Z") and plain ("…00Z") seconds. Nil when malformed.
    static func parseMemoryAt(_ iso: String) -> Date? {
        fractionalParser.date(from: iso) ?? plainParser.date(from: iso)
    }

    /// "July 1" from a UTC timestamp (memory day kept in UTC — memoryAt is a
    /// UTC "this day" anchor, a local tz shift would flip the day). The
    /// `MMMMd` template keeps day/month order locale-correct ("July 1" en,
    /// "1 juillet" fr).
    static func monthDayLabel(from date: Date, locale: Locale = .current) -> String {
        if locale == Locale.current {
            return monthDayFormatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter.string(from: date)
    }

    /// "July 1" — the card's title line. Nil when memoryAt can't be parsed.
    static func dayLabel(for memory: MemoryResponseDto, locale: Locale = .current) -> String? {
        guard let date = parseMemoryAt(memory.memoryAt) else { return nil }
        return monthDayLabel(from: date, locale: locale)
    }

    /// Years elapsed since the memory's year (calendar year arithmetic); nil
    /// when the year is current or in the future (no such memories server-side,
    /// but cheap to guard).
    static func yearsAgoCount(year: Int, now: Date = .now) -> Int? {
        let diff = Calendar.current.component(.year, from: now) - year
        return diff > 0 ? diff : nil
    }

    /// "Last year" / "N years ago" for a count from `yearsAgoCount`.
    static func yearsAgoText(count: Int, locale: Locale = .current) -> String? {
        guard count > 0 else { return nil }
        if count == 1 { return String(localized: "Last year", locale: locale) }
        return String(localized: "\(count) years ago", locale: locale)
    }

    /// Photo/video split of a memory's assets.
    static func mediaCount(for memory: MemoryResponseDto) -> (photos: Int, videos: Int) {
        let photos = memory.assets.filter { $0.type == "IMAGE" }.count
        return (photos, memory.assets.count - photos)
    }

    /// "12 photos" / "1 video" / "8 photos · 2 videos". Nil for an empty
    /// memory (server never sends one, but guards the formatting).
    static func mediaCountLabel(for memory: MemoryResponseDto, locale: Locale = .current) -> String? {
        let (photos, videos) = mediaCount(for: memory)
        switch (photos, videos) {
        case (0, 0): return nil
        case (_, 0): return photoLabel(photos, locale: locale)
        case (0, _): return videoLabel(videos, locale: locale)
        default: return "\(photoLabel(photos, locale: locale)) · \(videoLabel(videos, locale: locale))"
        }
    }

    /// "Paris, France" from the first asset carrying EXIF location (city →
    /// country fallback, whitespace-trimmed).
    static func locationLabel(for memory: MemoryResponseDto) -> String? {
        for asset in memory.assets {
            guard let exif = asset.exifInfo else { continue }
            let city = trimmed(exif.city)
            let country = trimmed(exif.country)
            switch (city, country) {
            case (let city?, let country?): return "\(city), \(country)"
            case (let city?, nil): return city
            case (nil, let country?): return country
            case (nil, nil): continue
            }
        }
        return nil
    }

    private static func photoLabel(_ n: Int, locale: Locale) -> String {
        n == 1 ? String(localized: "1 photo", locale: locale) : String(localized: "\(n) photos", locale: locale)
    }

    private static func videoLabel(_ n: Int, locale: Locale) -> String {
        n == 1 ? String(localized: "1 video", locale: locale) : String(localized: "\(n) videos", locale: locale)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let fractionalParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        parser.timeZone = TimeZone(identifier: "UTC")
        return parser
    }()

    private static let plainParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        parser.timeZone = TimeZone(identifier: "UTC")
        return parser
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter
    }()
}
