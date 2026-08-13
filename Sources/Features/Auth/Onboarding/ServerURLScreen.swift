import SwiftUI

/// Step 2 — Connexion au serveur. Input + live validation, one screen.
///
/// No `Form`. The field lives in a card-styled capsule with `@FocusState`
/// auto-focus on appear and `.submitLabel(.continue)` so the keyboard's return
/// key matches the primary action. Connectivity is validated in place — the
/// status section under the field reflects `auth.serverStatus` (checking →
/// reachable info card → unreachable error with retry) so the user never leaves
/// this screen to learn the result. On `.reachable` the CTA becomes
/// "Continuer", pushing the sign-in step. The CTA is pinned to the bottom over
/// a material bar — `.safeAreaInset` rides above the keyboard on iOS 17.
struct ServerURLScreen: View {
    @Environment(AuthViewModel.self) private var auth
    let `continue`: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var auth = auth

        ScrollView {
            VStack(spacing: PVSpacing.s24) {
                header

                VStack(alignment: .leading, spacing: PVSpacing.s8) {
                    Text("ADRESSE DU SERVEUR")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                        .tracking(1)

                    PVInputGroup {
                        TextField("https://photos.example.com", text: $auth.serverURLString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.continue)
                            .focused($isFocused)
                            .onSubmit(primaryAction)
                            .font(.pvBody)
                            .pvFieldSurface()
                    }

                    statusSection
                        .transition(.opacity)
                }

                // TODO: $PHASE_QR — scan a server QR code (AVFoundation/VisionKit)
                // and pre-fill `auth.serverURLString` from the decoded payload.
                // TODO: $PHASE_CERT — self-signed certificate validation. Today any
                // HTTPS server is accepted (NSAllowsArbitraryLoads in Info.plist);
                // a proper trust-evaluation + pinning flow is deferred.

                Spacer(minLength: PVSpacing.s48)
            }
            .padding(PVSpacing.s24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("URL du serveur")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
        .onChange(of: auth.serverURLString) { _, _ in
            auth.serverStatus = .idle
        }
        .animation(PVMotion.gentle, value: auth.serverStatus)
        .alert("Trust this server?", isPresented: Binding(
            get: { auth.pendingUntrustedHost != nil },
            set: { if !$0 { auth.pendingUntrustedHost = nil } }
        )) {
            Button("Trust", role: .destructive) {
                Task { await auth.trustPendingServer() }
            }
            Button("Cancel", role: .cancel) { auth.pendingUntrustedHost = nil }
        } message: {
            Text("The certificate of \(auth.pendingUntrustedHost ?? "this server") cannot be verified. Trust it anyway?")
        }
        .onboardingBottomBar {
            Button(action: primaryAction) {
                switch auth.serverStatus {
                case .checking:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 22)
                case .reachable:
                    Text("Continuer")
                case .unreachable:
                    Text("Réessayer")
                case .idle:
                    Text("Vérifier la connexion")
                }
            }
            .buttonStyle(PVPrimaryButtonStyle())
            .disabled(auth.serverURLString.isEmpty || auth.isLoading || auth.serverStatus == .checking)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch auth.serverStatus {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: PVSpacing.s8) {
                ProgressView()
                    .controlSize(.small)
                Text("Vérification du serveur…")
                    .font(.pvSubhead)
                    .foregroundStyle(Color.textSecondaryPV)
            }
            .padding(PVSpacing.s8)

        case .reachable(let version):
            VStack(alignment: .leading, spacing: PVSpacing.s12) {
                Label("Serveur connecté", systemImage: "checkmark.circle.fill")
                    .font(.pvBodyLarge)
                    .foregroundStyle(Color.immichSuccess)

                ServerInfoCard(
                    version: version.map { "\($0.major).\($0.minor).\($0.patch)" },
                    externalDomain: auth.serverConfig?.externalDomain,
                    isInitialized: auth.serverConfig?.isInitialized
                )
            }

        case .unreachable:
            InlineErrorBadge(
                message: auth.errorMessage ?? "Serveur injoignable",
                retry: { connect() }
            )
        }
    }

    private var header: some View {
        VStack(spacing: PVSpacing.s8) {
            PVHeaderBadge(icon: "link.badge.plus")
            Text("Connectez votre serveur")
                .font(.pvH2)
                .multilineTextAlignment(.center)
            Text("Indiquez l'URL de votre instance Immich.")
                .font(.pvSubhead)
                .foregroundStyle(Color.textSecondaryPV)
                .multilineTextAlignment(.center)
        }
        .padding(.top, PVSpacing.s8)
    }

    private func primaryAction() {
        switch auth.serverStatus {
        case .reachable: `continue`()
        default: connect()
        }
    }

    private func connect() {
        Task {
            await auth.connectServer()
        }
    }
}

/// Server info display card (no Form `Section`).
private struct ServerInfoCard: View {
    let version: String?
    let externalDomain: String?
    let isInitialized: Bool?

    var body: some View {
        VStack(spacing: PVSpacing.s0) {
            if let version {
                InfoRow(label: "Version", value: version)
                Divider()
            }
            if let externalDomain {
                InfoRow(label: "Domaine", value: externalDomain)
                Divider()
            }
            if let isInitialized {
                InfoRow(label: "Initialisé", value: isInitialized ? "Oui" : "Non")
            }
        }
        .padding(.horizontal, PVSpacing.s16)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.pvSubhead)
                .foregroundStyle(Color.textSecondaryPV)
            Spacer()
            Text(value)
                .font(.pvBody)
                .foregroundStyle(Color.textPrimaryPV)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, PVSpacing.s12)
    }
}
