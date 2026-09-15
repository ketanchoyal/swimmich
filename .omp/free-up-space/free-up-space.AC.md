# Task: free-up-space

Status: planifié — **aucune AC ouverte** (écart G1 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`, audit 2026-09-15).

## Plan (résumé)

**Objectif** : écran « Free Up Space » ouvert depuis la section Management du hub « Me » : date de coupure
(ou raccourci 30/60/90 j, 1/2/3 ans), conservation des favoris / d'albums (messagerie pré-cochée) / d'une
catégorie de médias, **scan** qui ne retient que les originaux présents **à la fois** sur l'appareil et sur
le serveur, **revue** avec volume récupérable, puis suppression **par lots de 10 000** via la corbeille
système. Les albums iCloud partagés sont écartés d'office. Le serveur n'est **jamais** vidé.

**Approche retenue** : A — un `FreeUpSpaceViewModel` (`@Observable @MainActor`) qui rejoue la logique
upstream en deux temps : le ledger complété par un `bulkUploadCheck` (`serverCheckChunkSize = 100`, même
découpage que `BackupEngine.reconcileLedgerIfDue`) décide **quels** assets sont candidats, une nouvelle
source locale `LocalCleanupSource` (implémentée par extension de `PhotoLibraryServiceImpl`) décide
**lesquels** sont supprimables, et deux vues stateless (réglages + revue) montrent puis exécutent.
**Arbitrage A assumé** : le ledger seul est un cache d'écritures, jamais la vérité serveur (entrée périmée
=> on détruirait la seule copie) ; le contrôle serveur coûte zéro octet de média, les checksums sont déjà
stockés. **B et C rejetées** : B = ledger seul sans confrontation ; C = lecteur `PHAsset` dans le ViewModel
(interdit par la couche `PhotoLibraryService`, et rendrait le scan non testable).

**Étapes** : (1) NEW `Sources/Core/Protocols/LocalCleanupSource.swift` ; (2) EDIT
`Sources/Services/PhotoLibraryServiceImpl.swift` (extension + suppression par lots + exclusion des albums
iCloud partagés) ; (3) NEW `CleanupSettingsStore.swift` ; (4) NEW `FreeUpSpaceViewModel.swift` ; (5) NEW
`FreeUpSpaceView.swift` ; (6) NEW `CleanupReviewView.swift` ; (7) EDIT `DependencyContainer.swift` (une
seule instance `PhotoLibraryServiceImpl` partagée) ; (8) EDIT `RootView.swift` ; (9) EDIT `ProfileView.swift`
(ligne `freeUpSpaceRow` en fin de section Management) ; (10) NEW `Tests/FreeUpSpaceViewModelTests.swift` ;
(11) chaînes extraites au build ; (12) `xcodegen generate` + suite complète.

**Incertitudes** : taille d'un asset sans le charger (`PHAssetResource` n'expose pas `fileSize`) ;
signature exacte de `PHAssetChangeRequest.deleteAssets(_:)` (pontage `NSArray`) ; dialogue système de
suppression Photos qui s'ajoute à notre `confirmationDialog` ; entrées de ledger v1 sans checksum (écartées
du scan, à dire en footer) ; coût du scan sur 50 000 photos (aucune progression).

## Critères

```
### AC-5000 [type: new]
Assertion: le protocole de suppression locale et ses types existent, avec la taille en octets que `BackupCandidate` n'a pas.
Check post-impl: sh -c 'f=Sources/Core/Protocols/LocalCleanupSource.swift; test -f "$f" && grep -qE "struct CleanupCandidate" "$f" && grep -qE "let byteSize: Int64" "$f" && grep -qE "struct CleanupScanResult" "$f" && grep -qE "var reclaimableBytes: Int64" "$f" && grep -qE "enum CleanupKeepMediaType" "$f" && grep -qE "protocol LocalCleanupSource" "$f" && grep -qE "func cleanupCandidates" "$f" && grep -qE "func deleteLocalAssets" "$f" && grep -qE "case none" "$f" && grep -qE "CaseIterable" "$f" && grep -qE "\"Photos\"" "$f" && grep -qE "\"Videos\"" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent : `grep -rn "LocalCleanupSource\|CleanupCandidate" Sources/` ne renvoie rien, aucun dossier `Sources/Features/FreeUpSpace`)
Post-state attendu: PASS
```

```
### AC-5001 [type: new]
Assertion: `PhotoLibraryServiceImpl` sait supprimer un asset de la pellicule (il ne sait aujourd'hui que créer) : extension dédiée, exclusion des albums iCloud partagés, borne de coupure inclusive, suppression par lots de 10 000.
Check post-impl: sh -c 'f=Sources/Services/PhotoLibraryServiceImpl.swift; grep -qE "extension PhotoLibraryServiceImpl: LocalCleanupSource" "$f" && grep -qE "func cleanupCandidates" "$f" && grep -qE "albumCloudShared" "$f" && grep -qE "excludedAssetIDs" "$f" && grep -qE "deleteBatchSize = 10_000" "$f" && grep -qE "PHAssetChangeRequest.deleteAssets" "$f" && grep -qE "performChanges" "$f" && grep -qE "<= cutoff" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (seule extension existante = `PhotoLibraryServiceImpl: BackupAssetSource` ligne 158 ; `PHAssetChangeRequest` n'apparaît que pour les créations lignes 124 et 146 ; `grep -rn "deleteLocalAssets" Sources/Services/` = vide)
Post-state attendu: PASS
Note: le check vise la déclaration de l'extension et l'appel `PHAssetChangeRequest.deleteAssets` — un grep du seul mot `deleteAssets` matcherait le chemin **serveur** (`ImmichClient.deleteAssets`, `ImmichAPIClient.deleteAssets`), hors sujet ici.
```

```
### AC-5002 [type: new — arbitrage A : la confirmation serveur]
Assertion: le scan confronte le ledger au serveur via `bulkUploadCheck` (un « déjà sauvegardé » non confirmé ne supprime rien) et réutilise le découpage en lots de 100 du moteur de sauvegarde.
Check post-impl: sh -c 'f=Sources/Features/FreeUpSpace/FreeUpSpaceViewModel.swift; test -f "$f" && grep -qE "bulkUploadCheck\(" "$f" && grep -qE "entriesForReconciliation\(\)" "$f" && grep -qE "serverCheckChunkSize = 100" "$f" && grep -qE "action == \"reject\"" "$f" && grep -qE "backedUpIDs" "$f" && grep -qE "skippedNotOnServer" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier `Sources/Features/FreeUpSpace` absent ; le seul appel `bulkUploadCheck` du dépôt est celui de `BackupEngine.reconcileLedgerIfDue`, `Sources/Services/BackupEngine.swift:623-633`)
Post-state attendu: PASS
Note: c'est exactement l'arbitrage A de la spec — un scan qui lirait le ledger seul (approche B) laisserait ce check en FAIL, la présence de `bulkUploadCheck` étant la seule preuve que les candidats viennent du serveur et non du cache.
```

```
### AC-5003 [type: new — l'invalidation du scan par les filtres]
Assertion: le ViewModel porte l'état du scan, ses projections, et **vide les candidats à chaque changement de filtre** (on ne supprime jamais sur la foi d'un scan fait avec d'autres filtres).
Check post-impl: sh -c 'f=Sources/Features/FreeUpSpace/FreeUpSpaceViewModel.swift; test -f "$f" && grep -qE "final class FreeUpSpaceViewModel" "$f" && grep -qE "var candidates: \[CleanupCandidate\]" "$f" && grep -qE "var reclaimableBytes: Int64" "$f" && grep -qE "var canScan: Bool" "$f" && grep -qE "var isScanning" "$f" && grep -qE "var errorMessage" "$f" && grep -qE "func setCutoff" "$f" && grep -qE "func toggleKeepAlbum" "$f" && grep -qE "func deleteConfirmed" "$f" && grep -qE "func resetScan" "$f" && n=$(grep -cE "candidates = \[\]|candidates\.removeAll\(\)" "$f"); test "${n:-0}" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: `n >= 4` compte les sites de vidage (scan, cutoff, favoris, catégorie, albums, reset) — la règle `CleanupNotifier` de la spec.
```

```
### AC-5004 [type: new — les réglages persistent et les albums de messagerie ne sont pré-cochés qu'une fois]
Assertion: `CleanupSettingsStore` persiste cutoff / favoris / catégorie / albums, applique les albums de messagerie **une seule fois** (garde `defaultsInitialized`) et purge les albums disparus.
Check post-impl: sh -c 'f=Sources/Features/FreeUpSpace/CleanupSettingsStore.swift; test -f "$f" && grep -qE "final class CleanupSettingsStore" "$f" && grep -qE "var cutoffDate: Date\?" "$f" && grep -qE "var keepFavorites" "$f" && grep -qE "var keepMediaType" "$f" && grep -qE "var keepAlbumIDs: Set<String>" "$f" && grep -qE "defaultsInitialized" "$f" && grep -qE "func applyDefaultKeepAlbums" "$f" && grep -qE "func pruneStaleAlbums" "$f" && grep -qE "whatsapp" "$f" && grep -qE "telegram" "$f" && grep -qE "UserDefaults" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; aucune clé `cleanupKeepAlbumIds` / `cleanupDefaultsInitialized` n'existe dans `Sources/`)
Post-state attendu: PASS
```

```
### AC-5005 [type: new — l'écran de réglages et de scan]
Assertion: `FreeUpSpaceView` rend la coupure (+ raccourcis), les filtres (favoris, catégorie, albums via `AlbumPickerView`), le bouton de scan et le récapitulatif, sans `NavigationStack` propre (elle est poussée depuis le hub « Me »).
Check post-impl: sh -c 'f=Sources/Features/FreeUpSpace/FreeUpSpaceView.swift; test -f "$f" && grep -qE "struct FreeUpSpaceView" "$f" && grep -qE "DatePicker\(" "$f" && grep -qE "AlbumPickerView\(" "$f" && grep -qE "Toggle\(\"Keep favorites\"" "$f" && grep -qE "PVPrimaryButtonStyle" "$f" && grep -qE "InlineErrorBadge" "$f" && grep -qE "navigationTitle" "$f" && grep -qE "StorageStatsViewModel.format" "$f" && ! grep -qE "NavigationStack \{" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check vise la **déclaration** `NavigationStack {` — un grep du seul mot échouerait sur un doc-comment expliquant justement l'absence de stack (piège de la carte stacks-ui, leçon du 2026-09-13).
```

```
### AC-5006 [type: new — entrée du hub et composition root]
Assertion: la ligne « Free Up Space » existe en fin de section Management avec son identifiant d'accessibilité, l'écran est fabriqué par le conteneur, et RootView possède l'instance unique.
Check post-impl: sh -c 'p=Sources/Features/Profile/ProfileView.swift; c=Sources/DependencyContainer.swift; r=Sources/RootView.swift; grep -qE "var freeUpSpace: FreeUpSpaceViewModel" "$p" && grep -qE "FreeUpSpaceView\(vm:" "$p" && grep -qE "freeUpSpaceRow" "$p" && grep -qE "func makeFreeUpSpaceViewModel" "$c" && grep -qE "let cleanupSource: any LocalCleanupSource" "$c" && grep -qE "cleanupSource = photoLibrary" "$c" && grep -qE "freeUpSpace: FreeUpSpaceViewModel" "$r" && grep -qE "makeFreeUpSpaceViewModel" "$r" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dernière ligne de Management = `OfflineStorageView` avec `offlineStorageRow`, `ProfileView.swift:107-112` ; aucune factory `makeFreeUpSpaceViewModel`, aucun `cleanupSource` dans le conteneur)
Post-state attendu: PASS
Note: `cleanupSource = photoLibrary` est l'assertion de la spec « une seule instance `PhotoLibraryServiceImpl` » — deux objets adossés à `PHPhotoLibrary` rendraient le cache d'albums iCloud partagés incohérent d'un écran à l'autre.
```

```
### AC-5007 [type: new — les tests unitaires]
Assertion: `Tests/FreeUpSpaceViewModelTests.swift` couvre le scan (confirmation serveur, découpage en 100, absence de date), l'invalidation par filtre, les albums par défaut, la purge, la suppression et son échec.
Check post-impl: sh -c 'f=Tests/FreeUpSpaceViewModelTests.swift; test -f "$f" && grep -qE "final class FreeUpSpaceViewModelTests" "$f" && grep -qE "MockCleanupSource" "$f" && grep -qE "test_scan_keepsOnlyAssetsTheServerStillHas" "$f" && grep -qE "test_scan_chunksTheServerCheckAtOneHundred" "$f" && grep -qE "test_scan_requiresACutoffDate" "$f" && grep -qE "test_changingAFilter_discardsTheScan" "$f" && grep -qE "test_applyDefaultKeepAlbums_runsOnceAndMatchesMessagingNames" "$f" && grep -qE "test_deleteConfirmed_reportsCountAndClearsCandidates" "$f" && grep -qE "deleteError" "$f" && n=$(grep -cE "func test_" "$f"); test "${n:-0}" -ge 8 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission, et ce check resterait seul juge.
```

```
### AC-5008 [type: new — aucune suppression sans confirmation]
Assertion: le bouton destructif de l'écran de revue ouvre un `confirmationDialog` identifié, et le ViewModel refuse de supprimer quand la liste est vide ; aucune suppression ne part de la vue.
Check post-impl: sh -c 'v=Sources/Features/FreeUpSpace/CleanupReviewView.swift; m=Sources/Features/FreeUpSpace/FreeUpSpaceViewModel.swift; test -f "$v" && grep -qE "confirmationDialog" "$v" && grep -qE "cleanupReviewConfirm" "$v" && grep -qE "role: .destructive" "$v" && grep -qE "vm.deleteConfirmed\(\)" "$v" && grep -qE "guard !candidates.isEmpty" "$m" && n=$(grep -cE "deleteLocalAssets|performChanges" "$v"); test "${n:-1}" -eq 0 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/FreeUpSpace/` absent ; aucun écran du dépôt n'appelle `PHAssetChangeRequest.deleteAssets`)
Post-state attendu: PASS
```

```
### AC-5009 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_freeupspace_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_freeupspace_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "${n:-0}" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
