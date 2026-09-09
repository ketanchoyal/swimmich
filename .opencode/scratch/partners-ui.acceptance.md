# Task: partners-ui

Status: plan

## Plan

**Objectif**: Ajouter l'interface complète de partner sharing. Client API existant (`getPartners`, `updatePartner`, `removePartner`) mais `POST /api/partners` (création) manque + pas d'écran dédié.

**Hypothèses** (ground truth vérifié):
- `PartnerResponseDto{…}` + `PartnerUpdateDto{inTimeline}` dans DTOs+People.swift.
- `getPartners()` wire dans ImmichClient.
- `getUsers()` wire pour le user picker.
- `SharedLinksView` a déjà `PartnerRow` + `PartnerAvatarCircle`.
- `TimelineViewModel` supporte `withPartners: Bool?`.

**Approche retenue**: A — `createPartner(email:)` + `getPartners(direction:)` + `PartnerShellView` + `InvitePartnerSheet` + `UserSearchView`.
**B (rejetée)**: Tout inline dans SharedLinksView → couplage fort.
**C (rejetée)**: 6ème tab → trop.

**Étapes**:
1. NEW `PartnerCreateDto` + `PartnerDirection` enum dans DTOs+People.swift.
2. EDIT `ImmichClient.swift` — Ajouter `createPartner(email:)` + `getPartners(direction:)`.
3. EDIT `ImmichAPIClient.swift` — Implémenter les 2 nouvelles méthodes.
4. NEW `PartnerShellViewModel.swift` — loadPartners(direction:), createPartner(email:), togglePartner(id:,isInTimeline:), removePartner(id:).
5. NEW `PartnerShellView.swift` — TabView (segmented) avec sections "Shared with me" / "Sharing", FAB "+" pour invite.
6. NEW `InvitePartnerSheet.swift` — TextField email + NavigationLink vers UserSearchView + CTA Invite.
7. NEW `UserSearchView.swift` — SearchField + liste users filtrée + checkmark selection.
8. EDIT `ProfileView.swift` — Ajouter "Partners" navigation link dans Me hub → PartnerShellView.
9. Tests — `PartnerShellViewModelTests` +6 (create, toggle, remove, direction filter, empty state, error).
10. Build + suite complète.

## Acceptance Contract

### Approches candidates
**A (retenue)**: createPartner + getPartners(direction:) + PartnerShellView + InvitePartnerSheet + UserSearchView.
**B**: Tout inline dans SharedLinksView → couplage.
**C**: 6ème tab → trop.

### Approche retenue + rationale
**A**. Parité Flutter, écran dédié pour partner management, réutilise DTOs + client.

### Critères

```
### AC-3100 [type: new]
Assertion: PartnerCreateDto{sharedWithId: String} + PartnerDirection enum (shared-by, shared-with) dans DTOs+People.swift.
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+People.swift; grep -qE "struct PartnerCreateDto" "$f" && grep -qE "let sharedWithId" "$f" && grep -qE "enum PartnerDirection" "$f" && grep -qE "shared-by" "$f" && grep -qE "shared-with" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3101 [type: new]
Assertion: ImmichClient expose createPartner(email:) + getPartners(direction: PartnerDirection?).
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; grep -qE "func createPartner\(email: String\)" "$f" && grep -qE "func getPartners\(direction: PartnerDirection\?\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3102 [type: new]
Assertion: PartnerShellViewModel expose loadPartners(direction:), createPartner(email:), togglePartner(id:,isInTimeline:), removePartner(id:), sharedByPartners, sharedWithPartners, inviteInput, availableUsers.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/PartnerShellViewModel.swift; test -f "$f" && grep -qE "func loadPartners" "$f" && grep -qE "func createPartner" "$f" && grep -qE "func togglePartner" "$f" && grep -qE "func removePartner" "$f" && grep -qE "sharedByPartners" "$f" && grep -qE "sharedWithPartners" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3103 [type: new]
Assertion: PartnerShellView expose TabView segmenté (2 tabs: "Shared with me" + "Sharing"), liste partners, FAB "+" pour invite, InvitePartnerSheet.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/PartnerShellView.swift; test -f "$f" && grep -qE "TabView" "$f" && grep -qE "segmented" "$f" && grep -qE "Shared with me" "$f" && grep -qE "Sharing" "$f" && grep -qE "plus" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3104 [type: new]
Assertion: InvitePartnerSheet expose TextField email + UserSearchView link + CTA Invite disabled si email vide + ImmichSwiftUIApp onOpenURL handler app.immich://oauth-callback.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/InvitePartnerSheet.swift; test -f "$f" && grep -qE "TextField" "$f" && grep -qE "email" "$f" && grep -qE "UserSearchView" "$f" && grep -qE "Invite" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3105 [type: new]
Assertion: ProfileView expose "Partners" navigation link dans Me hub avec label "Partners" et systemImage "person.2".
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "Label.*Partners.*person.2" "$f" && grep -qE "PartnerShellView" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3106 [type: new]
Assertion: ImmichAPIClient expose createPartner(email:) + getPartners(direction:).
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; grep -qE "func createPartner" "$f" && grep -qE "func getPartners" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3107 [type: new]
Assertion: MockImmichClient expose createPartner(email:) + getPartners(direction:).
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -qE "createPartner" "$f" && grep -qE "direction" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3108 [type: new]
Assertion: PartnerShellViewModelTests expose ≥6 tests (loadPartners, create, toggle, remove, direction, empty, error).
Check post-impl: sh -c 'f=Tests/PartnerShellViewModelTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 6 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3109 [type: regression]
Assertion: Suite complète ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_partners_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_partners_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
