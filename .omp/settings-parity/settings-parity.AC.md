# Task: settings-parity

Status: planifié — **aucune AC ouverte** (écart G22 du registre `.omp/backlog/ImmichSwiftUI-backlog.md:797`).

## Plan (résumé)

**Objectif** : l'utilisateur ouvre « Preferences » depuis le hub « Me » et règle ce qui décide de son
confort quotidien — groupement et densité de la timeline, qualité d'image du viewer, tap-to-navigate,
autoplay / boucle / source de la vidéo, cadence et style du diaporama, thème, couleur d'accent, retour
haptique global. Chaque choix survit au redémarrage et prend effet sans relancer l'app.

**Approche retenue** : A — un store unique `AppSettingsStore` (`@MainActor @Observable`, `UserDefaults`
injectable, une propriété calculée par réglage qui écrit à la mutation) injecté **une fois** à la racine,
consommé directement par les vues qui possèdent l'axe concerné, plus un seul écran poussé depuis
`ProfileView` ; les haptiques passent par **un** modificateur `.appSensoryFeedback(...)` posé sur les 20
appels existants. Les variantes B (`@AppStorage` dispersés) et C (un ViewModel par famille) sont rejetées
dans la spec, avec leurs raisons mesurables.

**Étapes** : (1) NEW `Sources/Features/Settings/AppTheme.swift` ; (2) NEW
`Sources/Features/Settings/AppSettingsStore.swift` ; (3) NEW `Sources/Features/Settings/HapticsEnvironment.swift` ;
(4) NEW `Sources/Features/Settings/PreferencesViewModel.swift` ; (5) NEW
`Sources/Features/Settings/PreferencesView.swift` ; (6) EDIT `DependencyContainer.swift` ; (7) EDIT
`RootView.swift` ; (8) EDIT `ProfileView.swift` ; (9) EDIT `TimelineView.swift` (densité) ; (10) EDIT
`TimelineSectionBuilder.swift` + `TimelineView.swift` (groupement) ; (11) EDIT `ZoomableImageView.swift` ;
(12) EDIT `PhotoViewer.swift` ; (13) EDIT `VideoPlaybackViewModel.swift` + `VideoPlayerView.swift` ;
(14) EDIT `SlideshowViewModel.swift` + `SlideshowView.swift` ; (15) EDIT les 14 fichiers portant les 20
`.sensoryFeedback` ; (16) NEW `Tests/AppSettingsStoreTests.swift` ; (17) `xcodegen generate` + suite.

**Défaut additif** : chaque valeur par défaut reproduit exactement le comportement d'aujourd'hui
(`tilesPerRow = 3`, `groupBy = .day`, `loadOriginal = false`, `autoPlayVideo = true`, `loopVideo = false`,
`loadOriginalVideo = false`, `theme = .system`, `accent = .immich`, `hapticsEnabled = true`), donc la
fiche n'enlève rien.

**Incertitudes** : valeurs exactes des enums upstream (`GroupAssetsBy`, `SlideshowLook`,
`SlideshowDirection`, presets `themePrimaryColor`) — décident des libellés, pas de l'architecture ;
nom du hook de fin de lecture pour `loopVideo` ; forme `Form` vs `List` (s'aligner sur
`NotificationSettingsView`) ; effet de `.tint` sur les surfaces Liquid Glass.

## Critères

```
### AC-5220 [type: new]
Assertion: `AppSettingsStore` existe avec les 14 clés nommées comme upstream et 14 accesseurs publics (stockage privé, écriture à la mutation), la densité bornée 2…7 et `resetToDefaults()`.
Check post-impl: sh -c 'f=Sources/Features/Settings/AppSettingsStore.swift; test -f "$f" && grep -qE "final class AppSettingsStore" "$f" && grep -qE "init[(]defaults: UserDefaults = [.]standard[)]" "$f" && grep -qE "static let timelineGroupByKey" "$f" && grep -qE "static let timelineTilesPerRowKey" "$f" && grep -qE "static let imageLoadOriginalKey" "$f" && grep -qE "static let tapToNavigateKey" "$f" && grep -qE "static let autoPlayVideoKey" "$f" && grep -qE "static let loopVideoKey" "$f" && grep -qE "static let loadOriginalVideoKey" "$f" && grep -qE "static let slideshowRepeatKey" "$f" && grep -qE "static let slideshowSpeedKey" "$f" && grep -qE "static let slideshowLookKey" "$f" && grep -qE "static let slideshowReverseKey" "$f" && grep -qE "static let themeModeKey" "$f" && grep -qE "static let accentColorKey" "$f" && grep -qE "static let hapticsEnabledKey" "$f" && grep -qF "timelineGroupAssetsBy" "$f" && grep -qF "hapticFeedbackEnabled" "$f" && grep -qE "var tilesPerRow: Int" "$f" && grep -qE "var groupBy: TimelineGroupBy" "$f" && grep -qE "var loadOriginal: Bool" "$f" && grep -qE "var tapToNavigate: Bool" "$f" && grep -qE "var autoPlayVideo: Bool" "$f" && grep -qE "var loopVideo: Bool" "$f" && grep -qE "var loadOriginalVideo: Bool" "$f" && grep -qE "var slideshowRepeat: Bool" "$f" && grep -qE "var slideshowSpeed: TimeInterval" "$f" && grep -qE "var slideshowLook: String" "$f" && grep -qE "var slideshowReverse: Bool" "$f" && grep -qE "var theme: AppTheme" "$f" && grep -qE "var accent: AppAccent" "$f" && grep -qE "var hapticsEnabled: Bool" "$f" && grep -qE "min[(]max[(]newValue, 2[)], 7[)]" "$f" && grep -qE "func resetToDefaults[(][)]" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `grep -rn "AppSettingsStore" Sources/` ne renvoie rien ; le dossier `Sources/Features/Settings/` n'abrite que la langue et le verrou)
Post-state attendu: PASS
Note: le check vise les **déclarations** (`static let …Key`, `var x: Type`) — un grep du seul mot clé matcherait aussi les doc-comments et ne prouverait rien sur les clés.
```

```
### AC-5221 [type: new]
Assertion: les deux axes fermés existent — `AppTheme` (system/light/dark, `colorScheme` dont `nil` laisse iOS décider) et `AppAccent` (six presets, `immich` rend la couleur de marque actuelle).
Check post-impl: sh -c 'f=Sources/Features/Settings/AppTheme.swift; test -f "$f" && grep -qE "import SwiftUI" "$f" && grep -qE "enum AppTheme: String, CaseIterable, Identifiable" "$f" && grep -qE "case system, light, dark" "$f" && grep -qE "var colorScheme: ColorScheme" "$f" && grep -qE "enum AppAccent: String, CaseIterable, Identifiable" "$f" && grep -qE "case immich, blue, green, orange, pink, purple" "$f" && grep -qE "var color: Color" "$f" && grep -qF "Color.immichPrimary" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `grep -rn "preferredColorScheme" Sources/` ne renvoie rien — le thème suit entièrement iOS, aucun axe d'accent n'existe)
Post-state attendu: PASS
Note: le défaut `.immich` doit rendre `Color.immichPrimary` pour que « ne rien changer » reste la couleur d'aujourd'hui.
```

```
### AC-5222 [type: new — couper les haptiques sans toucher aux 20 déclarations]
Assertion: la porte unique lit un `EnvironmentKey` de `defaultValue = true` et rend un `SensoryFeedback?` (`nil` supprime le retour) ; les 20 appels existants passent par elle et aucun `.sensoryFeedback(` ne subsiste hors de la porte.
Check post-impl: sh -c 'f=Sources/Features/Settings/HapticsEnvironment.swift; test -f "$f" && grep -qE "struct HapticsEnabledKey: EnvironmentKey" "$f" && grep -qE "static let defaultValue = true" "$f" && grep -qE "var hapticsEnabled: Bool" "$f" && grep -qE "func appSensoryFeedback<T: Equatable>" "$f" && grep -qF "hapticsEnabled ? feedback : nil" "$f" && c=$(grep -roE "[.]appSensoryFeedback[(]" Sources/Features | wc -l | tr -d " ") && test "$c" -ge 20 && r=$(grep -rlE "[.]sensoryFeedback[(]" Sources/Features | grep -v "HapticsEnvironment.swift" | wc -l | tr -d " ") && test "$r" -eq 0 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `grep -rn "appSensoryFeedback\|hapticsEnabled" Sources/` ne renvoie rien et 20 `.sensoryFeedback(` vivent dans 14 fichiers : AddToAlbumPickerSheet, AlbumDetailView, CreateAlbumSheet, EditAlbumSheet, LoginScreen, PhotoEditorView, MemoryMomentView, PhotoViewer, SlideshowView, SearchModeGlassBar, EditSharedLinkSheet, SharedLinksView, TimelineView, TrashView)
Post-state attendu: PASS
Note: `HapticsEnvironment.swift` est exclu du comptage résiduel parce qu'il contient l'unique appel `content.sensoryFeedback(trigger:)` de la porte ; le reste de `Sources/Features` doit compter 20 `.appSensoryFeedback(`.
```

```
### AC-5223 [type: new — le ViewModel ne possède aucun état]
Assertion: `PreferencesViewModel` est un passe-plat calculé vers le store (aucun stockage propre) et le composition root le fabrique.
Check post-impl: sh -c 'f=Sources/Features/Settings/PreferencesViewModel.swift; test -f "$f" && grep -qE "final class PreferencesViewModel" "$f" && grep -qE "@MainActor" "$f" && grep -qE "@Observable" "$f" && grep -qE "private let store: AppSettingsStore" "$f" && grep -qE "init[(]store: AppSettingsStore[)]" "$f" && grep -qE "var groupBy: TimelineGroupBy" "$f" && grep -qE "var theme: AppTheme" "$f" && grep -qE "var hapticsEnabled: Bool" "$f" && grep -qF "store.theme = newValue" "$f" && grep -qE "func resetToDefaults[(][)]" "$f" && ! grep -qE "^ *private var " "$f" && g=Sources/DependencyContainer.swift && grep -qE "let appSettings: AppSettingsStore" "$g" && grep -qE "func makeAppSettingsViewModel" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/Settings/PreferencesViewModel.swift` absent ; le conteneur ne tient que `language` et `makeLanguageSettingsViewModel()`)
Post-state attendu: PASS
Note: une seconde instance du store divergerait de celle à l'écran — c'est la raison mesurée pour laquelle le conteneur, et non la vue, tient l'instance.
```

```
### AC-5224 [type: new]
Assertion: `PreferencesView` rend les six sections, porte un identifiant d'accessibilité sur chacun des 14 contrôles, ne déclare AUCUN `NavigationStack` (elle est poussée depuis le hub « Me ») et confirme la remise à zéro.
Check post-impl: sh -c 'f=Sources/Features/Settings/PreferencesView.swift; test -f "$f" && grep -qE "struct PreferencesView" "$f" && grep -qE "@Bindable var vm: PreferencesViewModel" "$f" && grep -qF "navigationTitle(\"Preferences\")" "$f" && n=$(grep -cE "^[[:space:]]*Section[( {]" "$f") && test "$n" -ge 6 && i=$(grep -oE "preferences[A-Z][A-Za-z]+" "$f" | sort -u | wc -l | tr -d " ") && test "$i" -ge 14 && a=$(grep -oF "accessibilityIdentifier(\"preferences" "$f" | wc -l | tr -d " ") && test "$a" -ge 14 && grep -qF "preferencesColumnsStepper" "$f" && grep -qF "preferencesGroupPicker" "$f" && grep -qF "preferencesThemePicker" "$f" && grep -qF "preferencesAccentPicker" "$f" && grep -qF "preferencesHapticsToggle" "$f" && grep -qF "SlideshowSpeed.allCases" "$f" && grep -qF "SlideshowTransitionStyle.allCases" "$f" && grep -qF "AppTheme.allCases" "$f" && grep -qF "AppAccent.allCases" "$f" && grep -qF "confirmationDialog" "$f" && grep -qF "vm.resetToDefaults()" "$f" && ! grep -qE "NavigationStack [(]?[{]" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `grep -rn "PreferencesView" Sources/` ne renvoie rien)
Post-state attendu: PASS
Note: aucun libellé français — les chaînes d'UI sont des clés anglaises extraites par Xcode au build (décision i18n du dépôt), et les identifiants sont posés sur les contrôles eux-mêmes, jamais sur le conteneur `Form`/`Section` (sinon ils sont invisibles et donc inutiles).
```

```
### AC-5225 [type: new — le thème et l'accent couvrent aussi onboarding et verrou]
Assertion: la racine applique le store à tout l'arbre (environnement, porte des haptiques, `preferredColorScheme`, `tint`) et « Preferences » est une ligne du hub « Me » qui pousse l'écran.
Check post-impl: sh -c 'f=Sources/RootView.swift; grep -qF ".environment(appSettings)" "$f" && grep -qF ".environment(\.hapticsEnabled, appSettings.hapticsEnabled)" "$f" && grep -qF ".preferredColorScheme(appSettings.theme.colorScheme)" "$f" && grep -qF ".tint(appSettings.accent.color)" "$f" && grep -qE "appSettings: PreferencesViewModel" "$f" && grep -qF "makeAppSettingsViewModel" "$f" && p=Sources/Features/Profile/ProfileView.swift && grep -qE "var appSettings: PreferencesViewModel" "$p" && grep -qF "PreferencesView(vm: appSettings)" "$p" && grep -qF "preferencesRow" "$p" && grep -qF "slider.horizontal.3" "$p" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`RootView.swift` n'injecte que `auth`, `appLock`, `language` et `\.locale` ; aucune ligne « Preferences » dans `ProfileView.swift`)
Post-state attendu: PASS
Note: les deux modificateurs de thème vont sur le `ZStack` extérieur, pas sur `AuthenticatedRoot` — sinon l'onboarding et `LockView` gardent le thème système. `.tint` doit être vérifié visuellement contre les surfaces Liquid Glass du viewer.
```

```
### AC-5226 [type: new — la densité et le groupement sont réellement consommés]
Assertion: la grille sème sa densité depuis le store, le geste devient l'écrivain du réglage, un changement à chaud réagit, et le groupement est un paramètre du builder (trois cas, un seul builder).
Check post-impl: sh -c 'b=Sources/Features/Timeline/TimelineSectionBuilder.swift; v=Sources/Features/Timeline/TimelineView.swift; grep -qE "enum TimelineGroupBy: String, CaseIterable, Identifiable" "$b" && grep -qE "case day, month, none" "$b" && grep -qE "case flat[(]items: \[AssetReactItem\][)]" "$b" && grep -qE "case monthGroup[(]" "$b" && grep -qF "groupBy: TimelineGroupBy = .day" "$b" && grep -qF "groupBy: appSettings.groupBy" "$v" && grep -qF "@Environment(AppSettingsStore.self)" "$v" && grep -qF "appSettings.tilesPerRow" "$v" && grep -qF "appSettings.tilesPerRow = " "$v" && grep -qF "defaultColumns: baseColumns" "$v" && grep -qF ".onChange(of: appSettings.tilesPerRow)" "$v" && ! grep -qF "private let defaultColumnCount = 3" "$v" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`TimelineView.swift:29` porte encore `private let defaultColumnCount = 3` et `gridScale` est un `@State` de session ; `TimelineSectionBuilder.build(from:)` n'accepte aucun paramètre de groupement et `enum Section` n'a ni `flat` ni `monthGroup`)
Post-state attendu: PASS
Note: `defaultColumnCount` doit avoir DISPARU, pas cohabiter avec le réglage — deux sources pour la même densité divergent au premier redémarrage. `PinnedHeaderResolver` doit suivre le mois (et disparaître sous `.none`) sans être dupliqué.
```

```
### AC-5227 [type: new — le viewer et le diaporama lisent leur axe]
Assertion: la qualité d'image suit le réglage (original contre aperçu transcodé), le tap du viewer suit le réglage, la vidéo lit ses trois réglages à la préparation, et le diaporama sème ET réécrit ses trois axes dans le store.
Check post-impl: sh -c 'z=Sources/Features/PhotoViewer/ZoomableImageView.swift; p=Sources/Features/PhotoViewer/PhotoViewer.swift; v=Sources/Features/PhotoViewer/VideoPlaybackViewModel.swift; s=Sources/Features/PhotoViewer/SlideshowViewModel.swift; grep -qF "@Environment(AppSettingsStore.self)" "$z" && grep -qF "appSettings.loadOriginal" "$z" && grep -qF "ImmichAssetURL.original(assetId: asset.id" "$z" && grep -qF "size: .fullsize" "$z" && grep -qF "@Environment(AppSettingsStore.self)" "$p" && grep -qF "appSettings.tapToNavigate" "$p" && grep -qE "appSettings: AppSettingsStore" "$v" && grep -qF "appSettings.loadOriginalVideo" "$v" && grep -qF "appSettings.autoPlayVideo" "$v" && grep -qF "appSettings.loopVideo" "$v" && grep -qF "appSettings:" Sources/Features/PhotoViewer/VideoPlayerView.swift && grep -qE "appSettings: AppSettingsStore" "$s" && grep -qF "appSettings.slideshowSpeed" "$s" && grep -qF "appSettings.slideshowLook" "$s" && grep -qF "appSettings.slideshowReverse" "$s" && n=$(grep -oE "appSettings[.]slideshow(Speed|Look|Reverse)" "$s" | wc -l | tr -d " ") && test "$n" -ge 5 && grep -qE "var repeats" "$s" && grep -qF "vm.repeats" Sources/Features/PhotoViewer/SlideshowView.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`ZoomableImageView.swift:48` sert inconditionnellement `.fullsize` ; `PhotoViewer.swift` fait basculer le chrome au tap sans consulter de réglage ; `VideoPlaybackViewModel.swift` joue inconditionnellement la vidéo transcodée (`:7` « Auto-plays once prepared ») ; `SlideshowViewModel` garde `speed` / `transitionStyle` / `order` en session)
Post-state attendu: PASS
Note: les cinq occurrences minimum dans `SlideshowViewModel` sont la sème des trois axes plus la réécriture de `speed` et de `look` — c'est ce qui garantit que le menu de l'écran et l'écran de préférences modifient la même valeur. `tapToNavigate` est lu au moment du tap, pas à la construction de la vue.
```

```
### AC-5228 [type: new — preuve : le store survit au redémarrage et aucun réglage n'est mort]
Assertion: `Tests/AppSettingsStoreTests.swift` couvre les défauts, la borne, la relecture par un second store, le repli, la remise à zéro et les deux projections ; et chacun des 14 réglages est lu par un écran consommateur, hors du store et de l'écran de préférences (une clé écrite et jamais lue est un contrôle mort).
Check post-impl: sh -c 't=Tests/AppSettingsStoreTests.swift; test -f "$t" && grep -qF "@testable import ImmichSwiftUI" "$t" && n=$(grep -cE "func test_" "$t") && test "$n" -ge 7 && grep -qE "func test_defaults_matchCurrentBehaviour" "$t" && grep -qE "func test_tilesPerRow_isClampedToTwoThroughSeven" "$t" && grep -qE "func test_everySetting_survivesAFreshStoreOnTheSameDefaults" "$t" && grep -qE "func test_unreadableStoredTheme_fallsBackToSystem" "$t" && grep -qE "func test_resetToDefaults_restoresEveryKey" "$t" && grep -qE "func test_theme_colorScheme_nilOnlyForSystem" "$t" && grep -qE "func test_accent_immichIsTheBrandColor" "$t" && miss="" && for k in tilesPerRow groupBy loadOriginal tapToNavigate autoPlayVideo loopVideo loadOriginalVideo slideshowRepeat slideshowSpeed slideshowLook slideshowReverse theme accent hapticsEnabled; do grep -rqE "^[^/]*appSettings[.]$k" Sources/Features/Timeline Sources/Features/PhotoViewer Sources/RootView.swift || miss="$miss $k"; done && test -z "$miss" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Tests/AppSettingsStoreTests.swift` absent ; aucun des 14 réglages n'existe, donc aucune lecture consommatrice)
Post-state attendu: PASS
Note: la boucle de lecture exclut les lignes de commentaire (`^[^/]*`) pour qu'un doc-comment expliquant un réglage ne tienne pas lieu de consommation, et les racines de recherche sont les écrans consommateurs — pas `Sources/`, qui contiendrait le store lui-même et l'écran de préférences. Un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate`.
```

```
### AC-5229 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED — les 20 sites haptiques convertis et les 14 fichiers de vue touchés ne cassent aucun test existant.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_settingsparity_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_settingsparity_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
