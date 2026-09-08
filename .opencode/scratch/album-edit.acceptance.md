# Task: album-edit

Status: shipped — AC-1100..AC-1104 PASS 2026-08-12. Suite: 442 tests (440 → +2). Fix: AlbumResponseDto.albumName/description/isActivityEnabled let → var (mock echo updateAlbum applique désormais ces champs — précedent P0 réponse mutable) + MockImmichClient.updateAlbum echo étendu.

## Plan
**Objectif**: Édition d'un album — rename, description, toggle activité (isActivityEnabled). PATCH /api/albums/:id via updateAlbum(id:dto:) déjà câblé mais inutilisé (b1). Entry: menu ellipsis d'AlbumDetailView → sheet.

**Hypothèses**:
- UpdateAlbumDto (DTOs+Album.swift:67): let albumName/description/albumThumbnailAssetId/isActivityEnabled/order — memberwise SANS défauts (setCover passe les 5 args explicitement).
- AlbumDetailViewModel.setCover (:220) prouve le pattern updateAlbum + album = updated.
- AlbumDetailView menu ellipsis branche !selectionMode :165-220 (Select/Shared Links/Shared With/Delete).
- MockImmichClient.updateAlbum :416-425 (lastUpdateAlbumId/lastUpdateAlbumDto/updateAlbumResponse ?? echo cover).

**Approche retenue**: A — EditAlbumSheet (Form: nom, description, toggle activité) + AlbumDetailViewModel.updateAlbumDetails(name:description:isActivityEnabled:) async -> Bool (try-then-mutate album = updated). B: éditer depuis AlbumsView (grid) — hors scope, la grid n'a pas le VM détail. C: inline dans le menu — trop étroit pour 3 champs.

**Étapes**:
1. AlbumDetailViewModel: updateAlbumDetails(name:description:isActivityEnabled:) -> Bool — dto complet (5 args, thumbnail/order nil) → updateAlbum → album = updated; catch errorMessage false.
2. NEW Sources/Features/Albums/EditAlbumSheet.swift: @Bindable vm; @State name/description/activity; Save disabled si name trim vide || saving; Task { ok = await vm.updateAlbumDetails(...) ; si ok dismiss }.
3. AlbumDetailView: menu ellipsis → Button "Edit Album" (pencil) avant Shared Links; @State presentingEditAlbum; .sheet(isPresented:) → EditAlbumSheet(vm:).
4. Tests AlbumsTests.swift +2: updateAlbumDetails_sendsDtoAndUpdatesAlbum (lastUpdateAlbumDto albumName/description/isActivityEnabled + vm.album.albumName remplacé), updateAlbumDetails_failure_keepsAlbum.
5. xcodegen + build + suite → /tmp/immich_album_edit_test_summary.txt.

## Approches candidates
**A (retenue)**: Sheet édition + méthode VM dédiée. DRY, testable.
**B**: Édition dans AlbumsView. Pas de VM détail là-bas; dupliquerait le fetch.
**C**: Alertes inline (rename seulement). Scope incomplet (description + toggle).

### Critères

```
### AC-1100 [type: new]
Assertion: AlbumDetailViewModel expose updateAlbumDetails(name:description:isActivityEnabled:) async -> Bool qui remplace album après succès.
Check post-impl: sh -c 'f=Sources/Features/Albums/AlbumDetailViewModel.swift; grep -qE "func updateAlbumDetails\(name: String\?, description: String\?, isActivityEnabled: Bool\?\) async -> Bool" "$f" && grep -q "album = updated" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1101 [type: new]
Assertion: EditAlbumSheet existe (Form: TextField nom, TextField description, Toggle activité, Save→updateAlbumDetails).
Check post-impl: sh -c 'f=Sources/Features/Albums/EditAlbumSheet.swift; grep -qE "struct EditAlbumSheet" "$f" && grep -qE "Toggle\(\"Activity" "$f" && grep -qE "updateAlbumDetails" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-1102 [type: new]
Assertion: AlbumDetailView: entrée "Edit Album" dans le menu ellipsis + sheet présenté.
Check post-impl: sh -c 'f=Sources/Features/Albums/AlbumDetailView.swift; grep -qE "Edit Album" "$f" && grep -qF "EditAlbumSheet(vm:" "$f" && grep -qE "presentingEditAlbum" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1103 [type: new]
Assertion: Tests updateAlbumDetails — dto envoyé + album remplacé; échec garde l'album (≥2 tests).
Check post-impl: sh -c 'n=$(grep -cE "func test_updateAlbumDetails" Tests/AlbumsTests.swift); test "$n" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1104 [type: regression]
Assertion: Suite complète ≥ 440 tests, 0 échecs.
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_album_edit_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_album_edit_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 440 && echo PASS || echo FAIL'
Pre-state attendu: PASS (440)
Post-state attendu: PASS
```
