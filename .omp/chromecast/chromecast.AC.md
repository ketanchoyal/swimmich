# Task: chromecast

Status: planifié — **aucune AC ouverte** (écart G9 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`).
**Approche retenue par la spec : AirPlay natif** (`AVRoutePickerView` + `AVRouteDetector` +
`AVAudioSession.routeChangeNotification`) derrière la couture `CastService`. L'option Google Cast SDK est
**hors périmètre et conditionnée** : aucune AC ci-dessous ne présume un `GoogleCastService`, un
`GCKCastContext`, un receiver application ID, une clé `Info.plist` du SDK, ni un appel à `POST /api/sessions` —
ces trois préalables sont hors dépôt (SDK non distribué en SPM, dépôt sans `Podfile`, route de session non
consommée). La spec a tranché : livrer AirPlay, dimensionner la couture pour l'autre.

## Plan (résumé)

**Objectif** : depuis le viewer plein écran, une feuille « Cast » envoie la vidéo en cours vers un écran externe
via le sélecteur de route système AirPlay, sans quitter la photo ; la coiffe du viewer porte l'état « en cours de
diffusion », et la feuille dit honnêtement qu'AirPlay ne transporte pas d'image fixe.

**Approche retenue** : C — un protocole `CastService` comme couture (`Sources/Core/Protocols/`, sur le modèle de
`VideoPlaybackEngine.swift:20`) et **une seule implémentation livrée**, `AirPlayCastService`. Le fork est réel :
en AirPlay le téléphone reste le client HTTP (le Bearer de `AVVideoPlaybackEngine.swift:37` continue de
fonctionner), en Cast c'est le récepteur qui télécharge, ce qui exige une session serveur absente du dépôt. Et
`supportsStillImages` vaut `false` en AirPlay, `true` en Cast.

**Étapes** : (1) NEW `Sources/Core/Protocols/CastService.swift` ; (2) NEW `Sources/Services/AirPlayCastService.swift` ;
(3) NEW `Sources/Features/Cast/CastViewModel.swift` ; (4) NEW `Sources/Features/Cast/RoutePickerView.swift` ;
(5) NEW `Sources/Features/Cast/CastSheet.swift` ; (6) EDIT `Sources/Services/AVVideoPlaybackEngine.swift`
(`allowsExternalPlayback`) ; (7) EDIT `Sources/DependencyContainer.swift` (`castService` + `makeCastViewModel`) ;
(8) EDIT `Sources/Features/PhotoViewer/PhotoViewer.swift` (pastille de coiffe + feuille) ; (9) NEW
`Tests/Mocks/MockCastService.swift` + `Tests/CastViewModelTests.swift` ; (10) chaînes (aucune écriture manuelle
dans `Resources/Localizable.xcstrings`) ; (11) `xcodegen generate` + suite complète.

**Incertitudes** : routage effectif de l'`AVPlayer` du viewer sans `AVPlayerViewController` plein écran (à
constater sur appareil — le simulateur ne signale aucune route) ; `AVAudioSession.Port.airPlay` comme seule
source de vérité de l'état connecté ; stabilité de la pastille sur les `routeChangeNotification` d'écouteurs ;
glyphe `airplayvideo` (SF Symbols n'a pas de Chromecast).

## Critères

```
### AC-5080 [type: new]
Assertion: la couture `CastService` existe comme protocole d'infrastructure `@MainActor` et déclare exactement les six membres de la spec — détection, connexion, nom de route, capacité d'image fixe, et le cycle d'observation — sans importer AVKit ni AVFoundation (l'abstraction ne fuit pas le framework système qu'elle recouvre).
Check post-impl: sh -c 'f=Sources/Core/Protocols/CastService.swift; test -f "$f" && grep -qE "@MainActor protocol CastService" "$f" && grep -qE "var isAvailable: Bool" "$f" && grep -qE "var isConnected: Bool" "$f" && grep -qE "var connectedRouteName: String\?" "$f" && grep -qE "var supportsStillImages: Bool" "$f" && grep -qE "func startObserving\(\)" "$f" && grep -qE "func stopObserving\(\)" "$f" && grep -qE "^import Foundation" "$f" && ! grep -qE "^import AVKit|^import AVFoundation" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent : `grep -rn "CastService" Sources/ Tests/ project.yml` → 0 résultat, et `Sources/Core/Protocols/` ne contient aucun `CastService.swift`)
Post-state attendu: PASS
```

```
### AC-5081 [type: new]
Assertion: `AirPlayCastService` est l'unique implémentation livrée et elle l'est en AirPlay natif : `AVRouteDetector`, les deux notifications `routeChangeNotification` / `mediaServicesWereResetNotification`, `routeDetectionEnabled`, le port `.airPlay` de `AVAudioSession.currentRoute.outputs` comme source de l'état connecté, et `supportsStillImages = false` écrit noir sur blanc.
Check post-impl: sh -c 'f=Sources/Services/AirPlayCastService.swift; test -f "$f" && grep -qE "final class AirPlayCastService: CastService" "$f" && grep -qE "AVRouteDetector\(\)" "$f" && grep -qE "routeChangeNotification" "$f" && grep -qE "mediaServicesWereResetNotification" "$f" && grep -qE "routeDetectionEnabled = true" "$f" && grep -qE "portType == .airPlay" "$f" && grep -qE "let supportsStillImages = false" "$f" && grep -qE "func refresh" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `grep -rn "AVRouteDetector\|AVRoutePickerView\|allowsExternalPlayback\|GCKCastContext\|CC1AD845" Sources/ Tests/ project.yml Resources/` → 0 résultat)
Post-state attendu: PASS
```

```
### AC-5082 [type: new]
Assertion: `CastViewModel` ne fait que projeter le service (aucun état dupliqué à resynchroniser), porte l'asymétrie photo/vidéo dans `canCast(_:)` et délègue le cycle d'observation — sans toucher lui-même à AVFoundation ni à AVKit.
Check post-impl: sh -c 'f=Sources/Features/Cast/CastViewModel.swift; test -f "$f" && grep -qE "@MainActor @Observable final class CastViewModel" "$f" && grep -qE "private let service: any CastService" "$f" && grep -qE "init\(service: any CastService\)" "$f" && grep -qE "var statusText: String\?" "$f" && grep -qE "func canCast" "$f" && grep -qE "asset.isVideo \|\| service.supportsStillImages" "$f" && grep -qE "func onAppear" "$f" && grep -qE "func onDisappear" "$f" && grep -qE "startObserving\(\)" "$f" && grep -qE "stopObserving\(\)" "$f" && ! grep -qE "AVAudioSession|AVRouteDetector|^import AVFoundation|^import AVKit" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier `Sources/Features/Cast/` inexistant)
Post-state attendu: PASS
Note: `asset.isVideo` existe bien (`Sources/Core/Types/AssetReactItem.swift:44` : `var isVideo: Bool { !isImage }`) — pas de faux critère sur un symbole absent.
```

```
### AC-5083 [type: new]
Assertion: le sélecteur de route est le seul pont UIKit de la feature — un `UIViewRepresentable` qui rend une `AVRoutePickerView` configurée pour les appareils vidéo, et non un composant maison ou une liste de destinations dessinée à la main.
Check post-impl: sh -c 'f=Sources/Features/Cast/RoutePickerView.swift; test -f "$f" && grep -qE "struct RoutePickerView: UIViewRepresentable" "$f" && grep -qE "AVRoutePickerView" "$f" && grep -qE "prioritizesVideoDevices = true" "$f" && grep -qE "activeTintColor" "$f" && grep -qE "^import AVKit" "$f" && grep -qE "func makeUIView" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-5084 [type: new]
Assertion: la feuille porte ses trois surfaces identifiables — la ligne de statut, le sélecteur et le message honnête sur l'image fixe — plus la chaîne d'état vide, et ne déclare AUCUN `NavigationStack` (c'est une feuille du viewer, pas une vue poussée depuis le hub « Me »).
Check post-impl: sh -c 'f=Sources/Features/Cast/CastSheet.swift; test -f "$f" && grep -qE "struct CastSheet: View" "$f" && grep -qE "let asset: AssetReactItem" "$f" && grep -qE "let service: any CastService" "$f" && grep -qE "@State private var vm: CastViewModel" "$f" && grep -qE "castStatusRow" "$f" && grep -qE "castRoutePicker" "$f" && grep -qE "castImageHint" "$f" && grep -qE "No external screen connected" "$f" && grep -qE "AirPlay cannot send a still photo\. Use Screen Mirroring from Control Center\." "$f" && grep -qE "presentationDetents" "$f" && ! grep -qE "NavigationStack \{" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION (`NavigationStack {`) — le doc-comment de la feuille explique justement l'absence de stack ; un grep du seul mot échouerait (piège déjà rencontré sur la carte stacks-ui).
```

```
### AC-5085 [type: new — le flux vidéo est autorisé à sortir]
Assertion: `AVVideoPlaybackEngine.prepare(url:token:)` pose explicitement les deux propriétés qui autorisent la sortie externe du flux — aujourd'hui absentes du dépôt, leur absence laisserait le cast silencieusement dépendant du comportement par défaut d'AVFoundation.
Check post-impl: sh -c 'f=Sources/Services/AVVideoPlaybackEngine.swift; grep -qE "allowsExternalPlayback = true" "$f" && grep -qE "usesExternalPlaybackWhileExternalScreenIsActive = true" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "allowsExternalPlayback" Sources/` → 0 résultat ; fichier de 118 lignes)
Post-state attendu: PASS
```

```
### AC-5086 [type: new — une seule observation pour tout le processus]
Assertion: le composition root possède l'unique `AirPlayCastService` (propriété du conteneur, comme `offlineStore` et `upload`), démarre son observation dans l'`init`, et expose la fabrique `makeCastViewModel` — la vue ne construit ni le service ni le ViewModel.
Check post-impl: sh -c 'f=Sources/DependencyContainer.swift; grep -qE "let castService: any CastService" "$f" && grep -qE "AirPlayCastService\(\)" "$f" && grep -qE "castService.startObserving\(\)" "$f" && grep -qE "func makeCastViewModel" "$f" && grep -qE "asset: AssetReactItem" "$f" && grep -qE "CastViewModel\(service:" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "castService\|makeCastViewModel" Sources/` → 0 résultat ; `DependencyContainer.swift` fait 235 lignes)
Post-state attendu: PASS
```

```
### AC-5087 [type: new]
Assertion: la coiffe du viewer porte la pastille de cast (icône `airplayvideo`, variante `airplayvideo.circle.fill` quand un écran est connecté, désactivée hors disponibilité) et attache la feuille à l'asset courant ; le paramètre est défaut-valué sur le conteneur aux DEUX endroits — le modifier `photoViewer(` et la vue — pour que les appelants existants n'aient rien à changer.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -qE "viewerCastButton" "$f" && grep -qE "airplayvideo.circle.fill" "$f" && grep -qE "disabled\(!castService.isAvailable\)" "$f" && grep -qE "CastSheet\(" "$f" && grep -qE "sheet\(isPresented: .showCastSheet\)" "$f" && n=0 && n=$(grep -cE "var castService: any CastService = DependencyContainer.shared.castService" "$f") && test "$n" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "airplayvideo\|viewerCastButton\|castService" Sources/` → 0 résultat)
Post-state attendu: PASS
```

```
### AC-5088 [type: new — la partie testable est testée]
Assertion: le mock de la couture et les sept cas du ViewModel existent, dont celui qui décrit le comportement d'un futur service capable d'envoyer une image fixe et celui qui n'exerce que l'implémentation réelle `AirPlayCastService` (le seul cas possible sans écran externe).
Check post-impl: sh -c 'm=Tests/Mocks/MockCastService.swift; t=Tests/CastViewModelTests.swift; test -f "$m" && test -f "$t" && grep -qE "final class MockCastService: CastService" "$m" && grep -qE "var supportsStillImages" "$m" && grep -qE "startObservingCount" "$m" && grep -qE "stopObservingCount" "$m" && grep -qE "class CastViewModelTests" "$t" && n=0 && n=$(grep -cE "func test_" "$t") && test "$n" -ge 7 && grep -qE "test_canCast_isTrueForVideo_whenServiceCannotCastImages" "$t" && grep -qE "test_canCast_isFalseForStill_whenServiceCannotCastImages" "$t" && grep -qE "test_canCast_isTrueForStill_whenServiceCastsImages" "$t" && grep -qE "test_statusText_isNil_whenDisconnected" "$t" && grep -qE "test_statusText_surfacesConnectedRouteName" "$t" && grep -qE "test_airPlayService_declaresNoStillImageSupport" "$t" && grep -qE "test_onAppear_delegatesToStartObserving" "$t" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Tests/Mocks/` existe mais ne contient aucun `MockCastService.swift` ; `Tests/CastViewModelTests.swift` absent)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission.
```

```
### AC-5089 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED — cinq fichiers source, un mock et un fichier de test ajoutés ne doivent rien casser.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_chromecast_test.log && n=0 && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_chromecast_test.log | grep -oE "[0-9]+" | sort -n | tail -1) && test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
