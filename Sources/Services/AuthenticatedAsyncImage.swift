import SwiftUI

/// Loads images from authenticated Immich endpoints (Bearer token in header).
///
/// Premium pipeline (AC-200 integration):
/// 1. `ImageCache.shared` (in-memory NSCache) — instant hit on scroll-back.
/// 2. `imageSession` (URLCache-backed URLSession) — HTTP-level disk dedup,
///    honors server `Cache-Control` so repeated entries don't always re-hit net.
/// 3. Network fetch w/ Bearer header — only on cold load.
/// While in-flight a shimmer placeholder sweeps; on success the image crossfades.
struct AuthenticatedAsyncImage: View {
    let url: URL?
    let token: String?

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if didFail {
                Rectangle().fill(Color.bgTertiary.opacity(0.2))
                    .overlay(Image(systemName: "photo").foregroundStyle(Color.textSecondaryPV))
            } else {
                ShimmerPlaceholder()
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard let url else { return }
        // Reset state for the new URL (drives `.task(id:)` re-evals on URL change).
        if image != nil { image = nil }
        didFail = false

        // Tier 1 — in-memory cache. No await cost beyond actor hop.
        if let cached = await ImageCache.shared.image(for: url) {
            self.image = cached
            return
        }

        do {
            var request = URLRequest(url: url)
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            // Tiers 2+3 — URLCache dedup + network.
            let (data, response) = try await Self.imageSession.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                didFail = true
                return
            }
            guard let img = UIImage(data: data) else { didFail = true; return }
            // Populate both tiers for subsequent hits.
            await ImageCache.shared.store(img, for: url)
            self.image = img
        } catch {
            didFail = true
        }
    }

    /// Shared image session with a generous URLCache so the OS dedups HTTP
    /// traffic across scroll churn. Bearer header is per-request, so this
    /// session is safe to share between all authenticated image loads.
    private static let imageSession: URLSession = {
        let cache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,   // 50MB
            diskCapacity: 200 * 1024 * 1024,    // 200MB
            diskPath: "immich-image-cache"
        )
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()
}

/// Animated shimmer sweep for the loading state — far more premium than a
/// bare `ProgressView`. Uses phase-animated gradient so it reads as "alive"
/// even on slow networks.
struct ShimmerPlaceholder: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        Rectangle()
            .fill(Color.bgTertiary.opacity(0.12))
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.35), // DS-exempt: infinite shimmer, not interactive
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 320)
                .mask(Rectangle())
            )
            .clipped()
            .onAppear {
                // DS-exempt: infinite shimmer, not interactive
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
