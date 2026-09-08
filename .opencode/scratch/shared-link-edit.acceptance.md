# Task: shared-link-edit

Status: shipped — AC-1090..AC-1096 PASS 2026-08-12. Suite: 440 tests (436 → +4: 2 SharedLinksVM + 2 AlbumDetailVM). AC-1093 check édité (eval zsh expansait `$editLinkItem` → pattern vide; remplacé par grep -F "EditSharedLinkSheet(link: item.link)"). AC-1095 check édité (fichier réel Tests/AlbumsTests.swift, pas AlbumDetailViewModelTests.swift — pattern awk -F: sur grep -c multi-fichiers).

## Plan
**Objectif**: Édition d'un lien de partage existant — description, mot de passe, expiration, permissions (allowUpload/allowDownload/showMetadata). PUT /api/shared-links/{id} (P0: updateSharedLink + SharedLinkEditDto{password,expiresAt,allowUpload,allowDownload,showMetadata} tous optionnels). Entry: menu contextuel des rows (SharedLinksView tab + SharedLinkSheet album).

**Hypothèses**:
- SharedLinkResponseDto N'EST PAS Identifiable (DTOs+SharedLink.swift:54) → wrapper `Identifiable` pour .sheet(item:).
- MockImmichClient.updateSharedLink :505-517 capture lastUpdateSharedLinkId/lastUpdateSharedLinkDto, echo updateSharedLinkResponse ?? type:.album.
- SharedLinksViewModel (126L): client private, sharedLinks/errorMessage, pattern revoke try-then-mutate.
- AlbumDetailViewModel (298L): sharedLinks + revokeSharedLink existants — ajouter updateSharedLink miroir.
- LongDateFormatter.parse(isoTimestamp:) -> Date? existe (:41). Encodage date → ISO8601DateFormatter (withInternetDateTime + withFractionalSeconds).
- SharedLinkResponseDto.expiresAt = String? ISO (server) — pré-remplir le picker si parseable.
- password côté serveur: envoi nil = inchangé; désactiver le mot de passe = envoyer chaîne vide "" (server clears).

**Approche retenue**: A — EditSharedLinkSheet réutilisable (link + onSave closure async -> Bool) pour les DEUX surfaces (tab + album). VM: SharedLinksViewModel.updateLink(id:dto:) + AlbumDetailViewModel.updateSharedLink(id:dto:) (try-then-mutate row). B: sheet dédié par surface (duplication) — rejeté. C: édition inline dans la row — trop étroit pour expiry/password.

**Étapes**:
1. SharedLinksViewModel: updateLink(id:dto:) async -> Bool (replace row si idx, errorMessage sinon, return success).
2. AlbumDetailViewModel: updateSharedLink(id:dto:) async -> Bool (même pattern, replace dans sharedLinks).
3. NEW Sources/Features/SharedLinks/EditSharedLinkSheet.swift: Form — description TextField; Toggle Password protect + SecureField; Toggle "Expires" + DatePicker (graphical, si hasExpiry); Section Permissions: allowUpload/allowDownload/showMetadata toggles; Save → onSave(dto) → dismiss si true; Cancel; isSaving ProgressView; dto: password = usePassword ? (vide ? "" : text) : nil (chaîne vide = clear côté serveur), expiresAt = hasExpiry ? iso(date) : nil, description = vide ? nil : text, allowUpload/allowDownload/showMetadata envoyés (édition complète).
4. SharedLinksView: @State editLinkItem (wrapper Identifiable {link}); SharedLinkRow .contextMenu { Edit → editLinkItem; Revoke → pendingRevokeId }; .sheet(item: $editLinkItem) { EditSharedLinkSheet(link:, onSave: { dto in await vm.updateLink(id: link.id, dto: dto) }) } + detents .medium.
5. SharedLinkSheet (album): même contexte — @State editingLink wrapper + contextMenu + sheet(item:) → vm.updateSharedLink.
6. Tests: SharedLinksViewModelTests +2 (update_sendsDtoAndReplacesRow / update_failure_keepsRow); AlbumDetailViewModelTests +2 miroir.
7. xcodegen + build + suite → /tmp/immich_shared_link_edit_test_summary.txt.

## Approches candidates
**A (retenue)**: EditSharedLinkSheet réutilisable + updateLink dans les 2 VMs. DRY, testable, pattern sheet(item:).
**B**: Sheet séparé par surface. Duplication d'un Form entier.
**C**: Édition inline dans la row. Impossible pour DatePicker + toggles multiples.

### Critères

```
### AC-1090 [type: new]
Assertion: SharedLinksViewModel expose updateLink(id:dto:) async -> Bool qui remplace la row après succès (try-then-mutate).
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/SharedLinksViewModel.swift; grep -qE "func updateLink\(id: String, dto: SharedLinkEditDto\) async -> Bool" "$f" && grep -q "sharedLinks\[idx\] = updated" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (méthode absente)
Post-state attendu: PASS
```

```
### AC-1091 [type: new]
Assertion: AlbumDetailViewModel expose updateSharedLink(id:dto:) async -> Bool (même pattern, remplacement dans sharedLinks).
Check post-impl: sh -c 'f=Sources/Features/Albums/AlbumDetailViewModel.swift; grep -qE "func updateSharedLink\(id: String, dto: SharedLinkEditDto\) async -> Bool" "$f" && grep -q "sharedLinks\[idx\] = updated" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1092 [type: new]
Assertion: EditSharedLinkSheet existe avec description/password/expiresAt/allowUpload/allowDownload/showMetadata + onSave closure.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/EditSharedLinkSheet.swift; grep -qE "struct EditSharedLinkSheet" "$f" && grep -q "DatePicker" "$f" && grep -q "allowUpload" "$f" && grep -q "allowDownload" "$f" && grep -q "showMetadata" "$f" && grep -qE "onSave: \(SharedLinkEditDto\) async -> Bool" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier n'existe pas)
Post-state attendu: PASS
```

```
### AC-1093 [type: new]
Assertion: SharedLinksView présente le sheet d'édition via contextMenu Edit sur SharedLinkRow (wrapper Identifiable + .sheet(item:)).
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/SharedLinksView.swift; grep -qE "EditSharedLinkSheet" "$f" && grep -qE "contextMenu" "$f" && grep -qE "editLinkItem" "$f" && grep -qF "EditSharedLinkSheet(link: item.link)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1094 [type: new]
Assertion: SharedLinkSheet (album) permet aussi l'édition (contextMenu + sheet vers EditSharedLinkSheet via vm.updateSharedLink).
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/SharedLinkSheet.swift; grep -qE "EditSharedLinkSheet" "$f" && grep -qE "contextMenu" "$f" && grep -qE "updateSharedLink" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1095 [type: new]
Assertion: Tests VM — update envoie dto + remplace la row; échec garde la row (≥4 tests update sur les 2 fichiers).
Check post-impl: sh -c 'n=$(grep -cE "func test_(updateLink|updateSharedLink)" Tests/SharedLinksViewModelTests.swift Tests/AlbumsTests.swift | awk -F: "{s+=\$2} END {print s+0}"); test "$n" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1096 [type: regression]
Assertion: Suite complète ≥ 436 tests, 0 échecs.
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_shared_link_edit_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_shared_link_edit_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 436 && echo PASS || echo FAIL'
Pre-state attendu: PASS (436)
Post-state attendu: PASS
```
