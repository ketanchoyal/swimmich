# Task: settings-parity

> **Audit 2026-09-15 — écart G22** (`.omp/backlog/ImmichSwiftUI-backlog.md:797`) : le client Flutter expose trois familles de réglages purement locaux que l'app iOS ne persiste pas du tout —
`mobile/lib/widgets/settings/asset_list_settings/{asset_list_settings,asset_list_group_settings,asset_list_layout_settings}.dart` (clés `.timelineGroupAssetsBy`, `.timelineTilesPerRow`),
`asset_viewer_settings/{image_viewer_quality_setting,image_viewer_tap_to_navigate_setting,video_viewer_settings,slideshow_settings}.dart` (clés `.imageLoadOriginal`, `.viewerTapToNavigate`,
`.viewerAutoPlayVideo`, `.viewerLoopVideo`, `.viewerLoadOriginalVideo`, `.slideshowRepeat`, `.slideshowDuration`, `.slideshowLook`, `.slideshowDirection`) et
`preference_settings/{theme_setting,primary_color_setting,haptic_setting}.dart` (clés `.themeMode`, `.themeColorfulInterface`, `.themeDynamic`, `.themePrimaryColor`), les trois dossiers vérifiés
présents sur `immich-app/immich@e55ac299`. Côté iOS, `grep -rn "@AppStorage" Sources/` ne renvoie qu'une seule déclaration (`ProfileView.swift:9`, le verrou Face ID) et `grep -rn
"preferredColorScheme" Sources/` ne renvoie rien : la densité de la grille, le groupement, la qualité d'image du viewer, le tap-to-navigate, la vidéo et le diaporama sont tous des états de session non
persistés, et le thème, la couleur d'accent et le retour haptique n'ont aucun réglage.

**Objectif** : après cette fiche, l'utilisateur ouvre « Preferences » depuis le hub « Me » et règle ce qui décide de son confort quotidien — le groupement de la timeline (jour / mois / à plat) et sa
densité (colonnes), la qualité d'image du viewer (aperçu transcodé ou fichier original), le tap-to-navigate, l'autoplay / la boucle / la source de la vidéo, la cadence, le style et l'ordre du
diaporama, le thème (système / clair / sombre), la couleur d'accent et le retour haptique global. Chaque choix survit au redémarrage et prend effet immédiatement, sans relancer l'app.

**Hors périmètre** :
- `themeColorfulInterface` (« interface colorée ») et `themeDynamic` (thème dérivé de la photo affichée) : les surfaces du dépôt viennent d'un jeu unique de couleurs dynamiques `Color(light:dark:)`
(`Sources/DesignSystem/Tokens/ImmichColors.swift:11-59`) et d'une sémantique iOS écrite noir sur blanc dans son en-tête (`:72-75` : « `immichBackground` / `immichForeground` / `immichGray` ne
remplacent PAS systématiquement les semantic colors iOS »). Un second axe de palette doublerait chaque token et chaque composant du DesignSystem ; le thème dérivé d'une photo exigerait en plus une
extraction de palette par asset. Deux axes, deux chantiers, aucun dans le périmètre.
- La couleur d'accent **arbitraire** (nuancier libre, pipette) : le réglage offert est une liste fermée de presets, appliquée par un unique `.tint(...)` à la racine. Choisir la couleur exacte du rose
d'Immich n'est pas ce que l'utilisateur demande quand il veut « une autre couleur que le bleu-violet ».
- Les réglages déjà en place, qu'il ne faut **pas** redéplacer dans ce nouvel écran : le verrou Face ID (`ProfileView.swift:131-141`, source de vérité `AppLockViewModel.enabledKey` =
`app_lock_enabled`, `Sources/Features/Auth/AppLockViewModel.swift:8-10`) et la langue (`ProfileView.swift:44-52`, `Sources/Features/Settings/AppLanguageStore.swift:21`, clé `appLanguage`). L'écran «
Preferences » ne les mentionne pas.
- Les réglages de sauvegarde (`Sources/Features/Upload/UploadViewModel.swift:92-96`, suite `backupSettings`) et de notifications : ils ont leurs écrans et leur propre suite `UserDefaults`.
- Le moteur de haptique lui-même : aucun retour haptique n'est ajouté ni retiré, le réglage ne fait qu'activer/désactiver ce que les vues déclarent déjà.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main` = `e55ac299`, le 2026-09-15) :

- **Upstream — les clés écrites**, extraites des fichiers ci-dessus (`settingsProvider.write(...)`) : `.timelineGroupAssetsBy`, `.timelineTilesPerRow` (borné 1…7 dans l'UI Flutter,
`asset_list_layout_settings.dart:28`), `.imageLoadOriginal`, `.viewerTapToNavigate`, `.viewerAutoPlayVideo`, `.viewerLoopVideo`, `.viewerLoadOriginalVideo`, `.slideshowRepeat`, `.slideshowDuration`,
`.slideshowLook`, `.slideshowDirection`, `.themeMode`, `.themePrimaryColor`. Les *valeurs* des enums `GroupAssetsBy`, `SlideshowLook`, `SlideshowDirection` et de la liste de presets
`themePrimaryColor` **n'ont pas été vérifiées** — voir Incertitudes ; le plan n'en dépend pas (iOS choisit ses propres alternatives, équivalentes en surface), mais l'implémentation doit les confronter
avant de figer les libellés.
- **Aucune route serveur** n'est concernée : les trois dossiers upstream ne lisent que `settingsProvider` / `appConfigProvider` et n'appellent aucun endpoint. Rien à chercher dans
`/tmp/immich-openapi-main.json` — ces réglages sont purement client, donc rien n'est bloqué par une version de serveur.
- **La densité de la grille est un état de session.** `TimelineView.swift:26-33` : `private let defaultColumnCount = 3`, `minColumnCount = 2`, `maxColumnCount = 7`, et le zoom est un `@State private
var gridScale` (commentaire `:26-28` : « `gridScale` persists the committed zoom between gestures »). La correspondance zoom → colonnes est pure et testable
(`TimelineGridZoom.scale(forColumnCount:defaultColumns:)`, `effectiveScale`, `columns(forEffectiveScale:defaultColumns:minColumns:maxColumns:)`, `Sources/Features/Timeline/TimelineGridZoom.swift`) et
le geste est posé en `:162-186`. Conséquence : le geste est le bon écrivain du réglage, il ne manque que la persistance et la graine de départ.
- **Le groupement se décide dans la vue, pas dans le ViewModel.** `TimelineSectionBuilder.build(from groupedByDay: [(day: String, items: [AssetReactItem])]) -> [Section]`
(`TimelineSectionBuilder.swift:51-53`) rend `enum Section: Identifiable, Equatable { case monthHeader(month:display:), case dayGroup(day:items:) }` (`:28-34`) ; `TimelineView` en fait un
`ForEach(timelineSections)` (`:367`) au-dessus d'un `LazyVGrid(columns: spacing:)` (`:366`). `TimelineViewModel.groupedByDay` (`:276`) est un groupement par jour mis en cache et n'a aucune notion de
regroupement. Le paramètre de regroupement s'ajoute donc à la **fonction pure** et à la vue : le ViewModel n'est pas touché.
- **Le viewer lit `.fullsize`, pas l'original.** `Sources/Features/PhotoViewer/ZoomableImageView.swift:48` : `asset.thumbnailURL(base: baseURL, size: .fullsize, sharedLink: sharedLink)` — une seule
ligne décide de la variante servie, documentée en `PhotoViewer.swift:108` (« the photo is fetched at `.fullsize` and fits »). L'alternative existe déjà et est éprouvée :
`ImmichAssetURL.original(assetId:baseURL:sharedLink:)` (`Sources/Services/ImmichAssetURL.swift:36-39`), utilisée par `SaveToLibraryViewModel.transferOriginal()` (`:112`) et par l'index hors-ligne
(`Sources/Services/OfflineAssetStore.swift:136-138`).
- **La vidéo auto-play déjà, ne boucle pas, et a déjà une couture d'URL.** `VideoPlaybackViewModel` (`Sources/Features/PhotoViewer/VideoPlaybackViewModel.swift`) : `@Observable @MainActor`, doc `:7` «
Auto-plays once prepared (Photos behavior) », l'URL vient de `ImmichAssetURL.videoPlayback(assetId:baseURL:)` (`:60`) et la préparation passe par une couture publique qui prend une URL (`await
prepare(url: assetID: token:)`, `:61`). Aucune trace de boucle ni d'URL originale dans ce fichier.
- **Le diaporama a déjà ses trois axes, en session seulement.** `SlideshowViewModel.SlideshowSpeed: TimeInterval, CaseIterable, Identifiable { twoSeconds = 2, threeSeconds = 3, fiveSeconds = 5 }`
(`:16-25`) et `SlideshowTransitionStyle: String, CaseIterable, Identifiable { dissolve, slide, kenBurns }` (`:29-33`) sont choisis dans les menus de `SlideshowView` (`speedMenu`, `:279`) ; l'ordre vit
dans `order` / `shuffle()` (`:130`) et le helper pur `SlideshowDirection.isForward(from:to:count:)` (`:145`) n'est qu'une décision de transition. `slideshowLook` se projette donc sur le style de
transition **existant**, sans nouvel enum.
- **Les haptiques sont déclarés vue par vue, sans aucun point de passage commun** — 14 fichiers, 20 modificateurs `.sensoryFeedback` : `AddToAlbumPickerSheet.swift:60`,
`AlbumDetailView.swift:339-343`, `CreateAlbumSheet.swift:59`, `EditAlbumSheet.swift:68`, `LoginScreen.swift:94`, `PhotoEditorView.swift:68-70`, `MemoryMomentView.swift:77`,
`PhotoViewer.swift:948-951`, `SlideshowView.swift:276`, `SearchModeGlassBar.swift:59`, `EditSharedLinkSheet.swift:117`, `SharedLinksView.swift:421,512`, `TimelineView.swift:225-228`,
`TrashView.swift:44-45`. Un interrupteur global doit donc passer par un modificateur unique, pas par 20 conditions dispersées.
- **Le SDK fournit la porte exacte.** Vérifié dans le `.swiftinterface` du SDK iOS 26.2 : `func sensoryFeedback<T>(trigger: T, _ feedback: @escaping () -> SensoryFeedback?) -> some View where T :
Equatable` — la variante qui rend un **optionnel** : rendre `nil` supprime le retour au lieu de le jouer. C'est le seul mécanisme public qui permette de couper les haptiques sans toucher à la valeur
déclarée par chaque vue.
- **Le patron MVVM à suivre est en place.** `LanguageSettingsViewModel` (`Sources/Features/Settings/LanguageSettingsViewModel.swift`) : `@MainActor @Observable final class`, `private let store`, aucun
état propre, chaque lecture et chaque mutation transmise au store — « so the store stays the single writer and this screen can never disagree with what the next launch reads ». C'est exactement la
forme du ViewModel de cette fiche.
- **Les stores de préférences existants et leurs clés** : `AppLanguageStore.defaultsKey = "appLanguage"` sur `.standard` (`:21`, injectable `init(defaults:)`) ; `AppLockViewModel.enabledKey` sur
`.standard` via `@AppStorage` ; `UploadViewModel(suiteName: "backupSettings")`. Un store de préférences d'appareil partage la convention des deux premiers : `.standard`, injectable pour les tests.
- **L'injection racine est connue.** `RootView.swift:15` `@State private var language: AppLanguageStore` initialisé depuis le conteneur (`:22`), puis `.environment(auth) / .environment(appLock) /
.environment(language) / .environment(\.locale, …)` (`:39-51`) sur le `Group` qui enveloppe onboarding, racine authentifiée et verrou. `DependencyContainer.swift:53-54` tient `let language:
AppLanguageStore` avec le commentaire qui interdit une seconde instance (« a second instance would disagree with the one on screen »). `AuthenticatedRoot` (`RootView.swift:104-107`) tient les VMs
passés au hub, `ProfileView(...)` étant construit en `:234`.

**Approche retenue** : A — un store unique `AppSettingsStore` (`@MainActor @Observable`, `UserDefaults` injectable, une propriété calculée par réglage qui écrit à la mutation), injecté dans l'arbre
**une fois** à la racine, consommé directement par les vues qui possèdent l'axe concerné (grille : `TimelineView` ; viewer : `ZoomableImageView` / `PhotoViewer` / `VideoPlaybackViewModel` /
`SlideshowView`) et par un unique écran « Preferences » poussé depuis le hub « Me » ; les haptiques passent par **un** modificateur `.appSensoryFeedback(...)` posé sur les 20 appels existants.
- **B (rejetée)** : des `@AppStorage` dispersés dans chaque vue consommatrice, un par réglage → rejetée pour trois raisons mesurables. (1) Le réglage de densité a **deux écrivains** (le geste dans
`TimelineView`, le stepper dans l'écran de préférences) et `@AppStorage` ne synchronise pas deux déclarations indépendantes de la même clé dans deux vues vivantes — c'est exactement le bug que
`DependencyContainer.swift:53` documente pour la langue. (2) `@AppStorage` n'est pas injectable : les cas de repli (valeur stockée illisible, densité hors bornes 2…7) deviennent intestables sans
écrire dans le `UserDefaults.standard` du simulateur. (3) La clé serait recopiée 12 fois ; une faute de frappe crée un réglage silencieusement mort.
- **C (rejetée)** : un ViewModel par famille de réglages (`GridSettingsViewModel`, `ViewerSettingsViewModel`, `PreferenceSettingsViewModel`), à l'image des trois pages Flutter → rejetée parce que la
césure upstream est un artefact de son architecture : Flutter ouvre une **route** par groupe et doit donc un VM par route, alors que cet écran tient en ~14 contrôles. Trois VMs, trois injections et
trois points d'entrée pour un seul écran reproduiraient une contrainte de navigation qu'iOS n'a pas — précédent local inverse : un seul `NotificationSettingsViewModel` porte déjà tous les réglages de
notifications.

## Étapes

1. **Les axes de préférence** — NEW `Sources/Features/Settings/AppTheme.swift` : `import SwiftUI`. `enum AppTheme: String, CaseIterable, Identifiable { case system, light, dark }` avec `var id: String
{ rawValue }`, `var label: String` (`"System"` / `"Light"` / `"Dark"`, clés du catalogue) et `var colorScheme: ColorScheme?` (`.system → nil`, `.light → .light`, `.dark → .dark`) — `nil` est la valeur
qui laisse iOS décider. `enum AppAccent: String, CaseIterable, Identifiable { case immich, blue, green, orange, pink, purple }` avec `var color: Color` (le cas `immich` rend `Color.immichPrimary` — la
couleur de marque actuelle, `ImmichColors.swift:11-16` — pour que « ne rien changer » reste le défaut exact) et `var label: String`.
2. **Le store** — NEW `Sources/Features/Settings/AppSettingsStore.swift` : `@MainActor @Observable final class AppSettingsStore`, `import Foundation`. `init(defaults: UserDefaults = .standard)`, les
clés en `static let` reprenant le vocabulaire upstream (`timelineGroupByKey = "timelineGroupAssetsBy"`, `timelineTilesPerRowKey`, `imageLoadOriginalKey`, `tapToNavigateKey`, `autoPlayVideoKey`,
`loopVideoKey`, `loadOriginalVideoKey`, `slideshowRepeatKey`, `slideshowSpeedKey`, `slideshowLookKey`, `slideshowReverseKey`, `themeModeKey`, `accentColorKey`, `hapticsEnabledKey =
"hapticFeedbackEnabled"`). Chaque réglage est **privé en stockage, public en accès** : `private var storedTilesPerRow` + `var tilesPerRow: Int { get { storedTilesPerRow } set { let clamped =
min(max(newValue, 2), 7); guard clamped != storedTilesPerRow else { return }; storedTilesPerRow = clamped; defaults.set(clamped, forKey: …) } }` — le patron `guard` puis écriture de
`AppLanguageStore.apply(code:)`. Sont exposés : `tilesPerRow: Int` (borné **2…7**, les bornes de `TimelineView.swift:30-32`), `groupBy: TimelineGroupBy` (`.day` par défaut, cf. étape 10),
`loadOriginal: Bool`, `tapToNavigate: Bool`, `autoPlayVideo: Bool`, `loopVideo: Bool`, `loadOriginalVideo: Bool`, `slideshowRepeat: Bool`, `slideshowSpeed: TimeInterval`, `slideshowLook: String`,
`slideshowReverse: Bool`, `theme: AppTheme`, `accent: AppAccent`, `hapticsEnabled: Bool`. **Règle de défaut** : chaque valeur par défaut reproduit exactement le comportement d'aujourd'hui
(`tilesPerRow = 3`, `groupBy = .day`, `loadOriginal = false`, `autoPlayVideo = true`, `loopVideo = false`, `loadOriginalVideo = false`, `theme = .system`, `accent = .immich`, `hapticsEnabled = true`),
de sorte que la fiche soit purement additive. Toute valeur stockée illisible retombe sur le défaut (`defaults.string(forKey:)` puis `AppTheme(rawValue:) ?? .system`). Un `func resetToDefaults()` purge
les 14 clés — l'appareil doit pouvoir revenir à l'état d'usine sans réinstaller.
3. **La porte des haptiques** — NEW `Sources/Features/Settings/HapticsEnvironment.swift` : `import SwiftUI`. `private struct HapticsEnabledKey: EnvironmentKey { static let defaultValue = true }` +
`extension EnvironmentValues { var hapticsEnabled: Bool }`, puis `private struct AppSensoryFeedbackModifier<T: Equatable>: ViewModifier` qui lit `@Environment(\.hapticsEnabled) private var
hapticsEnabled` et rend `content.sensoryFeedback(trigger: trigger) { _ in hapticsEnabled ? feedback : nil }` — signature vérifiée ci-dessus. `extension View { func appSensoryFeedback<T: Equatable>(_
feedback: SensoryFeedback, trigger: T) -> some View }`. Le `defaultValue = true` est ce qui rend le modificateur sûr hors de l'arbre racine (aperçus `#if DEBUG`, vues testées isolément) : sans lui, la
lecture d'un environnement absent ferait planter un aperçu.
4. **Le ViewModel** — NEW `Sources/Features/Settings/PreferencesViewModel.swift` : `@MainActor @Observable final class PreferencesViewModel` sur le patron exact de `LanguageSettingsViewModel` —
`private let store: AppSettingsStore`, `init(store:)`, **aucun état propre**, chaque propriété est un passe-plat calculé (`var theme: AppTheme { get { store.theme } set { store.theme = newValue } }`
et de même pour les 13 autres), et `func resetToDefaults()` transmet au store. Aucune logique ici : le store reste l'unique écrivain.
5. **L'écran** — NEW `Sources/Features/Settings/PreferencesView.swift` : `import SwiftUI`. `struct PreferencesView: View` avec `@Bindable var vm: PreferencesViewModel` et `@State private var
showResetConfirm = false`. Corps : `Form` (idiome des réglages iOS, et cohérent avec `NotificationSettingsView`) ou `List` selon le patron de ce dernier, `.navigationTitle("Preferences")`,
`.navigationBarTitleDisplayMode(.inline)`, `.confirmationDialog("Reset Preferences?", isPresented: $showResetConfirm)` avec `Button("Reset", role: .destructive) { vm.resetToDefaults() }`. **Aucun
`NavigationStack`** : la vue est poussée depuis `ProfileView`, qui en porte un (`ProfileView.swift:25`) — même contrainte que `LanguageSettingsView`, `OfflineAssetsView`, `StackView`. Six sections :
*Photos* (`Picker("Group By", selection: $vm.groupBy)` en `.segmented` ou `.menu` ; `Stepper("Columns", value: $vm.tilesPerRow, in: 2...7)`), *Viewer* (`Toggle("Load Full Quality", isOn:
$vm.loadOriginal)` ; `Toggle("Tap to Navigate", isOn: $vm.tapToNavigate)`), *Video* (`Toggle("Auto-Play", …)`, `Toggle("Loop", …)`, `Toggle("Stream Original", …)`), *Slideshow* (`Toggle("Repeat", …)`,
picker de cadence alimenté par `SlideshowViewModel.SlideshowSpeed.allCases`, picker de style alimenté par `SlideshowViewModel.SlideshowTransitionStyle.allCases`, `Toggle("Reverse Order", …)`),
*Appearance* (`Picker("Theme", …)` alimenté par `AppTheme.allCases`, `Picker("Accent Color", …)` alimenté par `AppAccent.allCases` avec une pastille `Circle().fill(preset.color)` en `Label`),
*Feedback* (`Toggle("Haptic Feedback", isOn: $vm.hapticsEnabled)`), plus une dernière section `Button("Reset", role: .destructive)`. Identifiants d'accessibilité sur chacun des 14 contrôles
(`preferencesColumnsStepper`, `preferencesGroupPicker`, `preferencesLoadOriginalToggle`, `preferencesTapToNavigateToggle`, `preferencesAutoPlayToggle`, `preferencesLoopVideoToggle`,
`preferencesOriginalVideoToggle`, `preferencesSlideshowRepeatToggle`, `preferencesSlideshowSpeedPicker`, `preferencesSlideshowLookPicker`, `preferencesSlideshowReverseToggle`,
`preferencesThemePicker`, `preferencesAccentPicker`, `preferencesHapticsToggle`) — c'est la surface que les tests d'acceptation grep.
6. **L'injection** — EDIT `Sources/DependencyContainer.swift` : ajouter `let appSettings: AppSettingsStore` à côté de `let language: AppLanguageStore` (`:53-54`) et l'initialiser dans `init()` sur
`.standard` ; ajouter `func makeAppSettingsViewModel() -> PreferencesViewModel { PreferencesViewModel(store: appSettings) }` à côté de `makeLanguageSettingsViewModel()`.
7. **La racine** — EDIT `Sources/RootView.swift` : `@State private var appSettings: AppSettingsStore` après `language` (`:15`) et `_appSettings = State(initialValue: container.appSettings)` dans
`init` (`:22`) ; dans `body`, à la suite de `.environment(language)` (`:42`), ajouter `.environment(appSettings)` et `.environment(\.hapticsEnabled, appSettings.hapticsEnabled)` ; sur le `ZStack`
extérieur (`:63`), ajouter `.preferredColorScheme(appSettings.theme.colorScheme)` et `.tint(appSettings.accent.color)`. Le `ZStack` extérieur, et pas `AuthenticatedRoot` : le thème et l'accent doivent
aussi couvrir l'onboarding et l'écran de verrou (`LockView`). Dans `AuthenticatedRoot` : `@State private var appSettings: PreferencesViewModel` après `language` (`:107`), `_appSettings =
State(initialValue: container.makeAppSettingsViewModel())` (`:135`), et `appSettings: appSettings` ajouté à l'appel `ProfileView(...)` (`:234`).
8. **Le point d'entrée** — EDIT `Sources/Features/Profile/ProfileView.swift` : `@State var appSettings: PreferencesViewModel` après `language` (`:22`) ; insérer, **avant** la section Language (`:44`),
un bloc `Section { NavigationLink { PreferencesView(vm: appSettings) } label: { Label("Preferences", systemImage: "slider.horizontal.3") } .accessibilityIdentifier("preferencesRow") } header: {
Text("General") }`. La section porte un en-tête parce qu'elle n'a qu'une ligne : sans lui, rien ne dit à l'utilisateur que ce qu'il ouvre n'est ni le compte, ni le serveur, ni le stockage. L'ordre
place « Preferences » en tête des réglages d'appareil, avant Language, et son icône `slider.horizontal.3` reste distincte de `globe` (Language), `gearshape.2` (Administration) et `icloud.and.arrow.up`
(Backup).
9. **La densité persistée** — EDIT `Sources/Features/Timeline/TimelineView.swift` : ajouter `@Environment(AppSettingsStore.self) private var appSettings` ; remplacer `private let defaultColumnCount =
3` (`:29`) par `@State private var baseColumns: Int = 0` semé une fois dans `onAppear` (`baseColumns = appSettings.tilesPerRow`, `gridScale = 1`) et faire passer `defaultColumns: baseColumns` aux
trois appels de `TimelineGridZoom` (`:165-186`) ; dans `.onEnded`, après avoir recalculé `gridScale`, ajouter `appSettings.tilesPerRow = columnCount` — le geste devient l'écrivain du réglage, la
persistance étant la seule chose qui manquait. `minColumnCount` / `maxColumnCount` restent `2` / `7` (`:30-32`) et sont désormais la même borne que celle du store. L'écriture depuis l'écran de
préférences est lue par la vue sans geste supplémentaire : `baseColumns` ne se resème pas, donc une modification à chaud exige de réagir au changement — ajouter `.onChange(of: appSettings.tilesPerRow)
{ _, new in if new != columnCount { columnCount = new; gridScale = TimelineGridZoom.scale(forColumnCount: new, defaultColumns: new) } }`.
10. **Le groupement** — EDIT `Sources/Features/Timeline/TimelineSectionBuilder.swift` : `enum TimelineGroupBy: String, CaseIterable, Identifiable { case day, month, none }` (défini dans ce fichier,
au-dessus de `TimelineSectionBuilder`, avec `var label: String`) ; ajouter `case flat(items: [AssetReactItem])` à `enum Section` (`:28-34`) et un paramètre `groupBy: TimelineGroupBy = .day` à `static
func build(from:groupBy:)` (`:51-53`). `.day` garde la sortie d'aujourd'hui (`monthHeader` + `dayGroup`) ; `.month` rend un `monthHeader` suivi d'un `monthGroup(items:)` par mois (nouveau cas,
`Identifiable` par la clé `"YYYY-MM"`) ; `.none` rend un unique `flat(items:)`. Puis EDIT `Sources/Features/Timeline/TimelineView.swift` : `timelineSections` appelle
`TimelineSectionBuilder.build(from: vm.groupedByDay, groupBy: appSettings.groupBy)` et le `switch` du `ForEach` (`:367-380`) rend les nouveaux cas avec le même `LazyVGrid(columns: columns, spacing:
PVSpacing.s2)`. Trois cas, un seul builder, aucune duplication de grille.
11. **La qualité d'image du viewer** — EDIT `Sources/Features/PhotoViewer/ZoomableImageView.swift` : ajouter `@Environment(AppSettingsStore.self) private var appSettings` et, ligne 48, construire
l'URL selon le réglage — `appSettings.loadOriginal ? ImmichAssetURL.original(assetId: asset.id, baseURL: baseURL, sharedLink: sharedLink) : asset.thumbnailURL(base: baseURL, size: .fullsize,
sharedLink: sharedLink)`. Le helper `ImmichAssetURL.original` existe déjà (`ImmichAssetURL.swift:36-39`) et gère le lien partagé ; le cache (`ImageCache.shared` + `URLCache` `immich-image-cache`)
couvre les deux URL sans changement.
12. **Le tap-to-navigate** — EDIT `Sources/Features/PhotoViewer/PhotoViewer.swift` : `@Environment(AppSettingsStore.self) private var appSettings` et, sur le geste de tap de la page photo, brancher la
bascule — `tapToNavigate` désactivé : comportement actuel (bascule du chrome) ; activé : avancer d'un asset dans la `TabView` de pagination sans toucher au chrome. La lecture se fait au moment du tap,
pas à la construction de la vue, pour qu'un changement dans « Preferences » s'applique au viewer déjà ouvert.
13. **La vidéo** — EDIT `Sources/Features/PhotoViewer/VideoPlaybackViewModel.swift` : le VM reçoit le store (`init(engine:appSettings:)`, une valeur par défaut `.shared` pour ne casser aucun appelant
de test) et lit les trois réglages **au moment de `prepare`**, pas à l'init : l'URL devient `loadOriginalVideo ? ImmichAssetURL.original(assetId: baseURL:) : ImmichAssetURL.videoPlayback(assetId:
baseURL:)` (`:60`, les deux helpers déjà présents), l'auto-play est conditionné par `autoPlayVideo` (aujourd'hui inconditionnel, `:7`) et la fin de lecture boucle ou s'arrête selon `loopVideo` (le
hook de fin existe déjà — l'engine notifie la fin de lecture, cf. le commentaire `:20-22`). Puis EDIT `Sources/Features/PhotoViewer/VideoPlayerView.swift` pour transmettre le store au VM. **La Live
Activity et la sauvegarde ne sont pas concernées** : elles lisent le fichier, pas la source de lecture.
14. **Le diaporama** — EDIT `Sources/Features/PhotoViewer/SlideshowViewModel.swift` : `init(assets:appSettings:)` sème `speed` depuis `appSettings.slideshowSpeed` (repli sur `.threeSeconds` si la
valeur stockée n'est pas 2/3/5), `transitionStyle` depuis `appSettings.slideshowLook` (repli sur `.dissolve`) et `order` en ordre inverse quand `slideshowReverse`; les setters de `speed` /
`transitionStyle` **écrivent dans le store** — le menu de l'écran et l'écran de préférences modifient alors la même valeur, ce que `@AppStorage` ne garantissait pas (approche B). Ajouter `var repeats:
Bool { get/set → store.slideshowRepeat }`. Puis EDIT `Sources/Features/PhotoViewer/SlideshowView.swift` : le ticker (`:6-10`) ne s'arrête plus à la dernière diapositive quand `vm.repeats`, et le
`speedMenu` (`:279`) lit/écrit le VM sans changement de structure.
15. **Les haptiques, partout** — EDIT les 14 fichiers listés dans les hypothèses : remplacer chaque `.sensoryFeedback(` par `.appSensoryFeedback(` — une seule transformation par site, la valeur
déclarée (`.success` ou `.impact(weight: .light)`) et le `trigger` sont inchangés, la condition vivant dans le modificateur. Sans cette étape le réglage ne couvrirait que les écrans neufs, ce qui est
un contrôle mort. Les appels de `Sources/WidgetExtensionProbe` / extensions n'existent pas dans cette liste : aucun retour haptique n'y est déclaré.
16. **Les tests du store** — NEW `Tests/AppSettingsStoreTests.swift` : `import XCTest`, `@testable import ImmichSwiftUI`, une suite `final class AppSettingsStoreTests: XCTestCase` `@MainActor` avec un
`UserDefaults(suiteName: "appSettingsTests-\(UUID().uuidString)")!` remis à zéro dans `tearDown`. Cas : `test_defaults_matchCurrentBehaviour` (les 14 réglages valent exactement ce que l'app fait
aujourd'hui), `test_tilesPerRow_isClampedToTwoThroughSeven` (`1 → 2`, `9 → 7`), `test_everySetting_survivesAFreshStoreOnTheSameDefaults` (un second store sur les mêmes defaults relit les 14 valeurs),
`test_unreadableStoredTheme_fallsBackToSystem`, `test_resetToDefaults_restoresEveryKey`, et deux cas de projection : `test_theme_colorScheme_nilOnlyForSystem` et `test_accent_immichIsTheBrandColor`.
Chaque cas porte sur **une** propriété observable ou une transition : ce fichier est la preuve que le réglage survit au redémarrage, ce qui est exactement la promesse de la fiche.
17. `xcodegen generate` (six fichiers source et un fichier de test ajoutés : sans régénération ils ne sont pas compilés), puis la suite complète `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation

- **Les valeurs exactes des enums upstream** (`GroupAssetsBy`, `SlideshowLook`, `SlideshowDirection`, presets `themePrimaryColor`) : elles décident des **libellés** et du nombre d'options, pas de
l'architecture. Trancher par : `git clone --depth 1 --branch main https://github.com/immich-app/immich /tmp/immich-up && grep -rn "enum GroupAssetsBy\|enum SlideshowLook\|enum
SlideshowDirection\|PrimaryColorPreset" /tmp/immich-up/mobile/lib` — puis aligner `TimelineGroupBy` / la liste de presets sur ce qui existe, et documenter tout écart volontaire (`.none` à plat,
presets iOS).
- **Le geste de tap actuel dans `PhotoViewer`.** Le comportement de repli (« tap = bascule du chrome ») est déduit de la structure de l'écran, pas lu. Trancher par : `grep -n
"onTapGesture\|showControls\|chromeVisible" Sources/Features/PhotoViewer/PhotoViewer.swift` — si le tap est déjà détourné (double-tap du zoom, par exemple), c'est le moment de décider la priorité
entre `ZoomableImageView` et le réglage.
- **Le hook de fin de lecture de la vidéo.** `loopVideo` a besoin du nom exact du rappel de fin dans `VideoPlaybackEngine`. Trancher par : `grep -n "case ended\|func
loop\|actionAtItemEnd\|didPlayToEnd" Sources/Features/PhotoViewer/*.swift Sources/Services/*.swift`.
- **Où le `VideoPlaybackViewModel` est construit.** L'étape 13 suppose `VideoPlayerView`. Trancher par : `grep -rn "VideoPlaybackViewModel(" Sources/` — si un autre écran (Live Photo, Memory) en
construit un, il passe le même store.
- **`PinnedHeaderResolver` sous `.month` / `.none`.** L'en-tête collant suit aujourd'hui les groupes **jour** (`Sources/Features/Timeline/PinnedHeaderResolver.swift`) ; sans groupe jour il doit suivre
le mois ou disparaître. Trancher par : `grep -n "func resolve\|dayGroup\|monthHeader" Sources/Features/Timeline/PinnedHeaderResolver.swift` puis étendre son entrée, sans le dupliquer.
- **Le nom exact de la propriété de cadence et de transition dans `SlideshowViewModel`.** `speed` / `transitionStyle` sont déduits de `SlideshowSpeed` (`:16`) et de `SlideshowTransitionStyle` (`:29`),
pas lus. Trancher par : `grep -n "var speed\|var transitionStyle\|var order" Sources/Features/PhotoViewer/SlideshowViewModel.swift`.
- **La forme UI (`Form` vs `List`).** `NotificationSettingsView` est l'écran de réglages le plus proche ; s'aligner sur lui évite deux idiomes dans le même hub. Trancher par : `grep -n
"Form\|List\|Section" Sources/Features/Notifications/NotificationSettingsView.swift`.
- **Le catalogue de chaînes.** Aucune écriture manuelle dans `Resources/Localizable.xcstrings` : la clé est la chaîne anglaise, l'extraction est faite par Xcode au build (décision i18n du dépôt). Les
clés neuves sont les libellés des étapes 1, 5 et 8 ; vérifier qu'aucune n'existe déjà avant de figer la formulation : `python3 -c "import
json;d=json.load(open('Resources/Localizable.xcstrings'));print([k for k in d['strings'] if any(w in k for w in ('Theme','Accent','Haptic','Slideshow','Group','Columns'))])"`.
- **L'effet de `.tint(AppAccent.color)` sur les surfaces Liquid Glass.** `.tint` teinte les contrôles, mais les surfaces `glassEffect` du viewer et de la barre d'onglets ont leurs propres teintes
(`.glassEffect(.regular.tint(.black.opacity(0.6)))`, `PhotoViewer.swift:373`). Vérifier visuellement que l'accent choisi ne dégrade pas le contraste du chrome du viewer ; si c'est le cas, restreindre
`.tint` au `Group` intérieur et non au `ZStack`.
