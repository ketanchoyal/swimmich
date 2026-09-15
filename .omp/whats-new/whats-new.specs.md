# Task: whats-new

> **Audit 2026-09-15 — écart G23** : le client Flutter a un écran « Quoi de neuf » — `WhatsNewRoute` (`mobile/lib/routing/router.dart:134`,
> `AutoRoute(page: WhatsNewRoute.page, guards: [_duplicateGuard])`) atteint depuis `mobile/lib/pages/common/settings.page.dart:116-118`
> (`SettingListTile(title: context.t.whats_new, subtitle: context.t.whats_new_settings_subtitle)`) et `:152-154` —
> plus un écran de licences (`LicenseRegistry` alimenté par `mobile/lib/utils/licenses.dart`), tous deux absents côté iOS :
> `grep -rn "WhatsNew" Sources/` ne renvoie rien, aucune section « About » n'existe dans `ProfileView`, et `Resources/` ne contient aucun fichier d'attribution tiers.

**Objectif** : au premier lancement qui suit la publication d'une nouvelle série de nouveautés, l'app présente une feuille « What's New »
listant les nouveautés embarquées (capture ou icône, titre, corps) et n'y revient plus une fois la série vue ; depuis le hub « Me »,
l'utilisateur ouvre une section « About » qui donne la version de l'app, rouvre « What's New » à la demande, et lit les licences
des dépendances tierces réellement embarquées.

**Hors périmètre** :
- Les **captures d'écran** des cartes : l'upstream embarque cinq webp (`mobile/assets/feature_message/*.webp`). Aucun équivalent n'existe
  dans `Resources/Assets.xcassets`, et une capture se produit avec le simulateur, pas en écrivant une fiche. L'écran livre le repli que
  l'upstream prévoit lui-même (`feature_message_placeholder.widget.dart`) : une tuile teintée portant le SF Symbol de la nouveauté.
- Le **lien vers le dépôt GitHub** (`profile_drawer_github`, `mobile/lib/widgets/common/app_bar_dialog/app_bar_dialog.dart:205-215`).
- Le **texte de licence du produit Immich** (`/server/license`, `/users/me/license`) : c'est la licence commerciale, pas l'attribution open-source.
- La **rédaction d'une nouvelle série** de nouveautés : la fiche livre le catalogue et le mécanisme de comparaison, pas le contenu éditorial.
- Aucun token de DesignSystem ni composant de carte réutilisable neuf : `PVStatusBadge` et les tokens existants suffisent.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@e55ac299`, le 2026-09-15) :

- **Upstream — la source des notes est l'app, pas le serveur** (le point que la fiche tranche) :
  - `mobile/lib/domain/models/feature_message.model.dart` : `enum FeatureHighlight` (6 cas, chacun porteur d'un
    `image: 'assets/feature_message/ocr.webp'` de ce style) avec `isVisibleOnCurrentPlatform`, `openInImmich` étant déclaré
    `platform: [.android]` — donc **cinq** cas visibles sur iOS.
  - Le même fichier définit `const featureMessageRelease = SemVer(major: 3, minor: 0, patch: 0)`, commenté ainsi :
    « The release this batch of highlights was authored for. Content-defined: bump it only when publishing a new batch,
    never from the running app version ». La série n'est donc **pas** indexée sur la version de l'app.
  - `mobile/lib/domain/services/feature_message.service.dart:10-15` : `shouldShow()` =
    `visibleFeatureMessageHighlights.isNotEmpty && featureMessageRelease > seenRelease`, où `seenRelease` est le seul état persistant ;
    `markSeen()` écrit `SettingsKey.featureMessageSeenRelease`.
  - `mobile/lib/domain/models/config/feature_message_config.dart` : l'objet de configuration correspondant ne porte **qu'un** champ,
    `SemVer seenRelease`. Rien d'autre n'est téléchargé.
  - **Aucun endpoint** : `grep -c featureMessage /tmp/immich-openapi-main.json` → `0`. Les seules routes du contrat publié contenant
    « license » sont `/server/license` et `/users/me/license` (`LicenseKeyDto`, `LicenseResponseDto`, `UserLicense`).
    `mobile/lib/providers/feature_message.provider.dart:5` n'est qu'un provider local au-dessus du `SettingsRepository`.
  - Déclencheurs : `mobile/lib/presentation/pages/dev/main_timeline.page.dart:26-35` (après le premier frame de la timeline :
    `shouldShow()` → `markSeen()` → `showFeatureMessageDialog`) ; `mobile/lib/widgets/forms/login/login_form.dart:279,383`
    (`markSeen()` au login, pour qu'un compte fraîchement ajouté ne reçoive pas la série) ; `mobile/lib/utils/migration.dart:38`.
  - Deux présentations du **même** contenu : la page `mobile/lib/presentation/pages/feature_message/whats_new.page.dart`
    (`Scaffold` + `ListView.separated` de `_HighlightCard`) et la feuille paginée `feature_message_dialog.widget.dart`.
  - Mise en page de `_HighlightCard` : bloc image 256 pt, rayon 18, bordure `outlineVariant` à 0,5 ; titre `titleMedium` w600 ;
    corps `bodyMedium` en `onSurfaceVariant` ; marges horizontales 16 ; écart entre cartes 24.
  - `app_bar_dialog.dart:217-225` appelle `showLicensePage(applicationVersion: packageInfo.version)`, `applicationIcon` étant le logo Immich.
  - Licences tierces déclarées côté Flutter : `mobile/lib/utils/licenses.dart` = `const nonPubLicenses` (deux entrées, `aves` et `photo_view`),
    enregistrées dans le `LicenseRegistry` au démarrage (`mobile/lib/main.dart:115-117`).
- **iOS — l'état actuel qui rend la fiche nécessaire** :
  - Le hub « Me » : `Sources/Features/Profile/ProfileView.swift:24-163` — un `NavigationStack` contenant un `Form`, avec les sections
    Account, Servers, Server, storage, General, Management, Administration, Security, Log Out. **Aucune section About**.
  - La mécanique de feuille : `Sources/RootView.swift:82` (`private struct AuthenticatedRoot`), `:114`
    (`@State private var showProfile = false`), `:233-235` (`.sheet(isPresented: $showProfile)` présentant `ProfileView`).
    Les feuilles vivent dans `AuthenticatedRoot`, le seul présentateur stable — c'est le patron à suivre.
  - Le chemin de session : `Sources/Features/Auth/AuthViewModel.swift:330-345`
    (`private func applySession(token:email:name:userId:isAdmin:)`, appelé par le login mot de passe et par OAuth) écrit déjà dans
    `private let defaults: UserDefaults` (`:78`). `restoreSession()` (`:119-138`) ne passe **pas** par `applySession` : y écrire
    n'étouffe donc pas l'écran au relaunch qui suit une mise à jour.
  - Ressources embarquées : `Resources/` = `Assets.xcassets`, `Localizable.xcstrings`, `TeslaCar.usdz`, `Info.plist`, deux fichiers
    d'entitlements — rien pour les licences.
  - Une seule dépendance tierce : `SocketIO` (`project.yml:6-9`, `from: 16.1.0`, produit `SocketIO` en `project.yml:74-76`).
    XcodeGen embarque les ressources par énumération explicite (`project.yml:24-34`, un `- path:` par ressource), donc un dossier
    neuf n'est copié qu'après un EDIT de `project.yml`.
  - Précédents de patron : ViewModel `@MainActor @Observable` construit par `DependencyContainer`
    (`Sources/DependencyContainer.swift:81-230`) ; écran poussé **sans** `NavigationStack` parce que `ProfileView` en porte un
    (`LanguageSettingsView`, mémoire `3bfec9fe-f46d-4395-83de-d4ad3fecdedd`), et `ProfileView` déclarant le sien quand elle est en feuille.
- **Ce qui rend la fiche nécessaire** : `grep -rn "WhatsNew\|whatsNew\|License" Sources/` ne renvoie aucun résultat (vérifié le 2026-09-15) ;
  `Sources/Features/WhatsNew/` et `Sources/Features/About/` n'existent pas ; `Resources/Localizable.xcstrings` ne contient aucune clé
  « What's New », « About » ni « Licenses » (extraction JSON des clés contenant `bout`/`icens`/`What` → seulement deux corps de texte sans rapport).

**Approche retenue** : A — un catalogue **embarqué** (`FeatureHighlightCatalog` + release de contenu `"3.0.0"`), un `WhatsNewStore`
au-dessus d'`UserDefaults` qui ne persiste que la release vue, un `WhatsNewViewModel` mince, une vue de cartes unique servant à la fois
la feuille automatique et l'ouverture à la demande depuis une section About, et un écran de licences qui **charge les fichiers LICENSE
réellement résolus** au lieu d'en recopier le texte.
- **B (rejetée)** : servir les nouveautés depuis le serveur (endpoint neuf ou `/api/system-config`) → mesurablement impossible :
  `featureMessage` apparaît **0 fois** dans `/tmp/immich-openapi-main.json` et le modèle de config local ne porte que `seenRelease`.
  L'upstream tient lui-même la série en `const` ; un écran dépendant du réseau afficherait un vide hors-ligne là où toutes les autres
  fiches de parité lisent un état local.
- **C (rejetée)** : comparer `MARKETING_VERSION` (`project.yml:15`) au lieu d'une release de contenu → re-présenterait la feuille à chaque
  build de correctif et à chaque build local, ce que le commentaire upstream interdit explicitement (« never from the running app version »).

## Étapes

1. **Le catalogue embarqué** — NEW `Sources/Features/WhatsNew/FeatureHighlight.swift` : `struct FeatureHighlight: Identifiable, Hashable, Sendable`
   avec `let id: String`, `let title: String`, `let body: String`, `let systemImage: String` (repli visuel), `let imageName: String?`
   (nil tant qu'aucun asset n'est livré). `enum FeatureHighlightCatalog` : `static let release = "3.0.0"` (constante de contenu, commentée
   en citant l'upstream), `static let all: [FeatureHighlight]` — les **cinq** entrées visibles sur iOS (`shareQuality`, `slideshow`,
   `recentlyAdded`, `ocr`, `uploadToAlbum` ; `openInImmich` est Android-only et n'est pas déclaré) — et
   `static func isNewer(_ candidate: String, than seen: String) -> Bool`, qui découpe sur `.`, compare composant par composant avec
   `Int(_:) ?? 0` et renvoie `false` à égalité. Comparaison numérique volontaire : `"3.10.0" > "3.9.0"`, ce qu'une comparaison
   lexicographique rate dès la dixième mineure.
2. **L'état vu** — NEW `Sources/Features/WhatsNew/WhatsNewStore.swift` : `struct WhatsNewStore` avec
   `static let seenReleaseKey = "whatsNewSeenRelease"`, `let defaults: UserDefaults`,
   `var seenRelease: String { defaults.string(forKey: Self.seenReleaseKey) ?? "0.0.0" }`,
   `var shouldShow: Bool { !FeatureHighlightCatalog.all.isEmpty && FeatureHighlightCatalog.isNewer(FeatureHighlightCatalog.release, than: seenRelease) }`,
   `func markSeen() { defaults.set(FeatureHighlightCatalog.release, forKey: Self.seenReleaseKey) }`. L'injection du `UserDefaults` suit
   `BackupSettingsStore(suiteName:)` : suite jetable en test, `.standard` en production.
3. **Le ViewModel** — NEW `Sources/Features/WhatsNew/WhatsNewViewModel.swift` : `@MainActor @Observable final class WhatsNewViewModel`
   avec `private let store: WhatsNewStore`, `init(store:)`, `let highlights = FeatureHighlightCatalog.all`, `let release = FeatureHighlightCatalog.release`,
   `var seenRelease: String { store.seenRelease }`, `func shouldPresentAutomatically() -> Bool { store.shouldShow }`,
   `func markSeen() { store.markSeen() }`. Aucun état propre : « vue / pas vue » vit dans `UserDefaults`, pas dans la mémoire du view model,
   qui est recréé à chaque relance.
4. **L'écran** — NEW `Sources/Features/WhatsNew/WhatsNewView.swift` : `struct WhatsNewView: View` prenant `@Bindable var vm: WhatsNewViewModel`.
   Corps : `ScrollView { LazyVStack(spacing: PVSpacing.s24) { ForEach(vm.highlights) { card(for: $0) } } }` avec
   `.padding(.horizontal, PVSpacing.s16)` et `.padding(.vertical, PVSpacing.s16)`, sur `.background(Color.bgPrimary)` ;
   `.navigationTitle("What's New")`, `.navigationBarTitleDisplayMode(.inline)`. La carte (`private func card(for:)`) traduit `_HighlightCard` :
   tuile de 256 pt de haut, rayon 18, bordure à 0,5, remplie par `Image(highlight.imageName)` si l'asset existe et par le repli sinon
   (`Image(systemName: highlight.systemImage)` en `.font(.system(size: 44))` sur `Color.bgSecondary`) ; sous la tuile, titre `.headline`
   puis corps `.subheadline` en `Color.textSecondary`. **Aucun `NavigationStack`** : `ProfileView` en porte un quand la vue est poussée,
   et la feuille l'enveloppe (étape 7), comme elle enveloppe déjà `ProfileView`.
5. **La sortie de la feuille** — EDIT `Sources/Features/WhatsNew/WhatsNewView.swift` : ajouter `var onDone: (() -> Void)?` et, quand elle est
   non nulle, un `ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone?() } }`. Poussée depuis About, la vue n'a pas de
   bouton ; présentée en feuille, elle en a un. C'est la seule différence entre les deux usages : aucune carte dupliquée.
6. **L'injection** — EDIT `Sources/DependencyContainer.swift` : ajouter `let whatsNewStore = WhatsNewStore(defaults: .standard)` aux côtés
   des autres stockages du conteneur, puis `func makeWhatsNewViewModel() -> WhatsNewViewModel { WhatsNewViewModel(store: whatsNewStore) }`
   après `makeLanguageSettingsViewModel()` (`:223`). Le conteneur fabrique le store **une fois** : la release vue est un état de processus.
7. **La présentation automatique** — EDIT `Sources/RootView.swift` : dans `AuthenticatedRoot`, déclarer `@State private var whatsNew: WhatsNewViewModel`
   (à côté de `@State private var language`, `:135`) et `@State private var showWhatsNew = false`, initialiser le view model dans `init(container:)`
   par `_whatsNew = State(initialValue: container.makeWhatsNewViewModel())`, puis après la feuille du profil (`:233-235`) :
   `.sheet(isPresented: $showWhatsNew, onDismiss: { whatsNew.markSeen() }) { NavigationStack { WhatsNewView(vm: whatsNew, onDone: { showWhatsNew = false }) } }`.
   Déclenchement : `.task(id: auth.userId) { showWhatsNew = whatsNew.shouldPresentAutomatically() }` sur le même arbre — `auth.userId` en
   identifiant refait l'évaluation au changement de compte, et `markSeen()` en `onDismiss` couvre aussi le balayage vers le bas.
8. **Le marquage au login** — EDIT `Sources/Features/Auth/AuthViewModel.swift` : dans `applySession` (`:330-345`), après
   `defaults.set(isAdmin, forKey: Self.isAdminDefaultsKey)` (`:340`), écrire
   `defaults.set(FeatureHighlightCatalog.release, forKey: WhatsNewStore.seenReleaseKey)`. Miroir direct de `login_form.dart:279,383` :
   un compte fraîchement ajouté ne reçoit pas une série rédigée avant lui.
9. **Les licences réellement résolues** — NEW `Sources/Features/About/ThirdPartyLicense.swift` :
   `struct ThirdPartyLicense: Identifiable, Hashable { let id: String; let name: String; let resourceName: String }`,
   `static let all: [ThirdPartyLicense]` (au minimum `socket.io-client-swift`, seule dépendance SPM de `project.yml:6-9`), et
   `func licenseText(for:) throws -> String` lisant `Bundle.main.url(forResource: license.resourceName, withExtension: "txt")`.
   Aucun texte de licence n'est recopié à la main dans le Swift : le fichier doit être la copie exacte livrée par le paquet.
10. **Les fichiers d'attribution** — NEW `Resources/Acknowledgements/socket.io-client-swift.txt` : copie du `LICENSE` du checkout résolu
    (`~/Library/Developer/Xcode/DerivedData/ImmichSwiftUI-*/SourcePackages/checkouts/socket.io-client-swift/LICENSE`, plus un fichier par
    dépendance transitive listée au même endroit). EDIT `project.yml` : ajouter `- path: Resources/Acknowledgements` à l'énumération des
    ressources de la cible app (`:24-34`), sans quoi le dossier n'est pas copié et l'étape 9 échoue.
11. **L'écran des licences** — NEW `Sources/Features/About/LicensesView.swift` : `struct LicensesView: View` sans paramètre, avec
    `@State private var expanded: Set<String> = []` et `private let licenses = ThirdPartyLicense.all`. `List` de `Section` par licence,
    chaque section portant un `DisclosureGroup(isExpanded:)` dont le contenu est `Text(try licenseText(for: license))` en
    `.font(.footnote.monospaced())` et `.textSelection(.enabled)`, le label étant `license.name`. Titre `"Licenses"` en `.inline`.
    Échec de chargement → ligne `"License text unavailable"` identifiée `licenseMissingRow` : une panne de packaging doit se voir.
12. **L'écran About** — NEW `Sources/Features/About/AboutView.swift` : `struct AboutView: View` prenant `@Bindable var whatsNew: WhatsNewViewModel`.
    `List` à trois lignes — `LabeledContent("Version", value:)` lisant `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` et
    `CFBundleVersion` (`MARKETING_VERSION` = `0.1.0`, `project.yml:15`) ; `NavigationLink { WhatsNewView(vm: whatsNew) } label: { Label("What's New", systemImage: "sparkles") }`
    identifié `aboutWhatsNewRow` ; `NavigationLink { LicensesView() } label: { Label("Licenses", systemImage: "doc.text") }` identifié
    `aboutLicensesRow`. Titre `"About"`, `.inline`, pas de `NavigationStack` (poussé depuis `ProfileView`).
13. **Le point d'entrée** — EDIT `Sources/Features/Profile/ProfileView.swift` : ajouter `@State var whatsNew: WhatsNewViewModel` aux propriétés
    stockées (après `@State var language`, `:22`), puis insérer **après** la section Administration et **avant** la section Security
    (le bloc About regarde l'app elle-même, pas le compte) :
    `Section { NavigationLink { AboutView(whatsNew: whatsNew) } label: { Label("About", systemImage: "info.circle") } .accessibilityIdentifier("aboutRow") } header: { Text("About") }`.
    EDIT `Sources/RootView.swift` : ajouter `whatsNew: whatsNew` à l'appel du constructeur `ProfileView` (`:234`).
14. **Les tests du ViewModel** — NEW `Tests/WhatsNewViewModelTests.swift` : suite `final class WhatsNewViewModelTests: XCTestCase`, chaque cas
    créant un `WhatsNewStore(defaults: UserDefaults(suiteName: "whats-new-\(UUID().uuidString)")!)` supprimé dans `tearDown`. Cas :
    `test_shouldShow_whenNothingSeenYet`, `test_shouldShow_isFalse_onceMarked` (relire le store, pas seulement le view model),
    `test_markSeen_writesTheCatalogRelease`, `test_isNewer_isNumericNotLexicographic` (`"3.10.0"` contre `"3.9.0"`),
    `test_isNewer_isFalse_forAnOlderOrEqualRelease`, `test_catalog_excludesTheAndroidOnlyHighlight` (aucun `id` `openInImmich`),
    `test_catalog_hasNoDuplicateIdentifiers`, `test_highlights_haveNonEmptyTitleAndBody`.
15. **Le test de packaging** — NEW `Tests/ThirdPartyLicenseTests.swift` :
    `test_everyDeclaredLicense_resolvesToANonEmptyBundledFile` parcourant `ThirdPartyLicense.all` et exigeant un texte non vide via
    `licenseText(for:)`, plus `test_socketIO_isDeclared`. C'est le seul test qui attrape la panne silencieuse réelle : un `Resources/`
    non régénéré dans `project.yml`.
16. **Les chaînes** — aucune écriture manuelle dans `Resources/Localizable.xcstrings` (clé = chaîne anglaise, extraction au build).
    Chaînes neuves des étapes 1, 4, 5, 11 et 12 : `What's New`, `About`, `Licenses`, `Done`, `Version`, `License text unavailable`,
    plus les cinq paires titre/corps du catalogue.
17. `xcodegen generate` (les fichiers des étapes 1–4 et 9–12 et le dossier `Resources/Acknowledgements` ne sont ni compilés ni copiés sans
    régénération, `project.yml` ayant été modifié à l'étape 10), puis la suite complète `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation

- **Les dépendances transitives à attribuer.** `socket.io-client-swift` traîne `Starscream` dans son propre `Package.swift`. La liste à
  copier est celle des checkouts résolus, pas celle du manifeste. Trancher par :
  `ls ~/Library/Developer/Xcode/DerivedData/ImmichSwiftUI-*/SourcePackages/checkouts/*/LICENSE*`.
- **Le chemin de copie du dossier de ressources.** XcodeGen copie `- path: Resources/Acknowledgements` en groupe de ressources ou en
  dossier-référence selon la version, et la structure dans le bundle change le nom de ressource attendu par
  `Bundle.main.url(forResource:withExtension:)`. Trancher par :
  `find ~/Library/Developer/Xcode/DerivedData/ImmichSwiftUI-*/Build/Products -name "socket.io-client-swift.txt" -path "*ImmichSwiftUI.app*"`
  après un premier build — le test de l'étape 15 le confirmera de toute façon.
- **Le contenu des cinq cartes.** Les titres et corps iOS (share quality, slideshow, recently added, OCR, upload to album) décrivent des
  fonctions dont certaines ne sont pas livrées (`ocr` relève de la fiche `SpecOcrText`). Une carte annonçant une fonction absente serait un
  mensonge produit. Trancher par : `read Sources/Features/` puis, pour chaque entrée conservée, vérifier que l'écran correspondant existe ;
  retirer du catalogue toute nouveauté non livrée (un catalogue vide désactive la feuille via `shouldShow`).
- **La release de contenu à publier.** `"3.0.0"` reprend la valeur upstream (`feature_message.model.dart:39`) pour que la première
  présentation ait lieu dès l'installation de cette fiche. Si l'intégrateur préfère ne rien montrer avant une série réellement rédigée,
  la valeur de départ est recopiée dans la clé `whatsNewSeenRelease`. Trancher par :
  `grep -n "static let release" Sources/Features/WhatsNew/FeatureHighlight.swift` puis arbitrage de revue.
- **Le comportement de `.task(id: auth.userId)` quand `userId` est nil.** `AuthViewModel.userId` reste `String?` (`:52`) ; une session
  restaurée sans `userId` persistant verrait la tâche se ré-exécuter. Trancher par :
  `grep -n "userId" Sources/Features/Auth/AuthViewModel.swift | head`, puis vérifier que la feuille ne s'ouvre qu'une fois par session
  (`showWhatsNew` n'est jamais remis à `true` une fois `markSeen()` écrit).
- **L'icône de la ligne About.** `info.circle` est proposé pour rester distinct de `globe` (Language, `ProfileView.swift:38`) et
  `gearshape.2` (Administration, `:135`). Aucune commande ne tranche un choix d'icône : arbitrage de revue.
