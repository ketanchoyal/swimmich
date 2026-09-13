import SwiftUI

/// Full-screen memory "moment" — the nostalgia shot. A full-bleed swipeable
/// hero pager (one centered photo per page, slow Ken Burns on the active page)
/// with Liquid Glass chips floating over it (year, exact date, "N years ago",
/// location, people, tags, saved state).
///
/// Top bar: close (left), a centered "On this day" chip, and a "view in
/// timeline" teleport (right) that dismisses and jumps the Photos tab to this
/// photo. Swipe to browse; tap a photo for the full Photos-style pager.
///
/// It is also the memory's editing surface: the bottom action row saves or
/// unsaves it (`PUT /api/memories/{id}`), adds photos (`PUT
/// /api/memories/{id}/assets`), drops the photo currently on screen (`DELETE
/// …/assets`) and deletes the whole memory (`DELETE /api/memories/{id}`).
struct MemoryMomentView: View {
    let memory: MemoryResponseDto
    /// The memory's owner — mutations go through it so the list behind this
    /// screen shows the result, and so an emptied memory closes this screen.
    let vm: MemoriesViewModel
    let baseURL: URL
    let token: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openInTimeline) private var openInTimeline

    @State private var heroIndex = 0
    @State private var viewerItem: PhotoViewerItem?
    @State private var appeared = false
    @State private var kenBurns = false
    @State private var scrollPosition = ScrollPosition()
    @State private var isAutoPlaying = true
    @State private var isVideoActive = false
    @State private var showingAddPhotos = false
    @State private var confirmingDelete = false

    /// The asset currently shown as the hero (pager-selected, falls back to the
    /// first asset).
    private var heroAsset: AssetResponseDto? {
        memory.assets.indices.contains(heroIndex) ? memory.assets[heroIndex] : memory.assets.first
    }

    private var yearsAgoText: String? {
        guard let count = MemoryCardPresentation.yearsAgoCount(year: memory.data.year),
              let text = MemoryCardPresentation.yearsAgoText(count: count) else { return nil }
        return text
    }

    /// "Shot on iPhone 13" from the current hero asset's EXIF (make/model).
    private var heroCameraLabel: String? {
        guard let exif = heroAsset?.exifInfo else { return nil }
        let model = [exif.make, exif.model]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return model.isEmpty ? nil : model.joined(separator: " ")
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()
                heroPager
                scrims
                VStack(spacing: PVSpacing.s0) {
                    topBar
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -12)
                    Spacer()
                    bottomPanel
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 24 : 0)
                }
                .frame(width: proxy.size.width)
            }
            .onAppear(perform: appear)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: appeared)
        }
        .statusBarHidden(true)
        .photoViewer(item: $viewerItem, baseURL: baseURL, token: token)
        .onChange(of: heroIndex) { _, _ in
            isVideoActive = heroAsset?.type == "VIDEO"
            restartKenBurns()
        }
        .task(id: autoAdvanceKey) {
            guard isAutoPlaying, !isVideoActive, !reduceMotion, viewerItem == nil, memory.assets.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard isAutoPlaying, !isVideoActive, viewerItem == nil else { continue }
                advance()
            }
        }
    }

    /// Re-arms the auto-advance ticker whenever play state or video activity
    /// changes (same view-owned ticker pattern as `SlideshowView`).
    private var autoAdvanceKey: String { "\(isAutoPlaying)-\(isVideoActive)" }

    // MARK: - Hero pager (swipe to browse)

    private var heroPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(memory.assets.enumerated()), id: \.element.id) { index, dto in
                    heroPage(dto, index: index)
                        .id(dto.id)
                        .containerRelativeFrame(.horizontal)
                        .clipped()
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .interacting {
                isAutoPlaying = false
            }
        }
        .onScrollGeometryChange(for: Int.self) { geo in
            let width = geo.containerSize.width
            guard width > 0 else { return 0 }
            return min(max(Int((geo.contentOffset.x / width).rounded()), 0), memory.assets.count - 1)
        } action: { _, newIndex in
            heroIndex = newIndex
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func heroPage(_ dto: AssetResponseDto, index: Int) -> some View {
        Group {
            if dto.type == "VIDEO" && index == heroIndex {
                VideoPlayerView(
                    asset: AssetReactItem(from: dto),
                    baseURL: baseURL,
                    token: token,
                    controlsVisible: false,
                    videoGravity: .resizeAspectFill,
                    onPlaybackEnded: { videoEnded() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(kenBurns ? 1.08 : 1.0)
                .clipped()
            } else {
                let url = ImmichAssetURL.thumbnail(
                    assetId: dto.id,
                    thumbhash: dto.thumbhash ?? "",
                    baseURL: baseURL,
                    size: .preview
                )
                AuthenticatedAsyncImage(url: url, token: token, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(kenBurns && index == heroIndex ? 1.08 : 1.0)
                    .clipped()
                    .id(url.absoluteString)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { openViewer(at: index) })
        .accessibilityLabel(String(localized: "Open this memory's photos"))
    }

    private var scrims: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top, endPoint: .center
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .center, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Top bar

    private var topBar: some View {
        GlassEffectContainer {
            HStack(spacing: PVSpacing.s8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.pvHeadline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close memory"))

                Spacer(minLength: PVSpacing.s8)

                Label(
                    memory.type == .on_this_day ? String(localized: "On this day") : String(localized: "Memory"),
                    systemImage: "sparkles"
                )
                .font(.pvCaption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, PVSpacing.s12)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(.black.opacity(0.6)), in: Capsule())

                Spacer(minLength: PVSpacing.s8)

                Button {
                    if let asset = heroAsset {
                        openInTimeline(asset.id, String(asset.fileCreatedAt.prefix(10)))
                    }
                    dismiss()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.pvHeadline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(heroAsset == nil)
                .accessibilityLabel(String(localized: "View in timeline"))
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, PVSpacing.s16)
        .padding(.top, PVSpacing.s8)
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: PVSpacing.s12) {
            titleBlock
            pageDots
            chips
            actionRow
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PVSpacing.s16)
        .padding(.bottom, PVSpacing.s16)
    }

    /// The memory's mutations, over the hero. Each is a glass circle sized for
    /// the 44 pt minimum tap target; icons carry the meaning, VoiceOver the words.
    private var actionRow: some View {
        GlassEffectContainer {
            HStack(spacing: PVSpacing.s16) {
                actionButton(
                    symbol: memory.isSaved ? "bookmark.fill" : "bookmark",
                    label: memory.isSaved ? "Unsave memory" : "Save memory",
                    identifier: "memoryMomentSave"
                ) {
                    Task {
                        if memory.isSaved {
                            await vm.unsaveMemory(id: memory.id)
                        } else {
                            await vm.saveMemory(id: memory.id)
                        }
                    }
                }

                actionButton(
                    symbol: "plus.rectangle.on.rectangle",
                    label: "Add photos",
                    identifier: "memoryMomentAddPhotos"
                ) {
                    showingAddPhotos = true
                }

                actionButton(
                    symbol: "minus.circle",
                    label: "Remove this photo from the memory",
                    identifier: "memoryMomentRemovePhoto"
                ) {
                    guard let asset = heroAsset else { return }
                    Task { await removePhoto(asset.id) }
                }
                .disabled(heroAsset == nil)

                actionButton(
                    symbol: "trash",
                    label: "Delete memory",
                    identifier: "memoryMomentDelete"
                ) {
                    confirmingDelete = true
                }
            }
        }
        .sheet(isPresented: $showingAddPhotos) {
            AddPhotosToMemorySheet(
                memoryId: memory.id,
                existingAssetIds: Set(memory.assets.map(\.id)),
                vm: vm
            )
        }
        .confirmationDialog(
            "Delete this memory?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Memory", role: .destructive) {
                Task {
                    await vm.deleteMemory(id: memory.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The photos stay in your library — only this memory is removed.")
        }
    }

    private func actionButton(
        symbol: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .glassEffect(.regular.tint(.black.opacity(0.6)), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }

    /// Drops one photo from the memory. The server filters empty memories out of
    /// `GET /api/memories`, so when this was the last one the memory no longer
    /// exists to show — `removeAssets` reports that and this screen closes.
    private func removePhoto(_ assetId: String) async {
        let stillExists = await vm.removeAssets(fromMemoryId: memory.id, assetIds: [assetId])
        if !stillExists { dismiss() }
    }

    private var titleBlock: some View {
        VStack(spacing: PVSpacing.s4) {
            Text(String(memory.data.year))
                .font(.pvTitleXL)
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            if let subtitle = subtitleText {
                Text(subtitle)
                    .font(.pvSubhead)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// "1 juillet · il y a 3 ans" — fused day + elapsed line (the year is
    /// already the big numeral above, so the full date is redundant here).
    private var subtitleText: String? {
        let parts = [MemoryCardPresentation.dayLabel(for: memory), yearsAgoText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var pageDots: some View {
        if memory.assets.count > 1 {
            HStack(spacing: PVSpacing.s4) {
                ForEach(memory.assets.indices, id: \.self) { index in
                    Circle()
                        .fill(index == heroIndex ? Color.white : Color.white.opacity(0.35))
                        .frame(width: index == heroIndex ? 8 : 6, height: index == heroIndex ? 8 : 6)
                }
            }
            .animation(PVMotion.standard, value: heroIndex)
            .accessibilityLabel(String(localized: "Page \(heroIndex + 1) of \(memory.assets.count)"))
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PVSpacing.s8) {
                if let location = MemoryCardPresentation.locationLabel(for: memory) {
                    MemoryChip(symbol: "mappin.and.ellipse", text: location)
                }
                if let camera = heroCameraLabel {
                    MemoryChip(symbol: "camera", text: camera)
                }
                peopleChip
                if let tags = MemoryMomentPresentation.tagsLabel(for: memory) {
                    MemoryChip(symbol: "tag", text: tags)
                }
                if memory.isSaved {
                    MemoryChip(symbol: "heart.fill", text: String(localized: "Saved"))
                }
            }
            .padding(.horizontal, PVSpacing.s16)
        }
    }

    @ViewBuilder
    private var peopleChip: some View {
        let people = MemoryMomentPresentation.people(for: memory)
        if !people.isEmpty {
            HStack(spacing: -6) {
                ForEach(Array(people.prefix(4)), id: \.id) { person in
                    AuthenticatedAsyncImage(
                        url: ImmichAssetURL.personThumbnail(personId: person.id, baseURL: baseURL),
                        token: token
                    )
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                }
                if people.count > 4 {
                    Text("+\(people.count - 4)")
                        .font(.pvCaption)
                        .foregroundStyle(.white)
                        .padding(.leading, PVSpacing.s8)
                }
            }
            .padding(.horizontal, PVSpacing.s8)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.black.opacity(0.6)), in: Capsule())
            .accessibilityLabel(MemoryMomentPresentation.peopleLabel(for: memory) ?? String(localized: "People"))
        }
    }

    // MARK: - Actions

    private func openViewer(at index: Int) {
        let items = memory.assets.map { AssetReactItem(from: $0) }
        guard !items.isEmpty else { return }
        let clamped = min(max(index, 0), items.count - 1)
        viewerItem = PhotoViewerItem(assets: items, index: clamped)
    }

    private func appear() {
        withAnimation(PVMotion.adaptive(.easeOut(duration: 0.4), reduceMotion: reduceMotion)) {
            appeared = true
        }
        isVideoActive = heroAsset?.type == "VIDEO"
        restartKenBurns()
    }

    /// Advances the hero pager to the next asset (wrapping), re-armed by the
    /// auto-advance ticker or a finished video.
    private func advance() {
        guard memory.assets.count > 1 else { return }
        let next = (heroIndex + 1) % memory.assets.count
        withAnimation(PVMotion.adaptive(.easeInOut(duration: 0.4), reduceMotion: reduceMotion)) {
            scrollPosition.scrollTo(id: memory.assets[next].id)
        }
    }

    /// The current hero video finished playing — resume the slideshow and
    /// advance immediately (Photos behavior).
    private func videoEnded() {
        isVideoActive = false
        advance()
    }

    /// Slow 10 s zoom-in per slide (Ken Burns), restarted on each page change
    /// so every slide runs its own zoom before the ticker advances.
    private func restartKenBurns() {
        guard !reduceMotion else { return }
        kenBurns = false
        withAnimation(.linear(duration: 10)) {
            kenBurns = true
        }
    }
}

/// Small glass capsule chip (icon + label) used over hero imagery. White glyphs
/// over Liquid Glass — the scrim behind guarantees contrast on bright photos.
struct MemoryChip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: PVSpacing.s4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.pvCaption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, PVSpacing.s8)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(.black.opacity(0.6)), in: Capsule())
    }
}
