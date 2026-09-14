# Task: widgets-homescreen

Status: implemented (2026-09-13), corrected 2026-09-14 — issue #19, `ImmichWidgets` extension

## Plan

**Objectif**: trois widgets Home Screen (Photos, Souvenirs, Favoris) + familles Lock Screen, alimentés par le vrai serveur Immich depuis le processus du widget (Keychain partagé), avec deep links vers l'app.

**Approche retenue**: A — 3 widgets data-driven (`StaticConfiguration` + `TimelineProvider`) + une extension interactive (`Button(intent:)`) + le Keychain partagé via entitlement. **B** (App Group) et **C** (widget unique) restent rejetées.

## Corrections du contrat d'origine (vérifiées avant implémentation)

La carte d'origine (issue #19) était dérivée sur quatre points, tous corrigés ici :

1. **`GET /api/assets?isFavorite=true` n'existe pas.** Vérifié le 2026-09-13 sur l'OpenAPI publié (`/tmp/immich-openapi-main.json`) : `/assets` n'expose que `delete|post|put`. Les favoris passent par **`GET /api/timeline/buckets?isFavorite=true`** (le query est optionnel) puis `GET /api/timeline/bucket?timeBucket=…`, exactement comme le timeline de l'app.
2. **Le token n'était pas partageable.** `Resources/ImmichSwiftUI.entitlements` existait mais n'était câblé nulle part (`project.yml` n'avait ni `CODE_SIGN_ENTITLEMENTS` ni bloc `entitlements:`), et `KeychainStoreImpl` n'écrit aucun `kSecAttrAccessGroup`. Un widget est un bundle distinct (`fr.millianlmx.immich-ios.widgets`) : sans groupe partagé il ne lit rien, et chaque fetch rendrait 401. Prérequis **AC-3610**, livré dans cette passe.
3. **`glassEffect` ne s'applique pas dans un widget.** Le brief UI demandait des cartes vitrées (`glassEffect(.regular)` sur chaque cellule) : la Liquid Glass API est réservée à l'UI de l'app, un widget rend sa propre platter. Le « vitré » est donc obtenu avec `.ultraThinMaterial` (pastilles), un scrim dégradé sur la photo et `containerBackground` — vérifié au rendu.
4. **Les deep links multi-cellules ne peuvent pas être des `widgetURL`.** Un widget n'a qu'**un** `widgetURL` (le fond). Une cellule = un `Link(destination:)`, ce que fait chaque tuile. Le brief demandait aussi « configuration à l'écran d'accueil » (album sélecteur) et « pull-to-refresh du widget » : ni l'un ni l'autre n'existe côté WidgetKit, retirés.

**Contrainte de structure conservée**: toutes les vues dessinables vivent dans `Sources/ImmichSharedKit/`, jamais dans `ImmichWidgets/` — le pipeline de previews de Xcode refuse les vues déclarées dans une target widget-extension. Les fichiers de l'extension ne sont que la déclaration WidgetKit + le `TimelineProvider`.

## Acceptance Contract

### AC-3600 [type: new]
Assertion: les trois widgets existent, et leur composition vit dans le kit partagé (préviewable).
Check post-impl: `sh -c 'for f in ImmichGridWidget ImmichMemoriesWidget ImmichFavoritesWidget; do test -f "ImmichWidgets/$f.swift" || exit 1; done; grep -q "public struct WidgetPhotosView" Sources/ImmichSharedKit/WidgetViews.swift && echo PASS || echo FAIL'`

### AC-3601 [type: new]
Assertion: `WidgetDataProvider` expose les trois surfaces (photos récentes, favoris, souvenirs) et lit la session par `WidgetSessionStore` (Keychain).
Check post-impl: `sh -c 'f=Sources/ImmichSharedKit/WidgetDataProvider.swift; s=Sources/ImmichSharedKit/WidgetSession.swift; grep -q "func recentPhotos" $f && grep -q "func favoritePhotos" $f && grep -q "func memories" $f && grep -q "kSecAttrAccessibleAfterFirstUnlock" $s && echo PASS || echo FAIL'`

### AC-3602 [type: new]
Assertion: le widget Photos a un `TimelineProvider` et couvre small/medium/large ; ses cellules portent un deep link (`Link`), son fond un `widgetURL` implicite (app).
Check post-impl: `sh -c 'g=ImmichWidgets/ImmichGridWidget.swift; v=Sources/ImmichSharedKit/WidgetViews.swift; grep -q TimelineProvider $g && grep -q systemSmall $g && grep -q systemMedium $g && grep -q systemLarge $g && grep -q "Link(destination: WidgetDeepLink.asset" $v && echo PASS || echo FAIL'`

### AC-3603 [type: new]
Assertion: le widget Souvenirs affiche la pastille « On this day » et route vers l'onglet Souvenirs (`widgetURL`).
Check post-impl: `sh -c 'g=ImmichWidgets/ImmichMemoriesWidget.swift; v=Sources/ImmichSharedKit/WidgetViews.swift; grep -q WidgetMemoriesView $g && grep -q "widgetURL(WidgetDeepLink.memories.url)" $g && grep -q "calendar.badge.clock" $v && echo PASS || echo FAIL'`

### AC-3604 [type: new]
Assertion: le widget Favoris porte le watermark cœur **par-dessus** la mosaïque (sous les photos, il est invisible — constaté au rendu) et chaque tuile est un deep link.
Check post-impl: `sh -c 'v=Sources/ImmichSharedKit/WidgetViews.swift; grep -q "private var watermark" $v && grep -q "heart.fill" $v && grep -q "mosaic(columns: 2, limit: 4, fill: true)" $v && echo PASS || echo FAIL'`

### AC-3605 [type: new]
Assertion: l'app route les liens des widgets (`app.immich://asset|memories|backup`) ; le callback OAuth (`app.immich:///oauth-callback`, sans host) est explicitement rejeté.
Check post-impl: `sh -c 'grep -q "onOpenURL" Sources/RootView.swift && grep -q "WidgetDeepLink.parse" Sources/RootView.swift && grep -q "public static func parse" Sources/ImmichSharedKit/WidgetDeepLink.swift && n=$(grep -c "func test_" Tests/WidgetDeepLinkTests.swift); test "$n" -ge 8 && echo PASS || echo FAIL'`

### AC-3606 [type: new]
Assertion: le chemin de données du widget est couvert par des tests de comportement (≥3) : contrat HTTP, dégradation, rotation des souvenirs.
Check post-impl: `sh -c 'f=Tests/WidgetDataProviderTests.swift; n=$(grep -c "func test_" $f); test "$n" -ge 3 && grep -q "class WidgetDataProviderTests" $f && echo PASS || echo FAIL'`

### AC-3607 [type: new]
Assertion: le `WidgetBundle` déclare les 3 widgets **et** la Live Activity de backup (le `@main` a quitté `BackupLiveActivity.swift`).
Check post-impl: `sh -c 'f=ImmichWidgets/ImmichWidgetsBundle.swift; grep -q "@main" $f && for w in BackupLiveActivity ImmichHomeWidget ImmichGridWidget ImmichMemoriesWidget ImmichFavoritesWidget; do grep -q "$w" $f || exit 1; done; ! grep -q "@main" ImmichWidgets/BackupLiveActivity.swift && echo PASS || echo FAIL'`

### AC-3608 [type: regression]
Assertion: suite unitaire ≥ baseline (837 mesurée le 2026-09-13) et TEST SUCCEEDED.
Check post-impl: `sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_widgets_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_widgets_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 837 && echo PASS || echo FAIL'`

### AC-3609 [type: new]
Assertion: l'app publie la session widget à chaque entrée en session (login, OAuth, restauration, changement de compte) et l'efface à la déconnexion.
Check post-impl: `sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -q "func publishWidgetSession" $f && test $(grep -c "publishWidgetSession()" $f) -ge 4 && grep -q "widgetSession.clear()" $f && echo PASS || echo FAIL'`

### AC-3610 [type: new]
Assertion: les deux binaires déclarent le **même** groupe Keychain, et l'appex embarque le catalogue de traduction (sans lui, tous les textes du widget restent en anglais).
Check post-impl: `sh -c 'grep -q "keychain-access-groups" Resources/ImmichSwiftUI.entitlements && grep -q "keychain-access-groups" Resources/ImmichWidgets.entitlements && grep -q "CODE_SIGN_ENTITLEMENTS" project.yml && awk "/^  ImmichWidgets:/,/^  ImmichSwiftUITests:/" project.yml | grep -q "Localizable.xcstrings" && echo PASS || echo FAIL'`

### AC-3611 [type: new]
Assertion: les widgets sont interactifs (shuffle d'un souvenir, cœur d'une photo) via des `AppIntent` qui rechargent la bonne timeline.
Check post-impl: `sh -c 'i=Sources/ImmichSharedKit/WidgetIntents.swift; v=Sources/ImmichSharedKit/WidgetViews.swift; grep -q "struct ShuffleMemoriesIntent" $i && grep -q "struct ToggleFavoriteIntent" $i && grep -q "reloadTimelines" $i && grep -q "Button(intent:" $v && echo PASS || echo FAIL'`

## Correctifs du 2026-09-14 (rapport « les photos ne s'affichent pas dans le widget »)

Le symptôme est arrivé par le seul chemin que la livraison du 2026-09-13 n'avait **pas** pu vérifier : le widget dans son propre processus. Une reproduction de bout en bout a été montée (simulateur neuf + stub + connexion OAuth réelle + pose du widget sur l'écran d'accueil via SpringBoard — c'est désormais `UITests/ImmichWidgetHomeScreen.swift`). Constats :

| Constat | Preuve | Correctif |
|---|---|---|
| Le widget **fonctionne** de bout en bout (lecture du Keychain depuis le processus widget, fetch HTTP, décodage, rendu) | widget réel posé sur un écran d'accueil, affichant « 9 photos » + « 9 le 1 juil. » et la vignette servie par le stub | — |
| Le plist de l'appex n'avait **aucune** politique ATS, alors que l'app déclare `NSAllowsArbitraryLoads` | `plutil -p` sur l'appex livré | AC-3612 : même politique dans les deux binaires |
| Le widget fetchait avec `URLSession.shared`, donc **sans gestionnaire de certificat**, là où l'app a `TrustEvaluatingURLSessionDelegate` : un serveur auto-signé accepté dans l'app était injoignable depuis le widget | inspection des deux chemins réseau ; l'app possède tout un flux « faire confiance à ce serveur » qui n'avait aucun équivalent widget | AC-3613 : `WidgetTrustDelegate` + la liste des hôtes acceptés voyage **avec la session** (le widget ne peut pas lire le trust store de l'app, autre conteneur) |
| L'état vide **mentait** : « Pas encore de photos » pour « pas connecté » comme pour « serveur injoignable », et la branche sans session ne loggait rien | lecture du code + reproduction | AC-3614 : `WidgetAvailability` (`.ready` / `.signedOut` / `.unreachable`) porté par `PhotoWall` et `WidgetMemoryFeed`, copie dédiée par cause, log explicite quand la session manque ou quand le Keychain refuse (`-34018`) |

**Diagnostic du rapport utilisateur** : la capture montre, dans la pastille du widget, des **rectangles gris uniformes sans un seul caractère** et un glyphe de bouton réduit à un **blob gris** — la signature du rendu *redacté* du placeholder de WidgetKit, c'est-à-dire un widget qui n'a **jamais reçu de timeline**. La cause mécanique plausible : l'ancien build fetchait avec `URLSession.shared` (timeouts 60 s / 7 jours) ; un serveur injoignable depuis le processus widget consommait tout le budget de WidgetKit, l'entrée n'arrivait jamais et le widget restait sur l'aperçu système. Corrigé par AC-3615 : le widget rend désormais toujours quelque chose — les photos, ou le motif exact de l'échec.

**Ce qui n'a PAS pu être imputé** : la cause exacte du cas de l'utilisateur. Sur le simulateur, **ATS n'est pas appliqué** — une requête HTTP vers un hostname `.local` passe dans le processus widget même *sans* l'exception ATS (contrôle négatif joué : build sans `NSAppTransportSecurity`, widget posé, fetch réussi). L'exception ATS est donc une **parité défensive** (l'app l'a, l'extension doit avoir la même politique), pas une cause prouvée. Sur appareil, ATS est appliqué ; le correctif reste juste, mais la vérification doit se faire sur device.

### AC-3612 [type: new]
Assertion: l'extension déclare la **même** politique de transport que l'app (un serveur Immich auto-hébergé est souvent en HTTP).
Check post-impl: `sh -c 'plutil -p ImmichWidgets/Info.plist | grep -q NSAllowsArbitraryLoads && plutil -p Resources/Info.plist | grep -q NSAllowsArbitraryLoads && echo PASS || echo FAIL'`

### AC-3613 [type: new]
Assertion: le widget évalue la confiance serveur au lieu d'utiliser `URLSession.shared`, et la liste des hôtes acceptés dans l'app voyage avec la session.
Check post-impl: `sh -c 'grep -q "class WidgetTrustDelegate" Sources/ImmichSharedKit/WidgetSession.swift && grep -q "trustedHosts" Sources/ImmichSharedKit/WidgetSession.swift && grep -q "TrustEvaluatingURLSessionDelegate" Sources/Services/TrustEvaluatingURLSessionDelegate.swift && grep -q "trustStore.contains" Sources/Features/Auth/AuthViewModel.swift && echo PASS || echo FAIL'`

### AC-3614 [type: new]
Assertion: un widget vide dit **pourquoi** (déconnecté / serveur injoignable / rien à montrer) et la branche sans session est journalisée.
Check post-impl: `sh -c 'grep -q "enum WidgetAvailability" Sources/ImmichSharedKit/WidgetDataProvider.swift && grep -q "WidgetEmptyCopy" Sources/ImmichSharedKit/WidgetViews.swift && grep -q "Server unreachable" Sources/ImmichSharedKit/WidgetViews.swift && grep -q "no widget session in the keychain" Sources/ImmichSharedKit/WidgetDataProvider.swift && echo PASS || echo FAIL'`

### AC-3615 [type: new]
Assertion: une requête qui n'aboutit pas rend **quand même** une timeline (bornée), et l'échec rejoue vite au lieu d'attendre la période nominale.
Check post-impl: `sh -c 'grep -q "defaultDeadline" Sources/ImmichSharedKit/WidgetDataProvider.swift && grep -q "func bounded" Sources/ImmichSharedKit/WidgetDataProvider.swift && grep -q "availability == .ready ? 30 \* 60 : 5 \* 60" ImmichWidgets/ImmichGridWidget.swift && grep -q "test_aServerThatNeverAnswers_stillYieldsATimeline" Tests/WidgetDataProviderTests.swift && echo PASS || echo FAIL'`

### AC-3616 [type: new]
Assertion: un widget vide **dit lequel** serveur a été interrogé et pourquoi ça a échoué, et une tuile sans octets ne ressemble plus au placeholder redacté du système.
Check post-impl: `sh -c 'grep -q "failureHint" Sources/ImmichSharedKit/WidgetDataProvider.swift && grep -q "func hint(for" Sources/ImmichSharedKit/WidgetDataProvider.swift && grep -q "certificate refused" Sources/ImmichSharedKit/WidgetDataProvider.swift && grep -q "colors: \[widgetBrandStart, widgetBrandEnd\]" Sources/ImmichSharedKit/WidgetViews.swift && grep -q "hint: wall.failureHint" Sources/ImmichSharedKit/WidgetViews.swift && echo PASS || echo FAIL'`

## Résultats (2026-09-13, complétés le 2026-09-14)

| AC | État | Preuve |
|----|------|--------|
| AC-3600 | PASS | 3 fichiers widget + `WidgetPhotosView`/`WidgetMemoriesView`/`WidgetFavoritesView` dans `WidgetViews.swift` |
| AC-3601 | PASS | provider + `WidgetSessionStore` (`afterFirstUnlock`, jamais `whenUnlocked` : un widget d'écran verrouillé rafraîchit appareil verrouillé) |
| AC-3602 | PASS | `PhotosTimelineProvider`, 4 familles système + 2 accessoires ; hero en `size=preview`, cellules en `size=thumbnail` |
| AC-3603 | PASS | pastille année + compteur, bouton shuffle, `widgetURL` → onglet Souvenirs |
| AC-3604 | PASS | watermark au-dessus de la mosaïque (constat de rendu, cf. plus bas) |
| AC-3605 | PASS | `.onOpenURL` dans `AuthenticatedRoot` + 13 tests de parsing (`WidgetDeepLinkTests`) |
| AC-3606 | PASS | 12 tests `WidgetDataProviderTests` (contrat HTTP, 401/500/payload invalide, rotation) |
| AC-3607 | PASS | `@main` unique dans `ImmichWidgetsBundle.swift` |
| AC-3608 | PASS | **869 tests, TEST SUCCEEDED** (`/tmp/immich_widgets_test_summary.txt`), baseline 837 |
| AC-3609 | PASS | `publishWidgetSession()` (login, OAuth, restaurer, changer de compte) + `clear()` ; 2 tests |
| AC-3610 | PASS | entitlements décodés dans les deux binaires livrés (`2MJF39L8VY.fr.millianlmx.immich-ios`) ; `fr.lproj/Localizable.strings` dans l'appex |
| AC-3611 | PASS | `ShuffleMemoriesIntent` (aucun réseau) + `ToggleFavoriteIntent` (`PATCH /api/assets/{id}`, timeout 15 s) |
| AC-3612 | PASS | `NSAllowsArbitraryLoads` désormais dans `ImmichWidgets/Info.plist` comme dans celui de l'app |
| AC-3613 | PASS | `WidgetTrustDelegate` + `trustedHosts` transportés par la session ; test de politique par hôte |
| AC-3614 | PASS | `WidgetAvailability` + copie dédiée par cause ; log explicite quand la session manque ou que le Keychain refuse |
| AC-3615 | PASS | `defaultDeadline` 10 s + helper `bounded` (test : transport qui n'aboutit jamais → `.unreachable`) ; reprise à 5 min (15 min pour les souvenirs) après un échec |
| AC-3616 | PASS | `failureHint` (« nas.local · certificate refused », « … · no answer in 10s », « keychain ») affiché dans l'état vide ; plaques sans octets passées en dégradé de marque **plein** pour ne plus être confondues avec le placeholder redacté d'iOS (vérifié au rendu) |

## Vérification d'exécution

- **Suite unitaire** : 837 → **864 tests, 0 échec**, `TEST SUCCEEDED` (iPhone 17, `-only-testing:ImmichSwiftUITests`).
- **Entitlements livrés** (décodés depuis `__TEXT,__entitlements` des deux binaires — `codesign -d` rend `{}` sur une build simulateur) : app et appex déclarent tous deux `keychain-access-groups = [2MJF39L8VY.fr.millianlmx.immich-ios]`.
- **Catalogue dans l'extension** : `ImmichWidgets.appex/fr.lproj/Localizable.strings` contient les 31 clés neuves (« Pas encore de favoris », « Mélanger les souvenirs », « il y a %lld ans », …).
- **Rendu visuel** : les 10 compositions ont été rasterisées (`ImageRenderer`) puis inspectées — Photos small/medium/large/vide, Souvenirs small/medium, Favoris small/medium/large, ligne Lock Screen. Trois défauts réels ont été trouvés **et corrigés** par cette inspection :
  1. les previews ne déclaraient pas leur famille (`\.widgetFamily` est en lecture seule et vaut autre chose qu'annoncé hors widget) → toutes les familles sont désormais passées explicitement (`family:` sur les 3 vues, argument documenté comme couture de preview) ;
  2. la pastille du widget Favoris était rognée en small (« 12 483 favoris » ne tient pas dans 170 pt) → compteur seul en small + `minimumScaleFactor(0.75)` sur toutes les pastilles ;
  3. le watermark cœur était **invisible** (peint *sous* une mosaïque opaque) → passé en overlay au-dessus des photos.
- **Widget réellement posé sur un écran d'accueil** (2026-09-14) : `UITests/ImmichWidgetHomeScreen.swift` — simulateur neuf, connexion OAuth réelle contre le stub, pose du widget Photos par SpringBoard (édition → galerie → recherche → page « Photos Immich » → « Ajouter le widget »), capture d'écran, puis lecture des logs du processus widget. Deux configurations : `http://127.0.0.1:8421` et `http://<machine>.local:8422` (proxy LAN). Dans les deux cas le widget affiche « 9 photos », « 9 le 1 juil. » et la vignette servie par le stub — donc **lecture du Keychain depuis le processus widget, fetch HTTP, décodage et rendu vérifiés pour de vrai**.
- **Non vérifié** : la platter/marges de WidgetKit et les `Button(intent:)` en conditions réelles (non exercés par la capture), et le comportement **ATS/confiance TLS sur appareil** (le simulateur n'applique pas ATS — contrôle négatif joué).

## Fichiers

- NEW `Sources/ImmichSharedKit/WidgetSession.swift` — session + store Keychain partagé
- NEW `Sources/ImmichSharedKit/WidgetDataProvider.swift` — modèle de rendu + provider (buckets, souvenirs, favoris, vignettes)
- NEW `Sources/ImmichSharedKit/WidgetIntents.swift` — `ShuffleMemoriesIntent`, `ToggleFavoriteIntent`, kinds, store du shuffle
- NEW `Sources/ImmichSharedKit/WidgetViews.swift` — palette, copie localisée, atomes (tuile, pastille, cœur, shuffle, état vide), les 3 compositions + `WidgetPlaceholder`, `WidgetCanvas`, previews
- NEW `Sources/ImmichSharedKit/WidgetDeepLink.swift` — forme d'URL `app.immich://…` (parse + builder)
- NEW `ImmichWidgets/ImmichGridWidget.swift`, `ImmichMemoriesWidget.swift`, `ImmichFavoritesWidget.swift` — déclarations + `TimelineProvider`
- NEW `ImmichWidgets/ImmichWidgetsBundle.swift` — `@main` unique
- EDIT `ImmichWidgets/ImmichHomeWidget.swift` — plaque de lancement à la marque, deep link `backup` (qui ne faisait rien jusqu'ici), SF Symbol au lieu de `Image("AppIcon")` (l'extension n'a pas de catalogue d'assets : l'icône ne s'affichait pas)
- EDIT `ImmichWidgets/BackupLiveActivity.swift` — `@main` retiré
- EDIT `Sources/Features/Auth/AuthViewModel.swift` — `publishWidgetSession()` / `clear()`
- EDIT `Sources/RootView.swift` — `.onOpenURL` → asset (onglet Photos + scroll), `memories`, `backup`
- EDIT `Sources/DependencyContainer.swift`, `project.yml`, `Resources/*.entitlements`, `Resources/Localizable.xcstrings` (31 clés EN+FR)
- NEW `Tests/WidgetDataProviderTests.swift`, `Tests/WidgetDeepLinkTests.swift`
- NEW `UITests/ImmichWidgetHomeScreen.swift` — pose réelle du widget + capture (skip si le stub ne tourne pas ou si l'app n'est pas connectée)
