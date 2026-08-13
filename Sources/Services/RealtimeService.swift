import Foundation
import SocketIO

extension Notification.Name {
    /// Broadcast whenever server events indicate library content changed
    /// (asset create/update/delete/trash/restore/stack). VMs observe this to
    /// refresh their lists without a manual pull.
    static let immichAssetsChanged = Notification.Name("immichAssetsChanged")
}

/// Socket.IO-backed realtime service (gap #10). Connects to the Immich
/// server's `/api/socket.io` gateway, authenticates with the bearer token via
/// the websocket handshake headers, and coalesces asset/person events into a
/// debounced `.immichAssetsChanged` notification.
@MainActor
final class RealtimeService {
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var debounceTask: Task<Void, Never>?

    /// Debounce window for coalescing bursts of events (e.g. a bulk trash).
    private let debounceInterval: Duration = .milliseconds(600)

    var isConnected: Bool { socket?.status == .connected }

    nonisolated init() {}

    func connect(baseURL: URL, token: String) {
        disconnect()
        let manager = SocketManager(
            socketURL: baseURL,
            config: [
                .path("/api/socket.io"),
                .forceWebsockets(true),
                .extraHeaders(["Authorization": "Bearer \(token)"]),
                .reconnects(true),
                .compress,
            ]
        )
        let socket = manager.defaultSocket

        socket.on(clientEvent: .connect) { _, _ in
            // Connected; nothing to surface to the user.
        }
        socket.on(clientEvent: .error) { _, _ in
            // Errors are non-fatal — the HTTP layer still works without the socket.
        }

        let assetEvents = [
            "on_upload_success", "on_asset_delete", "on_asset_trash",
            "on_asset_update", "on_asset_hidden", "on_asset_restore",
            "on_asset_stack_update", "on_person_thumbnail",
        ]
        for event in assetEvents {
            socket.on(event) { [weak self] _, _ in
                self?.scheduleBroadcast()
            }
        }

        socket.connect()
        self.manager = manager
        self.socket = socket
    }

    func disconnect() {
        debounceTask?.cancel()
        debounceTask = nil
        socket?.disconnect()
        socket = nil
        manager = nil
    }

    private func scheduleBroadcast() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .milliseconds(600))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .immichAssetsChanged, object: nil)
        }
    }
}
