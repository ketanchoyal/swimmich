# Task: partners-ui

**Objectif** : Ajouter l'interface complète de partner sharing dans ImmichSwiftUI. Le client API est complet (`getPartners`, `updatePartner`, `removePartner`) mais le `POST /api/partners` (création) manque et il n'y a pas d'écran dédié au sharing. Parité avec le Flutter `partner.page.dart`, `partner_detail.page.dart`.

**Hypothèses** :
- `getPartners()` → `[PartnerResponseDto]` (DTOs+People.swift:57-64) — méthode wire.
- `updatePartner(id:, isInTimeline:)` → `PartnerUpdateDto(inTimeline:)` (DTOs+People.swift:68-70) — wire.
- `removePartner(id:)` — wire (DELETE 204).
- `PartnerResponseDto` expose `id`, `name`, `email`, `profileImagePath`, `avatarColor`, `inTimeline`.
- `getPartners` ne supporte pas le filtre `direction` (`shared-by` / `shared-with`) côté serveur — il faut `POST /api/partners/{id}` pour créer, et `GET /api/partners?direction=` pour filtrer.
- `SharedLinksView` a déjà `PartnerRow` et `PartnerAvatarCircle` (SharedLinksView.swift:341-407).
- Le `Shared` tab (SharedLinksView) est déjà utilisé pour les shared links + partenaires.
- `getTimeBuckets`/`getTimeBucket` acceptent déjà `withPartners: Bool?` (TimelineViewModel).

**Endpoints à ajouter** :
- `POST /api/partners` — créer un partenaire par email/userId (`PartnerCreateDto`).
- Query param `direction` dans `getPartners` pour filtrer `shared-by` / `shared-with`.

**Approche retenue** : A — ajout `createPartner` + `getPartners(direction:)` dans ImmichClient + écran PartnerShell dans le Shared tab.
- **B (rejetée)** : ajouter tout dans SharedLinksView. Trop de responsabilité pour un view déjà chargé.
- **C (rejetée)** : onglet dédié. Le Flutter met les partners dans la Library tab, pas un 6ème tab. On reste dans Shared.

## Étapes

1. **DTOs** — Ajouter :
   - NEW `PartnerCreateDto` dans `DTOs+People.swift` : `{ sharedWithId: String }`.
   - NEW `PartnerDirection` enum (`shared-by`, `shared-with`) dans `DTOs+People.swift`.
2. **ImmichClient** — Étendre :
   - `func createPartner(email: String) async throws -> PartnerResponseDto` (POST /api/partners).
   - `func getPartners(direction: PartnerDirection?) async throws -> [PartnerResponseDto]` (GET /api/partners?direction=).
3. **ImmichAPIClient** — Implémenter les 2 nouvelles méthodes.
4. **PartnerShell** — NEW `Sources/Features/SharedLinks/PartnerShellView.swift` :
   - Section "Shared with me" (direction=shared-by) : liste des partenaires qui partagent avec moi.
   - Section "Sharing" (direction=shared-with) : liste des partenaires que j'ai invités.
   - Bouton "+" pour créer un partenaire → invite sheet (email input + search Users).
   - Chaque partner row : avatar initials + name + email + toggle "Show in timeline" + button "Remove" + confirmation dialog.
5. **User picker** — Intégrer `getUsers()` (already wired) dans l'invite sheet pour rechercher les users de l'instance.
6. **RootView** — Ajouter `PartnerShellView` dans le Shared tab ou la section Shared.
7. **Tests** — `PartnerShellViewModelTests` + tests `createPartner`, `getPartners(direction:)`, `toggle`, `remove`.
8. **xcodegen + suite**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : `createPartner(email:)` + `getPartners(direction:)` + `PartnerShellView` dans le Shared tab. Parity Flutter complète.
**B** : Tout inline dans SharedLinksView. Couplage fort.
**C** : 6ème onglet. Trop d'onglets dans l'UI iOS.

### Approche retenue + rationale
**A**. S'inscrit dans le Shared tab existant, réutilise PartnerRow/PartnerAvatarCircle, expose les 2 nouveaux endpoints.

### Critères

```
### AC-PN01 [type: new]
Assertion: PartnerCreateDto existe (sharedWithId), PartnerDirection enum (shared-by, shared-with).
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+People.swift; grep -q "PartnerCreateDto" "$f" && grep -q "PartnerDirection" "$f" && grep -q "shared-by" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN02 [type: new]
Assertion: ImmichClient expose createPartner(email:) + getPartners(direction:).
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; grep -q "func createPartner(email" "$f" && grep -q "func getPartners(direction" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN03 [type: new]
Assertion: PartnerShellView existe (NEW file) avec sections "Shared with me" + "Sharing" + invite sheet.
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/PartnerShellView.swift; test -f "$f" && grep -q "createPartner" "$f" && grep -q "direction" "$f" && grep -q "removePartner" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN04 [type: new]
Assertion: ImmichAPIClient implémente createPartner + getPartners(direction:).
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; grep -q "func createPartner" "$f" && grep -q "func getPartners" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN05 [type: new]
Assertion: PartnerShellViewModel expose loadPartners(direction:), createPartner(email:), togglePartner(id:, isInTimeline:), removePartner(id:).
Check post-impl: sh -c 'f=Sources/Features/SharedLinks/PartnerShellViewModel.swift; test -f "$f" && grep -q "func loadPartners" "$f" && grep -q "func createPartner" "$f" && grep -q "func togglePartner" "$f" && grep -q "func removePartner" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN06 [type: new]
Assertion: MockImmichClient implémente createPartner + getPartners(direction:).
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -q "createPartner" "$f" && grep -q "direction" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN07 [type: regression]
Assertion: Suite ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_partners_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_partners_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
