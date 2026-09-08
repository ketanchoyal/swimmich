# Task: memories-complete

**Objectif** : Compléter la feature Memories pour atteindre la parité Flutter. Actuellement seul le tab "OnThisDay" est implémenté. Il manque le save/unsave, la création de mémoires, les autres types (first day, yearly recap), et le visionnage individuel complet.

**Hypothèses** :
- `MemoriesView.swift` + `MemoriesViewModel.swift` existants.
- `getMemories()` → `[MemoryResponseDto]` wire (DTOs+Social.swift:48-62).
- `MemoryResponseDto` expose `isSaved`, `showAt`, `hideAt`, `seenAt`, `deletedAt` — mais les méthodes d'update n'existent pas dans le client.
- `MemoryType` enum : `.on_this_day`, `.unknown`.
- `MemoryMomentView` affiche les cartes OnThisDay avec grille d'assets.
- Le viewer de mémoire (memories-redesign.acceptance.md) existe déjà.

**Endpoints à ajouter** :
- `GET /api/memories/{id}` — détails d'une mémoire (GET).
- `PUT /api/memories/{id}` — update (save/unsave, seen, hide) — PATCH.
- `DELETE /api/memories/{id}` — delete.
- `POST /api/memories` — create from selected assets.
- `PUT /api/memories/{id}/assets` — add assets.
- `DELETE /api/memories/{id}/assets` — remove assets.
- `GET /api/memories/statistics` — stats.

**Approche retenue** : A — ajouter les méthodes client CRUD + étendre MemoriesViewModel/MemoriesView avec save/unsave, create, et les types additionnels.
- **B (rejetée)** : créer un nouveau module Memories2. Le module existant fait 80% du travail.
- **C (rejetée)** : tous les endpoints en une seule card. Scope trop large — split en create/save + type extensions.

## Étapes

1. **DTOs** — Ajouter dans `DTOs+Social.swift` :
   - `MemoryCreateDto` : `{ assetIds: [String], isUpcoming: Bool?, memoryAt: String?, type: MemoryType? }`.
   - `MemoryUpdateDto` : `{ isSaved: Bool?, seenAt: String?, hideAt: String? }`.
   - NEW Memory types: `.first_day`, `.yearly_recap`.
2. **ImmichClient** — Ajouter :
   - `func getMemory(id: String) async throws -> MemoryResponseDto` (GET).
   - `func updateMemory(id: String, dto: MemoryUpdateDto) async throws -> MemoryResponseDto` (PUT/PATCH).
   - `func deleteMemory(id: String) async throws` (DELETE).
   - `func createMemory(dto: MemoryCreateDto) async throws -> MemoryResponseDto` (POST).
   - `func addAssetsToMemory(id: String, assetIds: [String]) async throws -> [BulkIdResponseDto]` (PUT).
   - `func removeAssetsFromMemory(id: String, assetIds: [String]) async throws -> [BulkIdResponseDto]` (DELETE).
   - `func getMemoriesStatistics() async throws -> MemoryStatisticsResponseDto`.
3. **ImmichAPIClient** — Implémenter les 7 nouvelles méthodes.
4. **MemoriesViewModel** — Étendre avec :
   - `func saveMemory(id: String)` — PUT isSaved=true.
   - `func unsaveMemory(id: String)` — PUT isSaved=false.
   - `func createMemory(assetIds: [String])` — POST.
   - `func deleteMemory(id: String)` — DELETE.
   - Gestion des types memoryAt (month/day pour first_day) + year pour yearly_recap.
5. **MemoriesView** — Étendre :
   - Save/unsave button (bookmark star) sur chaque mémoire.
   - "Create memory from selected" action → picker d'assets.
   - Support visuel des types first_day (champ de date) et yearly_recap (année + photo).
   - Delete confirmation.
6. **Tests** — `MemoriesViewModelTests` + 8 tests (save, unsave, create, delete, type variants).
7. **xcodegen + suite**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : CRUD + types additionnels dans MemoriesViewModel/MemoriesView existants. 7 endpoints à ajouter au client.
**B** : Nouveau module MemoriesComplete. Duplication de code.
**C** : Seulement save/unsave. Manque create + types.

### Approche retenue + rationale
**A**. Toutes les opérations memories couvertes en une seule implémentation, en étendant le module existant.

### Critères

```
### AC-MM01 [type: new]
Assertion: DTOs+Social.swift expose MemoryCreateDto, MemoryUpdateDto, MemoryType.first_day, MemoryType.yearly_recap.
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+Social.swift; grep -q "MemoryCreateDto" "$f" && grep -q "MemoryUpdateDto" "$f" && grep -q "first_day" "$f" && grep -q "yearly_recap" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-MM02 [type: new]
Assertion: ImmichClient expose 7 méthodes memories CRUD (getMemory, updateMemory, deleteMemory, createMemory, addAssetsToMemory, removeAssetsFromMemory, getMemoriesStatistics).
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; n=$(grep -c "Memory" "$f"); test "$n" -ge 14 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (<7)
Post-state attendu: PASS (≥14 mentions Memory)
```

```
### AC-MM03 [type: new]
Assertion: MemoriesViewModel expose saveMemory, unsaveMemory, createMemory, deleteMemory.
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoriesViewModel.swift; grep -q "func saveMemory" "$f" && grep -q "func unsaveMemory" "$f" && grep -q "func createMemory" "$f" && grep -q "func deleteMemory" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (seulement load())
Post-state attendu: PASS
```

```
### AC-MM04 [type: new]
Assertion: MemoriesView expose save/unsave toggle + create memory button + delete.
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoriesView.swift; grep -q "saveMemory\|unsaveMemory\|createMemory\|deleteMemory" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-MM05 [type: new]
Assertion: ImmichAPIClient implémente les 7 méthodes memories.
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; n=$(grep -c "Memory" "$f"); test "$n" -ge 14 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (<7)
Post-state attendu: PASS (≥14)
```

```
### AC-MM06 [type: new]
Assertion: MockImmichClient implémente les 7 méthodes memories.
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -q "updateMemory" "$f" && grep -q "createMemory" "$f" && grep -q "deleteMemory" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-MM07 [type: regression]
Assertion: Suite ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_memories_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_memories_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
