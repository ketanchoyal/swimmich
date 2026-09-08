# Task: memories

Status: shipped — AC-1110..AC-1114 PASS 2026-08-12 (446 tests, +4).

## Plan
**Objectif**: Onglet Memories (parity Flutter Photos/Memories/People/Albums/Shared). Affiche les souvenirs "On this day" du serveur (`GET /api/memories`, client P0 AC-802) : cartes par année + pile d'assets, tap → viewer plein écran. Save/unsave memory = backlog (endpoints serveur non exposés dans le client).

**Hypothèses**:
- `getMemories()` client → `[MemoryResponseDto{id, createdAt, updatedAt, memoryAt, ownerId, type: .on_this_day, data{year}, assets[AssetResponseDto], isSaved, showAt?/hideAt?/seenAt?/deletedAt?}]` (Sources/Core/Types/DTOs+Social.swift:39-53).
- MockImmichClient.getMemories :606-609 → `memoriesResponse ?? []` (throw sharedLinksError — stub borgne; tests utilisent globalError pour failure).
- RootTab (RootView.swift:165-171) = photos/albums/people/shared/me/search; insertion memories entre photos et albums (ordre Flutter).
- Pattern: DependencyContainer.makeXxxViewModel → RootView @State + State(initialValue:) → TabView Tab.
- Viewer: `.photoViewer(item:baseURL:token:onDataChanged:)` — PhotoViewerItem(assets: [AssetReactItem], index:) ; conversion AssetReactItem(from: AssetResponseDto) existante.
- Build: xcodebuild -destination id=5A17A555-84A5-49AE-9359-C07E1EA53908 (iPhone 17 Pro booté).

**Approche retenue**: A — MemoriesViewModel @Observable @MainActor (load/memories/isLoading/errorMessage) + MemoriesView ScrollView cartes (header "On this day" + "yyyy" + count, LazyVGrid 3 cols des assets du memory, tap → viewer) + Tab dédié. **B** (rejetée) : carousel en haut du Timeline — concurrence avec la grille, pas parity Flutter. **C** (rejetée) : section dans Search — mauvais slot.

**Étapes**:
1. Card écrite (ce fichier).
2. `Sources/Core/Protocols/ImmichClient.swift` — rien (getMemories existe).
3. NEW `Sources/Features/Memories/MemoriesViewModel.swift`.
4. NEW `Sources/Features/Memories/MemoriesView.swift`.
5. `Sources/DependencyContainer.swift` — makeMemoriesViewModel().
6. `Sources/RootView.swift` — RootTab.memories (entre photos et albums) + Tab("Memories", systemImage: "sparkles.rectangle.stack") + @State + bubbleIcon/handleBubbleTap cases .memories.
7. NEW `Tests/MemoriesViewModelTests.swift`.
8. xcodegen generate + build-for-testing + suite complète → /tmp/immich_memories_test_summary.txt.
9. Checks AC (grep ^Check post-impl: | sed | eval) + memory.md + Status shipped.

## Acceptance Contract

### Approches candidates
**A (retenue)**: VM dédié + Tab dédié. Parity Flutter, testable, pattern codebase.
**B**: Carousel dans TimelineView. Concurrence grille, hors parity.
**C**: Section Search. Mauvais slot UX.

### Approche retenue + rationale
**A**. Cohérent RootTab existant; VM isolé testable; viewer réutilisé.

### Critères

```
### AC-1110 [type: new]
Assertion: MemoriesViewModel existe avec load() async, memories, isLoading, errorMessage.
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoriesViewModel.swift; test -f "$f" && grep -q "func load() async" "$f" && grep -q "var memories" "$f" && grep -q "var errorMessage" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-1111 [type: new]
Assertion: MemoriesView existe : cartes par memory (année data.year + count) + grid assets + photoViewer intégré (PhotoViewerItem).
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoriesView.swift; test -f "$f" && grep -q "photoViewer" "$f" && grep -q "PhotoViewerItem" "$f" && grep -q "data.year" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-1112 [type: new]
Assertion: RootTab.memories existe entre photos et albums; Tab Memories dans TabView; DependencyContainer.makeMemoriesViewModel.
Check post-impl: sh -c 'grep -q "case memories" Sources/RootView.swift && grep -q "Tab(\"Memories\"" Sources/RootView.swift && grep -q "makeMemoriesViewModel" Sources/DependencyContainer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun memories)
Post-state attendu: PASS
```

```
### AC-1113 [type: new]
Assertion: Tests MemoriesViewModelTests ≥ 3 (load success/failure/empty).
Check post-impl: sh -c 'f=Tests/MemoriesViewModelTests.swift; n=$(grep -c "func test_" "$f"); test "$n" -ge 3 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-1114 [type: regression]
Assertion: Suite complète ≥ 442 tests, TEST SUCCEEDED.
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_memories_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_memories_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 442 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (pas de summary)
Post-state attendu: PASS
```
