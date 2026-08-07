import Foundation

/// Errors surfaced by the Immich client layer.
enum APIError: Error, LocalizedError, Equatable {
    case unauthorized
    case network(URLError)
    case serverError(Int, String?)
    case decoding(String)
    case invalidURL
    case multipartEncoding(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Unauthorized (401). Please sign in again."
        case .network(let e): return "Network error: \(e.localizedDescription)"
        case .serverError(let code, let msg): return "Server error \(code): \(msg ?? "no detail")"
        case .decoding(let m): return "Decoding failed: \(m)"
        case .invalidURL: return "Invalid server URL."
        case .multipartEncoding(let m): return "Multipart encoding failed: \(m)"
        case .http(let code): return "HTTP \(code)"
        }
    }

    /// `true` when this error represents cooperative `Task` cancellation (a
    /// `URLError(.cancelled)` surfacing from `URLSession.data(for:)` when the
    /// enclosing Task was cancelled). Cancellation is a normal outcome of
    /// debounced live search / pagination and must NOT be surfaced to the user.
    var isCancellation: Bool {
        switch self {
        case .network(let e): return e.code == .cancelled
        default: return false
        }
    }

    /// Maps a raw URL response error to the APIError domain.
    static func from(_ error: Error) -> APIError {
        if let api = error as? APIError { return api }
        if let url = error as? URLError {
            // URLSession surfaces 401 via status code path, not URLError, but defensive.
            return .network(url)
        }
        // Cooperative `Task` cancellation (`error` is `CancellationError`) —
        // round-trip through `.network(.cancelled)` so callers can detect it
        // via `isCancellation` instead of mislabeling it a decoding failure.
        if error is CancellationError {
            return .network(URLError(.cancelled))
        }
        return .decoding(String(describing: error))
    }
}
