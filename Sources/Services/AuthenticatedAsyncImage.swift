import SwiftUI

/// Loads images from authenticated Immich endpoints (Bearer token in header).
/// Plain AsyncImage doesn't allow custom request headers, so we use a small
/// URLSession-backed loader.
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
            } else if didFail {
                Rectangle().fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            } else {
                Rectangle().fill(Color.gray.opacity(0.1))
                    .overlay(ProgressView())
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard let url else { return }
        image = nil
        didFail = false
        do {
            var request = URLRequest(url: url)
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                didFail = true
                return
            }
            guard let img = UIImage(data: data) else { didFail = true; return }
            await MainActor.run { self.image = img }
        } catch {
            didFail = true
        }
    }
}
