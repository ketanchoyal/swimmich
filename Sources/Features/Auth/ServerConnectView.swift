import SwiftUI

/// First-run server discovery screen. Pings /api/server/ping.
struct ServerConnectView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var didAttempt = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server URL") {
                    TextField("https://photos.example.com", text: Bindable(auth).serverURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                if case .reachable(let version) = auth.serverStatus {
                    Section("Server") {
                        if let v = version {
                            LabeledContent("Version", value: "\(v.major).\(v.minor).\(v.patch)")
                        }
                        if let cfg = auth.serverConfig {
                            LabeledContent("External", value: cfg.externalDomain)
                            LabeledContent("Initialized", value: cfg.isInitialized ? "Yes" : "No")
                        }
                    }
                }

                if case .unreachable = auth.serverStatus {
                    Section {
                        Label("Could not reach server.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Immich")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Next") {
                        Task { await auth.connectServer() }
                    }
                    .disabled(auth.serverURLString.isEmpty || auth.isLoading)
                }
            }
            NavigationLink {
                LoginView()
            } label: {
                Text("Continue to login")
            }
            .disabled(isLoginDisabled)
            .padding()
        }
    }

    private var isLoginDisabled: Bool {
        if case .reachable = auth.serverStatus { return false }
        return true
    }
}
