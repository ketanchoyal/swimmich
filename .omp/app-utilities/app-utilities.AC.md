# Task: app-utilities

Status: planifié

## Plan (résumé)

**Objectif** : rendre lisibles les trois surfaces de diagnostic de l'écart G24 — **App Logs** (journal du
transport, filtrable par niveau, détail copiable, export texte), **Media Stats** (ce que l'appareil et le
serveur contiennent réellement) et **Download Info** (inventaire du cache hors-ligne déjà écrit) — depuis une
section **Advanced** neuve du hub « Me », plus le **troubleshoot d'un asset** (ids, checksum, dates, statut de
sauvegarde, correspondance serveur) atteint depuis le panneau d'infos d'une photo.

**Approche retenue** : A — un tampon circulaire synchrone en mémoire (`AppLogStore`, `NSLock`, sur le modèle de
`BackupLedger`) alimenté par les **deux seuls points de sortie** du transport (`dispatch` et `dispatchUpload`,
les deux seuls appels à `bumpRequestCount()`) via un protocole `AppLogSink` injecté à la construction
d'`ImmichAPIClient`, plus quatre ViewModels `@MainActor @Observable` et des vues stateless poussées depuis
`ProfileView`. Rejetées : B (`os.Logger` — pas de niveau applicatif, pas de champ path/status/duration, pas de
« Clear logs ») et C (décorateur du protocole ≈180 méthodes pour couvrir ce que deux méthodes couvrent déjà, et
tout oubli d'enveloppe serait silencieux).

**Étapes** : (1) NEW `Sources/Core/AppLog/AppLogEntry.swift` ; (2) NEW `Sources/Services/AppLogStore.swift` ;
(3) EDIT `ImmichAPIClient` (deux `log.record`) ; (4-5) NEW `Sources/Features/AppUtilities/*` (9 fichiers) ;
(6) EDIT `DependencyContainer` (le journal est construit **avant** le client) ; (7) EDIT `RootView` +
`ProfileView` (section Advanced, trois lignes) ; (8) EDIT `PhotoInfoPanel` (entrée troubleshoot) ;
(9) NEW `Tests/AppLogStoreTests.swift` + `Tests/ImmichAPIClientLogTests.swift` ; (10) `xcodegen generate` puis
suite complète.

**Incertitudes** : dérivation exacte de `signature` pour `BackupLedger.isBackedUp(id:signature:)` (à reprendre
de `BackupEngine`) ; noms de champs Swift de `AssetBulkUploadCheckRequest` ; compteur d'assets de l'appareil
(exposé par `PhotoLibraryService` ?) — absent plutôt que zéro inventé ; collision possible sur la section
`Advanced` avec les fiches `read-only-mode` / `settings-parity` (y ajouter les lignes plutôt qu'en créer une
seconde).

## Critères

```
### AC-5240 [type: new — le protocole de journal et son injection dans le transport]
Assertion: `AppLogEntry.swift` déclare les trois niveaux (`AppLogLevel`, dont `severe`), l'entrée (`AppLogEntry`), le protocole `AppLogSink` avec `record(_:)` et le défaut `NoopAppLogSink` ; `ImmichAPIClient` retient le puits (`private let log: any AppLogSink`) et l'accepte à la construction avec un défaut qui préserve les appels existants, dont `DependencyContainer.swift:60`.
Check post-impl: sh -c 'f=Sources/Core/AppLog/AppLogEntry.swift; g=Sources/Services/ImmichAPIClient.swift; test -f "$f" && grep -qE "enum AppLogLevel" "$f" && grep -qE "case severe" "$f" && grep -qE "struct AppLogEntry" "$f" && grep -qE "protocol AppLogSink" "$f" && grep -qE "func record" "$f" && grep -qE "struct NoopAppLogSink" "$f" && grep -qE "private let log: any AppLogSink" "$g" && grep -qE "log: any AppLogSink = NoopAppLogSink" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Core/AppLog/AppLogEntry.swift` absent — `grep -rn "AppLog" Sources/` ne renvoie rien ; le transport n'a que `_requestCount` à `Sources/Services/ImmichAPIClient.swift:21`)
Post-state attendu: PASS
```

```
### AC-5241 [type: new — le tampon borné]
Assertion: `AppLogStore` est un `AppLogSink` synchrone et borné : capacité 500 par défaut, `NSLock`, `record` jette le surplus par le bas (`removeFirst`), `snapshot()` rend une copie du plus récent au plus ancien, plus `count()` et `clear()`.
Check post-impl: sh -c 'f=Sources/Services/AppLogStore.swift; test -f "$f" && grep -qE "final class AppLogStore" "$f" && grep -qE "AppLogSink" "$f" && grep -qE "NSLock" "$f" && grep -qE "init\(capacity: Int = 500\)" "$f" && grep -qE "removeFirst" "$f" && grep -qE "func snapshot" "$f" && grep -qE "func count" "$f" && grep -qE "func clear" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Services/AppLogStore.swift` absent)
Post-state attendu: PASS
```

```
### AC-5242 [type: new — les deux points d'instrumentation du transport]
Assertion: `dispatch(_:)` et `dispatchUpload(_:fromFile:)` — les deux seuls chemins d'egress — journalisent chacun, avec les catégories `HTTP` et `Upload`, le chemin seul (`request.url?.path`, jamais la query), le statut, la durée, et un niveau mappé (`warning` en 4xx, `severe` en 5xx ou erreur jetée).
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; n=$(grep -cE "log\.record\(" "$f"); test "$n" -ge 2 && grep -qE "private func dispatch\(_ request: URLRequest\)" "$f" && grep -qE "private func dispatchUpload" "$f" && grep -qE "category: \"HTTP\"" "$f" && grep -qE "category: \"Upload\"" "$f" && grep -qE "path: request.url" "$f" && grep -qE "durationMS:" "$f" && grep -qE "\.warning" "$f" && grep -qE "\.severe" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -c "log.record(" Sources/Services/ImmichAPIClient.swift` = 0 ; les deux méthodes existent mais n'ont que `bumpRequestCount()`, lignes 801-824)
Post-state attendu: PASS
Note: le check vise les DÉCLARATIONS `private func dispatch…` et non le mot seul, et compte les appels plutôt que de supposer leur emplacement (le `catch` de chaque méthode en porte un aussi).
```

```
### AC-5243 [type: new — câblage conteneur + racine]
Assertion: le journal est construit dans `DependencyContainer.init()` **avant** le client, injecté (`ImmichAPIClient(trustStore: trustStore, log: appLog)`), les quatre factories existent, et `RootView` possède les instances de session puis les passe à `ProfileView` et à `PhotoInfoPanel`.
Check post-impl: sh -c 'f=Sources/DependencyContainer.swift; r=Sources/RootView.swift; grep -qE "let appLog = AppLogStore" "$f" && grep -qE "ImmichAPIClient\(trustStore: trustStore, log: appLog\)" "$f" && grep -qE "func makeAppLogViewModel" "$f" && grep -qE "func makeDownloadInfoViewModel\(offline:" "$f" && grep -qE "func makeMediaStatsViewModel\(offline:" "$f" && grep -qE "func makeAssetTroubleshootViewModel" "$f" && grep -qE "makeAppLogViewModel" "$r" && grep -qE "makeDownloadInfoViewModel" "$r" && grep -qE "makeMediaStatsViewModel" "$r" && grep -qE "makeAssetTroubleshootViewModel" "$r" && grep -qE "troubleshoot: troubleshoot" "$r" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`ImmichAPIClient(trustStore: trustStore)` sans `log:` à `Sources/DependencyContainer.swift:60`, aucune factory `makeAppLog*`)
Post-state attendu: PASS
```

```
### AC-5244 [type: new — les trois lignes de la section Advanced du hub « Me »]
Assertion: la section Advanced de `ProfileView` (créée si `read-only-mode` / `settings-parity` ne l'ont pas déjà posée) expose exactement trois lignes — App Logs, Media Stats, Download Info — chacune portant son identifiant sur l'élément interactif, alimentées par des ViewModels d'état de la vue, et **aucune** ligne troubleshooter (la page est paramétrée par l'asset).
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "AppLogView\(vm: appLog\)" "$f" && grep -qE "MediaStatsView\(vm: mediaStats\)" "$f" && grep -qE "DownloadInfoView\(vm: downloadInfo\)" "$f" && grep -qE "appLogsRow" "$f" && grep -qE "mediaStatsRow" "$f" && grep -qE "downloadInfoRow" "$f" && grep -qE "var appLog: AppLogViewModel" "$f" && grep -qE "var mediaStats: MediaStatsViewModel" "$f" && grep -qE "var downloadInfo: DownloadInfoViewModel" "$f" && ! grep -qE "AssetTroubleshootView" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "AppLogs\|MediaStats\|DownloadInfo" Sources/Features/Profile/ProfileView.swift` ne renvoie rien ; sections actuelles : Profil / Servers / Web / Storage / General / Management / Administration / Security)
Post-state attendu: PASS
```

```
### AC-5245 [type: new — les quatre ViewModels délèguent]
Assertion: `Sources/Features/AppUtilities/` porte les quatre ViewModels : `AppLogViewModel` lit `AppLogStore` (filtre niveau + texte, export texte), `DownloadInfoViewModel` projette `OfflineDownloadViewModel` sans re-formater les octets, `MediaStatsViewModel` appelle `getServerStatistics()` et lit le ledger, `AssetTroubleshootViewModel` enchaîne `getAsset` + `bulkUploadCheck` + le miroir hors-ligne + `isBackedUp`.
Check post-impl: sh -c 'd=Sources/Features/AppUtilities; test -f "$d/AppLogViewModel.swift" && test -f "$d/DownloadInfoViewModel.swift" && test -f "$d/MediaStatsViewModel.swift" && test -f "$d/AssetTroubleshootViewModel.swift" && grep -qE "private let store: AppLogStore" "$d/AppLogViewModel.swift" && grep -qE "func exportText" "$d/AppLogViewModel.swift" && grep -qE "private let offline: OfflineDownloadViewModel" "$d/DownloadInfoViewModel.swift" && grep -qE "formattedUsage" "$d/DownloadInfoViewModel.swift" && grep -qE "getServerStatistics" "$d/MediaStatsViewModel.swift" && grep -qE "trackedCount" "$d/MediaStatsViewModel.swift" && grep -qE "OfflineAssetIndex" "$d/AssetTroubleshootViewModel.swift" && grep -qE "bulkUploadCheck" "$d/AssetTroubleshootViewModel.swift" && grep -qE "isBackedUp" "$d/AssetTroubleshootViewModel.swift" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier `Sources/Features/AppUtilities` absent)
Post-state attendu: PASS
Note: aucun ajout au protocole `ImmichClient` n'est attendu — `getAsset`, `bulkUploadCheck` et `getServerStatistics` y sont déjà (AC-5245 ne doit donc pas faire tomber la suite au titre d'un contrat modifié).
```

```
### AC-5246 [type: new — les vues, sans NavigationStack, et l'entrée par asset]
Assertion: les trois vues poussées par le hub sont stateless (`@Bindable var vm`) et ne déclarent **aucun** `NavigationStack`, les écrans d'export/purge portent leurs identifiants, et le troubleshooter d'asset est atteint depuis `PhotoInfoPanel` avec un `NavigationStack` **local à la feuille**.
Check post-impl: sh -c 'd=Sources/Features/AppUtilities; p=Sources/Features/PhotoViewer/PhotoInfoPanel.swift; grep -qE "struct AppLogView: View" "$d/AppLogView.swift" && grep -qE "@Bindable var vm: AppLogViewModel" "$d/AppLogView.swift" && grep -qE "appLogList" "$d/AppLogView.swift" && grep -qE "appLogClearButton" "$d/AppLogView.swift" && grep -qE "struct AppLogDetailView" "$d/AppLogDetailView.swift" && grep -qE "struct DownloadInfoView: View" "$d/DownloadInfoView.swift" && grep -qE "downloadInfoPurgeButton" "$d/DownloadInfoView.swift" && grep -qE "struct MediaStatsView: View" "$d/MediaStatsView.swift" && grep -qE "mediaStatsServerPhotos" "$d/MediaStatsView.swift" && grep -qE "struct AssetTroubleshootView" "$d/AssetTroubleshootView.swift" && grep -qE "assetTroubleshootChecksum" "$d/AssetTroubleshootView.swift" && ! grep -qE "NavigationStack \{" "$d/AppLogView.swift" "$d/DownloadInfoView.swift" "$d/MediaStatsView.swift" && grep -qE "presentTroubleshoot" "$p" && grep -qE "troubleshoot: AssetTroubleshootViewModel" "$p" && grep -qE "AssetTroubleshootView\(vm: troubleshoot, assetID:" "$p" && grep -qE "NavigationStack \{" "$p" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "Troubleshoot" Sources/` ne renvoie rien ; le dossier `Sources/Features/AppUtilities` n'existe pas)
Post-state attendu: PASS
Note: le check négatif vise la forme de déclaration `NavigationStack {` — un `grep` du mot seul échouerait sur le doc-comment qui documente justement l'absence de stack (piège de la carte stacks-ui).
```

```
### AC-5247 [type: new — les tests unitaires du tampon et du transport]
Assertion: `Tests/AppLogStoreTests.swift` couvre l'ordre (plus récent en premier), la borne (510 → 500, plus ancienne jetée), le vidage et la concurrence (100 enregistrements concurrents conservés) ; `Tests/ImmichAPIClientLogTests.swift` injecte un vrai `AppLogStore` dans le client stubé et couvre l'absence de query et d'en-têtes dans l'entrée, plus le 5xx en `severe`.
Check post-impl: sh -c 'a=Tests/AppLogStoreTests.swift; b=Tests/ImmichAPIClientLogTests.swift; test -f "$a" && test -f "$b" && grep -qE "test_record_keepsNewestFirst" "$a" && grep -qE "test_capacity_dropsOldestEntries" "$a" && grep -qE "test_clear_emptiesTheBuffer" "$a" && grep -qE "test_concurrentRecords_doNotLoseEntries" "$a" && grep -qE "test_successfulRequest_isLoggedWithoutQueryNorHeaders" "$b" && grep -qE "test_serverError_isLoggedAsSevere" "$b" && grep -qE "ImmichAPIClient\(trustStore:" "$b" && grep -qE "@testable import ImmichSwiftUI" "$b" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (les deux fichiers de test sont absents)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission (11 sources + 2 fichiers de test ajoutés).
```

```
### AC-5248 [type: new — aucun secret dans le journal]
Assertion: le tampon ne peut pas retenir de secret : `AppLogEntry` n'a de champ que pour le chemin (aucun champ query, en-tête, corps, token ou clé) et la couche qui journalise n'utilise jamais `absoluteString` ni `allHTTPHeaderFields` — la query porte la clé du visiteur de lien partagé (`sendSharedLinkRaw`, `ImmichAPIClient.swift:737-761`) et les en-têtes portent le bearer et le cookie.
Check post-impl: sh -c 'e=Sources/Core/AppLog/AppLogEntry.swift; s=Sources/Services/AppLogStore.swift; v=Sources/Features/AppUtilities/AppLogViewModel.swift; grep -qE "let path: String" "$e" && ! grep -qE "query|header|Header|httpBody|token|Token|apiKey|secret" "$e" && ! grep -qE "absoluteString|allHTTPHeaderFields|httpBody|Bearer|cookie|apiKey" "$s" "$v" && ! grep -qE "absoluteString|allHTTPHeaderFields" Sources/Services/ImmichAPIClient.swift && grep -qE "path: request.url" Sources/Services/ImmichAPIClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Core/AppLog/AppLogEntry.swift` absent)
Post-state attendu: PASS
Note: `httpBody` est légitimement présent dans le transport (encodage des corps, lignes 698 et 756) — c'est pourquoi le check négatif ne le cherche que dans les fichiers du journal et jamais dans `ImmichAPIClient.swift`, et pourquoi il exige en positif que le champ journalisé soit `request.url?.path`.
```

```
### AC-5249 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED, aucun appelant du protocole ni du conteneur cassé par l'ajout du paramètre `log:`.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_apputilities_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_apputilities_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent, et `grep -c "func test_" Tests/*.swift` ne compte aucun cas AppLog/troubleshoot)
Post-state attendu: PASS
```
