# Task: archive

Status: shipped — P1 card 5/8. AC-1000..AC-1009 PASS 2026-08-12 (AC-1009 check fixed: max-executed extraction via grep -o on summary file, not sort -n tail).

## Plan

**Objectif**: Archiver / désarchiver des assets depuis la Timeline (mode sélection + menu contextuel + viewer) et depuis le viewer (barre basse). Archive = `visibility: "archive"` sur `PUT /api/assets` — PAS de champ isArchived dans le DTO (P0, AC-804). `isArchived` reste champ réponse READ-ONLY d'AssetResponseDto.

**Hypothèses**:
- `bulkUpdateAssets(dto:)` existe (protocole :116 + impl P0, lastBulkUpdateDto mock:623).
- `AssetBulkUpdateDto{ids + var visibility}` (dto-reference:7, DTOs.swift:222-223): archive exprimé `visibility: .archive`.
- TimelineViewModel expose `selectedIds`/`selectionMode`/`exitSelectionMode()` + pattern try-then-mutate (deleteSelected:48-63).
- PhotoViewer self-contained pattern: callbacks optionnels (onToggleFavorite/onDelete/onRestore/onDeletePermanent + onDataChanged) — fallback client direct + removeAsset + onDataChanged (confirmDelete:752-783).
- photoViewer modifier chain: PhotoViewerPresentation (:35) → extension View (:74) → PhotoViewer struct (:111) → init (:159) — 4 points de passage pour un nouveau callback.
- AssetThumbnailCell: contextMenu non-trash = Favorite + Delete (:67-79), callbacks onToggleFavorite/onDelete; add onArchive optionnel.
- MockImmichClient.bulkUpdateAssets: lastBulkUpdateDto capture + globalError (throw si globalError != nil).
- Tests existants: TimelineViewModelTests.swift (16.2K), TrashViewModelTests.swift. Baseline suite: 361 tests (save-download).
- iOS 26 `.toolbar` selection-mode: bouton archivebox dans ToolbarItemGroup topBarTrailing.

**Approche retenue**: A — 4 surfaces: (1) TimelineViewModel.archiveSelected() + archive(id:) (bulkUpdateAssets visibility .archive, try-then-mutate, remove items+loadedIds, exitSelectionMode si succès); (2) TimelineView toolbar Archive (archivebox) si selectionMode, désactivé si vide; (3) AssetThumbnailCell.onArchive + entrée menu contextuel (branche non-trash); (4) viewer: onArchive callback dans toute la chaîne + bouton archivebox barre basse + fallback self-contained (bulkUpdateAssets + removeAsset + onDataChanged). Pas de filtre timeline "Archived" ici (card favorites-filter couvre le menu de filtres). Pas de dialog de confirmation (action réversible).

**Étapes**:
1. TimelineViewModel: `filterVisibility: String?` (var, nil par défaut) + refresh()/load()/loadNextBucket() passent filterVisibility → client (remplace littéral nil) — réutilisable par le filtre fan de la prochaine card.
2. `archiveSelected() async` — guard non-empty; ids; bulkUpdateAssets(AssetBulkUpdateDto(ids:, visibility: .archive)); succès → items.removeAll{selectedIds.contains} + loadedIds.subtract + exitSelectionMode; catch → errorMessage (garde sélection).
3. `archive(id:) async` — single: bulkUpdateAssets([id]) → remove item + loadedIds.
4. TimelineView toolbarContent: bouton Archive (archivebox) après Add-to-Album, .disabled(selectedIds.isEmpty).
5. AssetThumbnailCell: `var onArchive: (() -> Void)? = nil` + Button Archive dans contextMenu (branche else, avant Delete).
6. TimelineView cellView: onArchive: { Task { await vm.archive(id: item.id) } }.
7. PhotoViewer toute la chaîne + onArchive + bouton barre basse (archivebox, verre, à gauche de Delete) + `private func archive(_ asset:)` self-contained fallback (Task bulkUpdateAssets → onDataChanged?() ; removeAsset(at:)).
8. TimelineView .photoViewer: onArchive: { Task { await vm.archive(id: asset.id) } }.
9. Tests TimelineViewModelTests: test_archive* (selectedIds→dto ids+visibility archive; items/loadedIds nettoyés; selectionMode exit; single archive; échec → errorMessage + items intacts). Tests PhotoViewer non nécessaires (view).
10. Build + suite complète; summary /tmp/immich_archive_test_summary.txt.
11. memory.md + statut card.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Callback onArchive sur toute la chaîne + VM bulkUpdate + fallback viewer. Pattern existant (onDelete/confirmDelete), testable.
**B**: Uniquement toolbar sélection, pas de viewer/context menu. Scope trop étroit vs Flutter (archive doit être accessible partout).
**C**: Filtre timeline Archived AVEC le card. Contamine le scope (le filtre = card dédiée).

### Approche retenue + rationale
**A**. Cohérente (viewer callback chain existante), archive 4 surfaces, try-then-mutate conservé.

### Critères

```
### AC-1000 [type: new]
Assertion: TimelineViewModel.archiveSelected() appelle client.bulkUpdateAssets avec AssetBulkUpdateDto dont ids == Array(selectedIds) et visibility == .archive.
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineViewModel.swift; n=$(grep -c "func archiveSelected" "$f"); grep -q "visibility: .archive" "$f" && test "$n" -ge 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune archiveSelected)
Post-state attendu: PASS
```

```
### AC-1001 [type: new]
Assertion: archiveSelected() nettoie items + loadedIds des ids archivés et quitte le mode sélection uniquement en cas de succès (try-then-mutate).
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineViewModel.swift; grep -q "loadedIds.subtract" "$f" && grep -q "items.removeAll" "$f" && grep -q "exitSelectionMode()" "$f" && grep -q "catch let e {" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1002 [type: new]
Assertion: TimelineViewModel.archive(id:) single-item utilise aussi bulkUpdateAssets (archive d'un asset depuis menu contextuel / viewer callbacks).
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineViewModel.swift; n=$(grep -c "func archive(id:" "$f"); grep -q "bulkUpdateAssets" "$f" && test "$n" -ge 1 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1003 [type: new]
Assertion: AssetThumbnailCell expose onArchive optionnel et l'ajoute au menu contextuel (branche non-trash, avec Delete).
Check post-impl: sh -c 'f=Sources/Features/Timeline/AssetThumbnailCell.swift; grep -q "var onArchive: (() -> Void)? = nil" "$f" && grep -q "onArchive()" "$f" && grep -q "contextMenu" "$f" && grep -q "\"Archive\"" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1004 [type: new]
Assertion: Toolbar Timeline: bouton Archive (systemImage archivebox) visible en mode sélection, désactivé si aucune sélection.
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineView.swift; grep -q "\"archivebox\"" "$f" && grep -q "vm.selectedIds.isEmpty" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1005 [type: new]
Assertion: Chaîne photoViewer complète porte onArchive: PhotoViewerPresentation, extension View, PhotoViewer struct, init.
Check post-impl: sh -c 'n=$(grep -c "onArchive" Sources/Features/PhotoViewer/PhotoViewer.swift); test "$n" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1006 [type: new]
Assertion: PhotoViewer barre basse: bouton archive (archivebox) + fallback self-contained (bulkUpdateAssets → removeAsset + onDataChanged) quand onArchive == nil.
Check post-impl: sh -c 'f=Sources/Features/PhotoViewer/PhotoViewer.swift; grep -q "func archive(_ asset: AssetReactItem)" "$f" && grep -q "bulkUpdateAssets" "$f" && grep -q "removeAsset(at:" "$f" && grep -q "archivebox" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1007 [type: new]
Assertion: TimelineView relie le viewer: onArchive → vm.archive(id:) (in-place grid update).
Check post-impl: sh -c 'f=Sources/Features/Timeline/TimelineView.swift; grep -q "onArchive: { asset in" "$f" && grep -q "vm.archive(id: asset.id)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1008 [type: new]
Assertion: Tests TimelineViewModel couvrent archive: archiveSelected multi (dto ids/visibility), nettoyage items/loadedIds + exitSelectionMode, archive single, échec → errorMessage + items intacts.
Check post-impl: sh -c 'n=$(grep -cE "^[[:space:]]*func test_archive" Tests/TimelineViewModelTests.swift); grep -q "visibility" Tests/TimelineViewModelTests.swift && test "$n" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1009 [type: regression]
Assertion: Suite complète verte, ≥ 361 tests executés (baseline save-download).
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_archive_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_archive_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 361 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```