# Task: download-panel

Status: planifié — **aucune AC ouverte** (écart G10 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`).

## Plan (résumé)

**Objectif** : une file de téléchargement process-wide, un panneau flottant au-dessus des onglets et un écran
d'information, adossés aux briques existantes (`FileDownloadTransport` pour le streaming disque,
`AssetFileTransfer` pour les noms, `ImmichAPIClient` pour les `URLRequest`) — les fichiers arrivent nommés
comme sur le serveur, dans un dossier que l'utilisateur retrouve, hors du budget du cache hors-ligne.

**Approche retenue** : A — `DownloadQueueViewModel` (`@MainActor @Observable`) construit une seule fois par
`DependencyContainer`, comme `UploadViewModel` ; `DownloadProgressPanel` stateless posé en `overlay` dans
`AuthenticatedRoot` ; `DownloadInfoView` présenté en sheet sous un `NavigationStack` fourni par l'hôte.

**Étapes** : (1) NEW `DownloadItem.swift` ; (2) EDIT `ImmichClient.swift` (3 exigences + `DownloadInfoResponse`) ;
(3) EDIT `ImmichAPIClient.swift` (`POST /download/info`, `GET /assets/{id}/original`, `POST /download/archive`) ;
(4) NEW `DownloadQueueViewModel.swift` ; (5) NEW `DownloadProgressPanel.swift` ; (6) NEW `DownloadInfoView.swift` ;
(7) EDIT `RootView.swift` (`overlay` + sheet) ; (8) EDIT `DependencyContainer.swift` (`makeDownloadQueueViewModel`) ;
(9) EDIT `PhotoViewer.swift` (« Download to Files ») et la feuille de sélection du timeline (« Download ») ;
(10) NEW `Tests/DownloadQueueViewModelTests.swift` ; (11) `xcodegen generate` + suite complète.

**Incertitudes** : session de fond vs premier plan (l'upstream utilise `background_downloader` ; notre
`URLSessionFileDownloadTransport` prend `.shared` — trancher explicitement) ; destination durable
(`Documents/Downloads/` vs `ShareLink`/`fileExporter`) ; disponibilité de `originalFileName` sur `AssetReactItem` ;
convention d'`archiveName` reprise du mobile.

## Critères

```
### AC-5090 [type: new]
Assertion: le contrat de téléchargement traverse les deux couches — les trois exigences et la valeur de retour du lot sont déclarées sur `ImmichClient`, et `ImmichAPIClient` les réalise sur les chemins réels de l'OpenAPI (`POST /download/info` — obligatoire, puis `POST /download/archive` ; `GET /assets/{id}/original` pour le mono-asset), via le constructeur de requêtes qui pose l'en-tête Bearer.
Check post-impl: sh -c 'p=Sources/Core/Protocols/ImmichClient.swift; c=Sources/Services/ImmichAPIClient.swift; grep -qE "func downloadInfo\(assetIds:" "$p" && grep -qE "func originalRequest\(assetId:" "$p" && grep -qE "func downloadArchiveRequest\(archiveName:" "$p" && grep -qE "struct DownloadInfoResponse" "$p" && grep -qE "let totalSize: Int64" "$p" && grep -qE "let size: Int64" "$p" && grep -qE "\"download/info\"" "$c" && grep -qE "\"download/archive\"" "$c" && grep -qE "/original\"" "$c" && grep -qE "func downloadInfo\(" "$c" && grep -qE "func originalRequest\(" "$c" && grep -qE "func downloadArchiveRequest\(" "$c" && grep -qE "private func baseRequest\(" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune méthode de téléchargement sur le protocole — `grep -rn "func .*[Dd]ownload" Sources/Core/Protocols/ImmichClient.swift` est vide — et aucun chemin `download` dans le client ; le viewer passe par `AssetFileTransfer.fetchData`, le cache hors-ligne par un `URLRequest` + transport)
Post-state attendu: PASS
Note: le découpage est délibéré — le client **construit** les requêtes, le transport les exécute ; y faire entrer un `Data` de ZIP contredirait le streaming disque de `URLSessionFileDownloadTransport`. Les greps visent les **littéraux** (`"download/info"` entre guillemets), pour qu'un doc-comment citant `POST /download/info` ne puisse pas satisfaire le check.
```

```
### AC-5091 [type: new]
Assertion: les types de la file existent — statuts utiles, une ligne clée par asset avec nom/fraction/statut, `progress` à `nil` quand le serveur n'a pas donné de `Content-Length`, et la taille mise en forme par `ByteCountFormatter` (pas une seconde mise en forme maison).
Check post-impl: sh -c 'f=Sources/Features/DownloadPanel/DownloadItem.swift; test -f "$f" && grep -qE "enum DownloadStatus" "$f" && grep -qE "case cancelled" "$f" && grep -qE "struct DownloadItem" "$f" && grep -qE "let assetId: String" "$f" && grep -qE "let fileName: String" "$f" && grep -qE "var receivedBytes: Int64" "$f" && grep -qE "var progress: Double" "$f" && grep -qE "ByteCountFormatter" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun dossier `Sources/Features/DownloadPanel` : `ls` renvoie « No such file or directory »)
Post-state attendu: PASS
```

```
### AC-5092 [type: new]
Assertion: le ViewModel de file est construit par injection (`client`, `transport`, `fileManager`), expose ses projections **calculées** (jamais un compteur à maintenir) et l'accès par asset aux noms du VM hors-ligne.
Check post-impl: sh -c 'f=Sources/Features/DownloadPanel/DownloadQueueViewModel.swift; test -f "$f" && grep -qE "final class DownloadQueueViewModel" "$f" && grep -qE "transport: any FileDownloadTransport" "$f" && grep -qE "var isPanelVisible" "$f" && grep -qE "var aggregateProgress" "$f" && grep -qE "var formattedAggregateSize" "$f" && grep -qE "func progress\(for assetId:" "$f" && grep -qE "func status\(for assetId:" "$f" && grep -qE "func enqueue\(assets:" "$f" && grep -qE "func cancel\(assetId:" "$f" && grep -qE "func retry\(assetId:" "$f" && grep -qE "func clearCompleted\(" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `grep -rn "DownloadState\|downloadState\|taskProgress" Sources/` ne renvoie rien)
Post-state attendu: PASS
```

```
### AC-5093 [type: new]
Assertion: la marche d'une entrée tient le contrat de la spec — `downloadInfo` **avant** toute requête d'archive quand la demande porte plus d'un asset, streaming par le transport, nom du fichier repris du serveur via `AssetFileTransfer.baseName`, destination renseignée, et échec d'une ligne sans interruption de la file.
Check post-impl: sh -c 'f=Sources/Features/DownloadPanel/DownloadQueueViewModel.swift; grep -qE "client.downloadInfo\(" "$f" && grep -qE "transport.download\(" "$f" && grep -qE "baseName\(originalName:" "$f" && grep -qE "status = .failed" "$f" && grep -qE "errorMessage =" "$f" && grep -qE "destinationURL =" "$f" && a=$(grep -nE "client.downloadInfo\(" "$f" | cut -d: -f1); b=$(grep -nE "downloadArchiveRequest\(" "$f" | cut -d: -f1); test -n "$a" && test -n "$b" && test "$a" -lt "$b" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: la comparaison de numéros de ligne encode le contrat serveur (« assets must have been previously requested via the getDownloadInfo endpoint ») — sans elle, un appel d'info oublié passerait inaperçu au test comme au grep.
```

```
### AC-5094 [type: new]
Assertion: le panneau flottant est une vue **sans état** qui projette le VM, ne contient qu'un seul contrôle interactif (`Button(action: onOpenInfo)` — pas de bouton imbriqué dans un bouton) et porte ses trois identifiants.
Check post-impl: sh -c 'f=Sources/Features/DownloadPanel/DownloadProgressPanel.swift; test -f "$f" && grep -qE "struct DownloadProgressPanel" "$f" && grep -qE "let onOpenInfo: \(\) -> Void" "$f" && grep -qE "Button\(action: onOpenInfo\)" "$f" && grep -qE "downloadPanelSummary" "$f" && grep -qE "downloadPanelProgress" "$f" && grep -qE "ultraThinMaterial" "$f" && grep -qE "Capsule\(\)" "$f" && grep -qE "PVSpacing.s12" "$f" && ! grep -qE "@State" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: un `Button` imbriqué dans un `Button` est un piège mesuré du dépôt (`AssetThumbnailCell` dans un `Button`, mémo `03f1558c`) — l'action « ouvrir l'écran d'information » appartient au panneau entier.
```

```
### AC-5095 [type: new]
Assertion: l'écran d'information est un contenu présenté par l'hôte — il déclare **son propre** `NavigationStack` absent, ses sections par statut, son en-tête agrégé et ses actions `Clear completed` / `Done`, avec les identifiants de ligne et d'action.
Check post-impl: sh -c 'f=Sources/Features/DownloadPanel/DownloadInfoView.swift; test -f "$f" && grep -qE "struct DownloadInfoView" "$f" && grep -qE "@Bindable var vm: DownloadQueueViewModel" "$f" && grep -qE "@Environment\(\\\\.dismiss\)" "$f" && grep -qE "downloadInfoSummary" "$f" && grep -qE "downloadInfoRow_" "$f" && grep -qE "downloadInfoClearCompleted" "$f" && grep -qE "Clear completed" "$f" && grep -qE "navigationTitle\(\"Downloads\"\)" "$f" && grep -qE "ProgressView" "$f" && ! grep -qE "NavigationStack \{" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check vise la **déclaration** (`NavigationStack {`) — un grep du seul mot échouerait sur le doc-comment qui explique justement l'absence de pile (même piège que la carte stacks-ui, mémo `7d2c7eab`).
```

```
### AC-5096 [type: new]
Assertion: `AuthenticatedRoot` héberge le panneau (`overlay(alignment: .bottom)`, conditionné par `isPanelVisible`) et l'écran d'information (`sheet` > `NavigationStack` > `DownloadInfoView`), et l'instance unique vient du composition root (`DependencyContainer`), pas de la vue.
Check post-impl: sh -c 'a=Sources/RootView.swift; b=Sources/DependencyContainer.swift; grep -qE "overlay\(alignment: .bottom\)" "$a" && grep -qE "DownloadProgressPanel\(vm:" "$a" && grep -qE "showDownloadInfo" "$a" && grep -qE "NavigationStack \{ DownloadInfoView\(vm:" "$a" && grep -qE "func makeDownloadQueueViewModel" "$b" && grep -qE "DownloadQueueViewModel\(client:" "$b" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun `DownloadQueueViewModel`, aucun `DownloadProgressPanel` ; le seul overlay global connu est `LockView`, `RootView.swift:273`)
Post-state attendu: PASS
```

```
### AC-5097 [type: new]
Assertion: les deux points d'entrée appellent la file — le viewer propose « Download to Files » à côté de « Download original » (qui reste, lui, le chemin vers Photos), et l'action de sélection de masse passe la sélection entière au VM sans en instancier un.
Check post-impl: sh -c 'a=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -qE "downloads.enqueue\(asset: asset" "$a" && grep -qE "Download to Files" "$a" && grep -qE "downloadToFilesButton" "$a" && grep -qE "downloadOriginal\(\)" "$a" && grep -qE "let downloads: DownloadQueueViewModel" "$a" && grep -qE "enqueue\(assets:" -r Sources/Features/Timeline Sources/Features/Albums && ! grep -qE "DownloadQueueViewModel\(" -r Sources/Features/Timeline Sources/Features/Albums && echo PASS || echo FAIL'
Pre-state attendu: FAIL (le seul bouton de téléchargement du viewer est `downloadForOfflineButton`, `PhotoViewer.swift:1257`, qui écrit dans le cache sous un nom dérivé de l'id d'asset)
Post-state attendu: PASS
Note: la négation sur `Sources/Features/Timeline` + `Sources/Features/Albums` encode l'anti-piège « pas d'instanciation de VM dans une vue » : le VM arrive par le même chemin que les autres dépendances de la feuille de sélection (dont le détenteur de `selectedIds` peut vivre dans l'une ou l'autre).
```

```
### AC-5098 [type: new]
Assertion: `Tests/DownloadQueueViewModelTests.swift` existe avec un faux `FileDownloadTransport` et ≥ 8 cas, exerçant l'API du VM (file mono-asset, lot, échec isolé, annulation, nettoyage des terminés, visibilité du panneau).
Check post-impl: sh -c 'f=Tests/DownloadQueueViewModelTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 8 && grep -qE "FileDownloadTransport" "$f" && grep -qE "enqueue\(assets:" "$f" && grep -qE "cancel\(assetId:" "$f" && grep -qE "clearCompleted\(\)" "$f" && grep -qE "isPanelVisible" "$f" && grep -qE "downloadInfo" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `Tests/` ne contient aucune suite de file de téléchargement)
Post-state attendu: PASS
Note: un `Tests/*.swift` n'est compilé ni exécuté qu'après `xcodegen generate` (étape 11) — sans régénération la suite reste « verte » par omission.
```

```
### AC-5099 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_downloadpanel_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_downloadpanel_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log `/tmp/immich_downloadpanel_test.log` absent — la suite n'a pas encore été relancée avec les nouveaux fichiers)
Post-state attendu: PASS
```
