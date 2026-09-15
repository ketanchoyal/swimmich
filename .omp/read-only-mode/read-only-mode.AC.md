# Task: read-only-mode

Status: planifié — **aucune AC ouverte** (écart G17 du registre `.omp/backlog/ImmichSwiftUI-backlog.md` §2.17).

## Plan (résumé)

**Objectif** : un booléen de réglage d'appareil (mode lecture seule) basculable depuis le hub « Me » et par
appui long sur l'avatar, qui coupe **toute** écriture côté serveur au niveau du client typé — suppressions,
retraits, corbeille, piles, tags, mémoires, activités, admin, partenaires, upload manuel et automatique,
modifications (favori, note, description, nom d'album).

**Approche retenue** : A — NEW `ReadOnlyModeStore` (`@MainActor @Observable`, persisté dans `UserDefaults`)
injecté par l'environnement pour l'UI, **plus** un décorateur `ReadOnlyGuardClient: ImmichClient` posé une
seule fois dans `DependencyContainer`, qui jette `APIError.readOnlyMode` sur les méthodes d'écriture et
relaie les lectures. B (`.disabled` partout dans l'UI) est rejetée : l'inventaire compte des appels au
client **depuis des vues** (`PhotoViewer.swift:781`, `:792`, `:719`, `:742`, `:758` ;
`StackSheet.swift:110`, `:121`, `:132`), des `swipeActions` et des `contextMenu` (`AssetThumbnailCell.swift:99`,
`StackView.swift:42`) — un site oublié ne fait échouer aucun test, il supprime. C (verbe/chemin dans
`sendAuthed`) est rejetée : `POST /api/trash/empty` et `POST /api/trash/restore` partagent le verbe, et une
méthode destructrice neuve ne casserait plus la compilation.

**Étapes** : (1) NEW `Sources/Features/ReadOnly/ReadOnlyModeStore.swift` ; (2) NEW
`Sources/Features/ReadOnly/ReadOnlyGuardClient.swift` ; (3) EDIT `Sources/Core/Types/APIError.swift`
(`case readOnlyMode`) ; (4) EDIT `Sources/DependencyContainer.swift` (store + `guardedClient` donné aux VMs) ;
(5) EDIT `Sources/RootView.swift` (`.environment(readOnly)`, passage à `ProfileView`, appui long sur
`ProfileAvatarButton`) ; (6) EDIT `Sources/Features/Profile/ProfileView.swift` (Toggle dans Security) ;
(7) EDIT `Sources/Features/Upload/UploadViewModel.swift` (refus du run + CTA désactivé) ;
(8) NEW `Tests/ReadOnlyModeTests.swift` ; (9) `xcodegen generate` + suite complète.

## Critères

```
### AC-5170 [type: new — stockage du booléen]
Assertion: ReadOnlyModeStore persiste le réglage sous la clé du réglage upstream (readOnlyModeEnabled), publie l'état après écriture, et offre la lecture non isolée que le décorateur peut appeler depuis une méthode async non isolée.
Check post-impl: sh -c 'f=Sources/Features/ReadOnly/ReadOnlyModeStore.swift; test -f "$f" && grep -qE "@MainActor" "$f" && grep -qE "final class ReadOnlyModeStore" "$f" && grep -qE "defaultsKey" "$f" && grep -qE "readOnlyModeEnabled" "$f" && grep -qE "private\(set\) var isEnabled" "$f" && grep -qE "func setEnabled" "$f" && grep -qE "defaults\.set\(" "$f" && grep -qE "func toggle" "$f" && grep -qE "nonisolated static func isEnabledIn" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier absent : `grep -rn "ReadOnly\|readOnly" Sources/ Tests/` ne renvoie AUCUNE ligne — aucun symbole de mode lecture seule n'existe, le seul store persistant voisin est `BackupSettingsStore` (`UploadViewModel.swift:24`), de type différent)
Post-state attendu: PASS
```

```
### AC-5171 [type: new — la garde est unique et typée, pas dans l'UI]
Assertion: ReadOnlyGuardClient est un décorateur du protocole (il relaie tout et ne peut pas être incomplet) dont au moins les 22 méthodes d'écriture de l'inventaire commencent par assertWritable() : le contrôle est donc absent — levée de APIError.readOnlyMode — pour tout appelant, y compris les 8 sites qui appellent le client depuis une vue.
Check post-impl: sh -c 'f=Sources/Features/ReadOnly/ReadOnlyGuardClient.swift; test -f "$f" && grep -qE "struct ReadOnlyGuardClient: ImmichClient" "$f" && grep -qE "let inner: any ImmichClient" "$f" && grep -qE "func assertWritable" "$f" && grep -qE "APIError.readOnlyMode" "$f" && n=$(grep -cE "try assertWritable\(\)" "$f" | cat) && test "$n" -ge 22 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `Sources/Core/Protocols/ImmichClient.swift` déclare les écritures — `deleteAssets` :49, `emptyTrash` :54, `deleteAlbum` :74, `deleteStack` :230, `deleteAdminUser` :237, `uploadAsset` :264 — et `ImmichAPIClient.swift` les exécute sans aucune garde, ex. `:154` DELETE /api/assets)
Post-state attendu: PASS
Note: le seuil 22 est un plancher — l'inventaire de `ImmichClient.swift` omet des écritures tout aussi destructrices (`restoreTrashAssets` :52 déjà listé, mais aussi `updateAlbumUserRole`, `addUsersToAlbum`, `removeUserFromAlbum`, `tagAssets`, `createAlbum`), qui doivent être classées aussi. Le compilateur garantit que le décorateur implémente TOUT le protocole, pas qu'il classe bien : c'est la seule relecture humaine à faire.
```

```
### AC-5172 [type: new — un seul état, un seul client gardé]
Assertion: le composition root possède le store et le client gardé, et les ViewModels de bibliothèque construits par ses factories ne reçoivent PLUS le client brut (le cast `client as any ImmichClient` disparaît des constructions en une ligne).
Check post-impl: sh -c 'c=Sources/DependencyContainer.swift; r=Sources/RootView.swift; test -f "$c" && grep -qE "let readOnly: ReadOnlyModeStore" "$c" && grep -qE "ReadOnlyGuardClient\(inner:" "$c" && grep -qE "ReadOnlyModeStore\(\)" "$c" && grep -qE "ReadOnlyModeStore.isEnabledIn" "$c" && n=$(grep -cE "ViewModel\(client: client as any ImmichClient\)" "$c" | cat) && test "$n" -eq 0 && grep -qE "environment\(readOnly\)" "$r" && grep -qE "readOnly: readOnly" "$r" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun `readOnly` dans le conteneur ; toutes les factories passent le client brut — `TimelineViewModel(client: client as any ImmichClient)` `:93`, idem :97, :101, :105, :109, :113, :117, :132, :158, :162, :166, :170, :180, :184, :206)
Post-state attendu: PASS
Note: les constructions multilignes (`:72` upload, `:83` AuthViewModel, `:125` SharedLinkViewerViewModel, `:195` RoadTripViewModel) échappent au compteur — la garde de l'upload est vérifiée par AC-5176, et le client du viewer public reste hors périmètre (transport propre, mémoires #22). Vérifier à l'implémentation que le décorateur lit la MÊME instance de `UserDefaults` que le store : `grep -n "UserDefaults" Sources/DependencyContainer.swift` ne renvoie rien aujourd'hui, donc `ReadOnlyModeStore()` et sa lecture statique doivent tomber sur `.standard` toutes les deux.
```

```
### AC-5173 [type: new — famille « assets + corbeille »]
Assertion: les suppressions d'assets et la corbeille (deleteAssets, restoreTrashAssets, restoreAllTrash, emptyTrash) sont couvertes par le test de garde, et la vue PhotoViewer n'appelle plus le client pour supprimer : ses deux appels directs passent par le ViewModel, qui publie l'erreur au lieu de l'avaler.
Check post-impl: sh -c 't=Tests/ReadOnlyModeTests.swift; test -f "$t" && grep -qE "APIError.readOnlyMode" "$t" && grep -qE "requestCount" "$t" && n=$(grep -oE "deleteAssets|restoreTrashAssets|restoreAllTrash|emptyTrash" "$t" | sort -u | wc -l | tr -d " " | cat) && test "$n" -eq 4 && ! grep -qE "client\.(deleteAssets|restoreTrashAssets)" Sources/Features/PhotoViewer/PhotoViewer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (le fichier de test n'existe pas ; PhotoViewer.swift:781 et :792 appellent `client.deleteAssets(ids:force:)` en direct, :758 `client.restoreTrashAssets`)
Post-state attendu: PASS
Note: points d'entrée de la famille couverts par cette garde — Timeline `TimelineView.swift:238`, `:262`, `:546` → `TimelineViewModel.deleteSelected()` `:112` / `delete(id:)` `:346` → client `:117`, `:348` ; `AssetThumbnailCell.swift:99` (`onDeletePermanent`), `:121` (`onDelete`) ; Album `AlbumDetailView.swift:158`, `:309`, `:428` → `deleteSelected()` `:103` ; PhotoViewer `:246`, `:584`, `:781`, `:792` ; Corbeille `TrashView.swift:53`, `:67`, `:243` → `TrashViewModel.deletePermanently(id:)` `:132` / `emptyTrash()` `:148` ; Doublons `DuplicatesView.swift:58`, `:90` → `deleteGroup(id:)` `:43` ; `TrashView.swift:67` → `restoreAllTrash` `:119`, `restoreTrashAssets` `:106`. Tous ces points sont en aval de la couture unique sauf les deux appels du viewer, que le check interdit.
```

```
### AC-5174 [type: new — famille « albums, piles, liens partagés, partenaires »]
Assertion: deleteAlbum, removeAssetsFromAlbum, updateAlbum, deleteSharedLink, deleteStack, removeAssetFromStack, updateStack et removePartner sont couverts par le test de garde, et StackSheet n'appelle plus le client directement (il était le second fichier de vue à contourner tout ViewModel).
Check post-impl: sh -c 't=Tests/ReadOnlyModeTests.swift; test -f "$t" && grep -qE "APIError.readOnlyMode" "$t" && n=$(grep -oE "deleteAlbum|removeAssetsFromAlbum|updateAlbum|deleteSharedLink|deleteStack|removeAssetFromStack|updateStack|removePartner" "$t" | sort -u | wc -l | tr -d " " | cat) && test "$n" -eq 8 && ! grep -qE "client\.(deleteStack|removeAssetFromStack|updateStack)" Sources/Features/PhotoViewer/StackSheet.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (StackSheet.swift:121 `client.removeAssetFromStack`, :132 `client.deleteStack`, :110 `client.updateStack` ; le fichier de test n'existe pas)
Post-state attendu: PASS
Note: points d'entrée de la famille — Album `AlbumDetailView.swift:251`, `:293` → `deleteAlbum()` `:202` ; retrait d'asset `:144`, `:324`, `:428`, `:522` → `removeSelected()`/`removeAssets(ids:)` `:186` ; partage `AlbumShareSheet.swift:54`, `:147` → `revoke(userId:)` ; `AlbumDetailViewModel.deleteSharedLink` `:321` ; liens `SharedLinksViewModel.swift:47` ; piles `StackView.swift:42` (swipe) → `StacksViewModel.deleteStack(id:)` `:110` ; `StackDetailView.swift:64`, `:112`, `:160`, `:179` → `removeAssetFromStack` `:131` ; `StackSheet.swift:86`, `:97`, `:110`, `:121`, `:132` ; partenaires `PartnersViewModel.swift:160` → `client.removePartner(id:)` (`ImmichAPIClient.swift:433`, DELETE /api/partners/{id}) — la liste des partenaires est bloquée même si sa vue n'a pas été relevée ligne à ligne.
```

```
### AC-5175 [type: new — famille « tags, mémoires, activités, admin, modifications »]
Assertion: deleteTag, deleteMemory, deleteActivity, deleteAdminUser, deleteLibrary, deleteAPIKey, updateAsset, updateTag et updateMemory sont couverts par le test de garde, et aucune vue n'appelle ces méthodes : le seul site d'écriture hors ViewModel (le favori et l'archivage du viewer) disparaît.
Check post-impl: sh -c 't=Tests/ReadOnlyModeTests.swift; test -f "$t" && grep -qE "APIError.readOnlyMode" "$t" && n=$(grep -oE "deleteTag|deleteMemory|deleteActivity|deleteAdminUser|deleteLibrary|deleteAPIKey|updateAsset|updateTag|updateMemory" "$t" | sort -u | wc -l | tr -d " " | cat) && test "$n" -eq 9 && ! grep -qE "client\.(updateAsset|bulkUpdateAssets)" Sources/Features/PhotoViewer/PhotoViewer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (PhotoViewer.swift:719 `client.updateAsset` et :742 `client.bulkUpdateAssets` en direct ; le fichier de test n'existe pas)
Post-state attendu: PASS
Note: points d'entrée — tags `TagsViewModel.swift:43` ; mémoires `MemoriesView.swift:121` et `MemoryMomentView.swift:307` → `deleteMemory(id:)` `:150` ; activités `ActivityFeedSheet.swift:34` → `deleteActivity(id:)` `:97` ; admin `AdminView.swift:73`, `:83`, `:234` → `AdminViewModel.deleteUser` `:70`, `deleteLibrary` `:113`, `deleteAPIKey` `:136` ; modifications `AssetDetailViewModel.swift:121`, `:137`, `:157` (favori, description, date), `TimelineViewModel.swift:95`, `:328` (favori), `AlbumDetailViewModel.swift:88` (favori), `MemoriesViewModel.swift:104` (`isSaved`), `TagsViewModel.swift:43` (couleur via `updateTag`), `AlbumDetailViewModel.swift:223`, `:242` (couverture, nom).
```

```
### AC-5176 [type: new — upload manuel et sauvegarde automatique]
Assertion: UploadViewModel refuse le run quand le mode est actif (un seul refus en amont, pas N échecs d'uploadAsset) et son CTA est désactivé ; le conteneur lui passe le store. La garde du décorateur couvre de toute façon uploadAsset et uploadAssetToSharedLink.
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; c=Sources/DependencyContainer.swift; t=Tests/ReadOnlyModeTests.swift; test -f "$t" && grep -qE "test_guardClient_blocksUpload" "$t" && grep -qE "uploadAsset" "$t" && grep -qE "readOnly: ReadOnlyModeStore" "$f" && grep -A8 "func runBackup" "$f" | grep -qE "readOnly" && grep -qE "reportError" "$f" && grep -qE "disabled\(readOnly" "$f" && grep -A8 "self.upload = UploadViewModel[(]" "$c" | grep -qE "readOnly" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "readOnly" Sources/Features/Upload/UploadViewModel.swift` ne renvoie rien ; le seul refus de run est l'accès photothèque — `engine.reportError` `:301` — et `kickOffAutoBackupIfConfigured()` `:378` lance `runBackup(manual: false)` `:381` sans autre contrôle)
Post-state attendu: PASS
Note: la garde posée en tête de `runBackup(overrideSettings:manual:)` (`:298`) couvre les DEUX chemins — le CTA manuel et `container.kickOffAutoBackup()` (`DependencyContainer.swift:142`) qui délègue à `kickOffAutoBackupIfConfigured` : un seul point de refus, à condition qu'il soit dans `runBackup` et non dans la branche `manual`.
```

```
### AC-5177 [type: new — les deux surfaces de bascule d'un même état]
Assertion: le réglage est un Toggle identifié dans ProfileView, relié au store partagé, et l'avatar porte l'appui long 0,5 s qui bascule le même état, avec un badge visible quand le mode est actif ; l'identifiant profileAvatar et le libellé d'accessibilité du bouton sont conservés.
Check post-impl: sh -c 'p=Sources/Features/Profile/ProfileView.swift; r=Sources/RootView.swift; grep -qE "Toggle\(.Read-only Mode." "$p" && grep -qE "readOnlyModeToggle" "$p" && grep -qE "readOnly: ReadOnlyModeStore" "$p" && grep -qE "readOnly.setEnabled" "$p" && grep -qE "@Environment\(ReadOnlyModeStore.self\)" "$r" && grep -qE "onLongPressGesture" "$r" && grep -qE "minimumDuration: 0.5" "$r" && grep -qE "readOnly.toggle\(\)" "$r" && grep -qE "lock.fill" "$r" && grep -qE "profileAvatar" "$r" && grep -qE "accessibilityLabel" "$r" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (ProfileView.swift:132 `Toggle("Require Face ID", ...)` + `appLockToggle` `:136` est le seul réglage de la section Security ; RootView.swift:334-354 `ProfileAvatarButton` est un simple `Button(action:)` avec `.accessibilityLabel("Profile")` `:353` — aucun geste long, aucun badge)
Post-state attendu: PASS
Note: le placement dans Security est délibéré (ProfileView n'a pas de section « Advanced », contrairement au hub de réglages upstream) et le réglage est une préférence d'appareil au même titre que Face ID juste au-dessus. Le tap et l'appui long doivent rester exclusifs : un `Button` avec `.simultaneousGesture(LongPressGesture…)` déclencherait les DEUX (ouverture de la feuille « Me » + bascule) — d'où la paire `.onTapGesture` / `.onLongPressGesture` sur le glyphe, avec `.accessibilityIdentifier("profileAvatar")` sur l'élément interactif (jamais sur un conteneur : l'identifiant écraserait celui des descendants).
```

```
### AC-5178 [type: new — les tests unitaires]
Assertion: ReadOnlyModeTests couvre la persistance du booléen, la bascule, le blocage des familles destructrices (aucun appel enregistré par le mock), le blocage de l'upload et la transparence des lectures et des écritures quand le mode est éteint.
Check post-impl: sh -c 't=Tests/ReadOnlyModeTests.swift; test -f "$t" && n=$(grep -cE "func test_" "$t" | cat) && test "$n" -ge 8 && grep -qE "test_defaultsToDisabled" "$t" && grep -qE "test_setEnabled_persistsAcrossInstances" "$t" && grep -qE "test_toggle_flipsAndPersists" "$t" && grep -qE "test_guardClient_blocksDeletion" "$t" && grep -qE "test_guardClient_blocksUpload" "$t" && grep -qE "test_guardClient_forwardsReadsWhenEnabled" "$t" && grep -qE "test_guardClient_forwardsWritesWhenDisabled" "$t" && grep -qE "requestCount" "$t" && grep -qE "MockImmichClient" "$t" && grep -qE "UserDefaults\(suiteName:" "$t" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — aucun `Tests/*ReadOnly*`)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe verte par omission. L'assertion de non-appel doit porter sur `requestCount` du mock (`Tests/Mocks/MockImmichClient.swift:271` `bump()`, incrémenté par chaque méthode déléguée) ou sur le compteur de l'endpoint (`deleteAlbumCallCount` `:136`, `emptyTrashCallCount` `:96`, `deleteMemoryCallCount` `:204`, `uploads` `:253`), jamais sur le seul type de l'erreur levée.
```

```
### AC-5179 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED — le décorateur relaie tout le protocole, donc une méthode mal relayée casserait les suites existantes des ViewModels.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_readonlymode_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_readonlymode_test.log | grep -oE "[0-9]+" | sort -n | tail -1) && test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
Note: la régénération du projet (`xcodegen generate`) fait partie de la preuve : les deux sources neuves et le fichier de test ne sont compilés qu'après.
```
