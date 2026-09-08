# Task: memories-complete

Status: plan

## Plan

**Objectif**: Compléter Memories avec save/unsave, create memory, et autres types (first_day, yearly_recap). Seulement `getMemories()` wire actuellement.

**Hypothèses** (ground truth vérifié):
- `MemoriesView` + `MemoriesViewModel` existent dans Sources/Features/Memories/.
- `getMemories() -> [MemoryResponseDto]` wire (DTOs+Social.swift).
- `MemoryResponseDto{isSaved, showAt, hideAt, seenAt, deletedAt}` expose des champs d'update mais méthodes manquantes.
- `MemoryType{on_this_day, unknown}` dans DTOs+Social.swift.
- `MemoryMomentView` affiche les cartes OnThisDay.

**Approche retenue**: A — CRUD mémoire + types additionnels dans MemoriesViewModel/MemoriesView.
**B (rejetée)**: Nouveau module Memories2 → duplication.
**C (rejetée)**: Seulement save/unsave → manque create + types.

**Étapes**:
1. NEW `MemoryCreateDto`, `MemoryUpdateDto` + MemoryType.first_day, yearly_recap dans DTOs+Social.swift.
2. EDIT `ImmichClient.swift` — 7 nouvelles méthodes: getMemory(id:), updateMemory(id:,dto:), deleteMemory(id:), createMemory(dto:), addAssetsToMemory(id:,assetIds:), removeAssetsFromMemory(id:,assetIds:), getMemoriesStatistics().
3. EDIT `ImmichAPIClient.swift` — Implémenter les 7 méthodes.
4. EDIT `MemoriesViewModel.swift` — saveMemory(id:), unsaveMemory(id:), createMemory(assetIds:), deleteMemory(id:), memoryTitle, memoryDate, selectedType, selectedPhotos.
5. EDIT `MemoriesView.swift` — Save/unsave dans context menu, create FAB, types display (badges colorés).
6. NEW `CreateMemorySheet.swift` — Type selector + title + date picker + photo count.
7. Tests — `MemoriesViewModelTests` +8 (save, unsave, create, delete, type variants).
8. Build + suite complète.

## Acceptance Contract

### Approches candidates
**A (retenue)**: CRUD + types additionnels → 7 endpoints + extensions DTO + VM étendu.
**B**: Nouveau module → duplication.
**C**: Seulement save/unsave → insuffisant.

### Approche retenue + rationale
**A**. Toutes les opérations memories en une extension du module existant.

### Critères

```
### AC-3200 [type: new]
Assertion: DTOs+Social.swift expose MemoryCreateDto{assetIds:[String],isUpcoming?,memoryAt?,type:MemoryType?}, MemoryUpdateDto{isSaved?,seenAt?,hideAt?}, MemoryType.first_day, yearly_recap.
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+Social.swift; grep -qE "struct MemoryCreateDto" "$f" && grep -qE "struct MemoryUpdateDto" "$f" && grep -qE "first_day" "$f" && grep -qE "yearly_recap" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3201 [type: new]
Assertion: ImmichClient expose 7 méthodes memories: getMemory(id:), updateMemory(id:,dto:), deleteMemory(id:), createMemory(dto:), addAssetsToMemory(id:,assetIds:), removeAssetsFromMemory(id:,assetIds:), getMemoriesStatistics().
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; n=$(grep -cE "Memory" "$f"); test "$n" -ge 14 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (<7)
Post-state attendu: PASS (≥14 mentions Memory)
```

```
### AC-3202 [type: new]
Assertion: MemoriesViewModel expose saveMemory(id:), unsaveMemory(id:), createMemory(assetIds:), deleteMemory(id:), memoryTitle, memoryDate, selectedType, selectedPhotos.
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoriesViewModel.swift; grep -qE "func saveMemory" "$f" && grep -qE "func unsaveMemory" "$f" && grep -qE "func createMemory" "$f" && grep -qE "func deleteMemory" "$f" && grep -qE "memoryTitle" "$f" && grep -qE "memoryDate" "$f" && grep -qE "selectedType" "$f" && grep -qE "selectedPhotos" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (seulement load())
Post-state attendu: PASS
```

```
### AC-3203 [type: new]
Assertion: MemoriesView expose save/unsave toggle dans context menu, create FAB ("+") dans toolbar, memory type badges colorés.
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoriesView.swift; grep -qE "saveMemory" "$f" && grep -qE "unsaveMemory" "$f" && grep -qE "createMemory" "$f" && grep -qE "plus" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3204 [type: new]
Assertion: CreateMemorySheet expose type selector, title field, date picker, photo count → POST /api/memories.
Check post-impl: sh -c 'f=Sources/Features/Memories/CreateMemorySheet.swift; test -f "$f" && grep -qE "type.*selected" "$f" && grep -qE "TextField" "$f" && grep -qE "DatePicker" "$f" && grep -qE "createMemory" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3205 [type: new]
Assertion: ImmichAPIClient expose 7 méthodes memories (getMemory, updateMemory, deleteMemory, createMemory, addAssetsToMemory, removeAssetsFromMemory, getMemoriesStatistics).
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; n=$(grep -cE "Memory" "$f"); test "$n" -ge 14 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (<7)
Post-state attendu: PASS (≥14)
```

```
### AC-3206 [type: new]
Assertion: MockImmichClient expose 7 méthodes memories.
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -qE "updateMemory" "$f" && grep -qE "createMemory" "$f" && grep -qE "deleteMemory" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3207 [type: new]
Assertion: MemoriesViewModelTests expose ≥8 tests (save, unsave, create, delete, first_day, yearly_recap, type variants, error).
Check post-impl: sh -c 'f=Tests/MemoriesViewModelTests.swift; n=$(grep -cE "func test_memory\|func test_save\|func test_unsave\|func test_create\|func test_delete" "$f"); test "$n" -ge 8 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3208 [type: regression]
Assertion: Suite complète ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_memories_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_memories_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
