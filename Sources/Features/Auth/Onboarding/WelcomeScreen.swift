import SwiftUI

/// Step 1 — Bienvenue. Single-screen welcome, Apple "What's New" style.
///
/// One screen, one message: a `PVHeaderBadge` hero in a rounded wash, a short
/// title + tagline, then the three value props as static rows (icon tile +
/// headline + detail). No paging, no skip, no looping motion — the single CTA
/// is pinned to the bottom over a material bar so it never scrolls out of
/// reach.
struct WelcomeScreen: View {
    let `continue`: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: PVSpacing.s32) {
                header

                VStack(alignment: .leading, spacing: PVSpacing.s16) {
                    ForEach(WelcomeBullet.all) { bullet in
                        WelcomeBulletRow(bullet: bullet)
                    }
                }
            }
            .padding(PVSpacing.s24)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onboardingBottomBar {
            Button("Commencer", action: `continue`)
                .buttonStyle(PVPrimaryButtonStyle())
        }
    }

    private var header: some View {
        VStack(spacing: PVSpacing.s8) {
            PVHeaderBadge(icon: "camera.aperture")
            Text("Bienvenue sur Immich")
                .font(.pvH2)
                .multilineTextAlignment(.center)
            Text("Configurez votre serveur et connectez-vous.")
                .font(.pvSubhead)
                .foregroundStyle(Color.textSecondaryPV)
                .multilineTextAlignment(.center)
        }
        .padding(.top, PVSpacing.s8)
    }
}

// MARK: - Bullets

private struct WelcomeBullet: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String

    static let all: [WelcomeBullet] = [
        .init(
            symbol: "photo.stack",
            title: "Votre photothèque",
            detail: "auto-hébergée, privée et durable."
        ),
        .init(
            symbol: "lock.shield.fill",
            title: "Vos photos, votre serveur",
            detail: "Aucun cloud tiers. Vos souvenirs restent chez vous."
        ),
        .init(
            symbol: "sparkles",
            title: "Recherche & souvenirs",
            detail: "Recherche intelligente, albums partagés, timelines."
        )
    ]
}

/// Static value-prop row: tinted icon tile + headline + detail line.
private struct WelcomeBulletRow: View {
    let bullet: WelcomeBullet

    var body: some View {
        HStack(alignment: .top, spacing: PVSpacing.s16) {
            Image(systemName: bullet.symbol)
                .font(.pvH5)
                .foregroundStyle(Color.immichPrimary)
                .frame(width: 48, height: 48)
                .background(Color.immichPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: PVRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: PVSpacing.s4) {
                Text(bullet.title)
                    .font(.pvHeadline)
                    .foregroundStyle(Color.textPrimaryPV)
                Text(bullet.detail)
                    .font(.pvBody)
                    .foregroundStyle(Color.textSecondaryPV)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
