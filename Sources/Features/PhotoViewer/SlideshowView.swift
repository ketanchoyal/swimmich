import SwiftUI

/// Fullscreen autoplay slideshow (Photos-style) — presented as an INTERNAL
/// overlay of the photo viewer (never a new presentation layer: cover-inside-
/// cover is a known teardown crash, memory 2026-08-05).
///
/// The ticking loop lives HERE (view-owned), not in the VM: a `.task(id:)`
/// loop re-arms whenever speed or play state changes and calls `vm.advance()`
/// only when `vm.isPlaying && !vm.isVideoActive`, so the VM stays a pure,
/// unit-testable state machine. Videos play inline via the existing
/// `VideoPlayerView`; the ticker suspends during playback and resumes when
/// the video ends.
struct SlideshowView: View {
    let vm: SlideshowViewModel
    let baseURL: URL
    let token: String?
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let asset = vm.currentAsset {
                Group {
                    if asset.isVideo {
                        VideoPlayerView(
                            asset: asset,
                            baseURL: baseURL,
                            token: token,
                            controlsVisible: false,
                            onPlaybackEnded: { vm.videoEnded() }
                        )
                    } else {
                        ZoomableImageView(
                            asset: asset,
                            baseURL: baseURL,
                            token: token,
                            onSingleTap: {}
                        )
                    }
                }
                .transition(.opacity)
                .id(asset.id)
                .animation(
                    PVMotion.adaptive(.easeInOut(duration: 0.4), reduceMotion: reduceMotion),
                    value: vm.currentIndex
                )
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomBar }
        .task(id: tickerKey) {
            guard vm.isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(vm.speed.rawValue))
                guard vm.isPlaying, !vm.isVideoActive else { continue }
                vm.advance()
            }
        }
        .onAppear { vm.slideChanged(); vm.start() }
        .onChange(of: vm.currentIndex) { _, _ in
            vm.slideChanged()
        }
    }

    /// Restarts the ticking loop whenever speed or play state changes.
    private var tickerKey: String { "\(vm.speed.rawValue)-\(vm.isPlaying)" }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            if let asset = vm.currentAsset {
                Text("\(vm.currentIndex + 1) of \(vm.count)")
                    .font(.pvCaption.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, PVSpacing.s12)
                    .padding(.vertical, PVSpacing.s4)
                    .glassEffect(.regular, in: Capsule())
                    .accessibilityLabel("Slide \(vm.currentIndex + 1) of \(vm.count): \(asset.isVideo ? "Video" : "Photo")")
            }

            Spacer()

            Button {
                vm.stop()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.pvHeadline)
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Slideshow")
        }
        .padding(.horizontal, PVSpacing.s16)
        .padding(.top, PVSpacing.s8)
    }

    private var bottomBar: some View {
        GlassEffectContainer {
            HStack(spacing: PVSpacing.s16) {
                Button {
                    vm.previous()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous")
                .disabled(vm.count < 2)

                Spacer()

                Button {
                    vm.togglePlayPause()
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.isPlaying ? "Pause" : "Play")

                Spacer()

                Button {
                    vm.next()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.pvHeadline)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next")
                .disabled(vm.count < 2)
            }
            .padding(.horizontal, PVSpacing.s16)
        }
        .overlay(alignment: .bottomTrailing) {
            Menu {
                ForEach(SlideshowViewModel.SlideshowSpeed.allCases) { speed in
                    Button {
                        vm.speed = speed
                    } label: {
                        if speed == vm.speed {
                            Label(speed.label, systemImage: "checkmark")
                        } else {
                            Text(speed.label)
                        }
                    }
                }
            } label: {
                Text(vm.speed.label)
                    .font(.pvCaption.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, PVSpacing.s12)
                    .padding(.vertical, PVSpacing.s4)
                    .glassEffect(.regular, in: Capsule())
            }
            .accessibilityLabel("Slideshow Speed")
            .padding(.trailing, PVSpacing.s16)
            .padding(.bottom, PVSpacing.s8)
        }
        .padding(.bottom, PVSpacing.s8)
    }
}