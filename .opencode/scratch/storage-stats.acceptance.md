# Task: storage-stats

Status: shipped — AC-1030..AC-1035 PASS 2026-08-12. Full suite 382 tests, 0 failures (baseline 376). Note: quota mapping initial impl (first(where:) one-liner) crashed the Swift 5.9 frontend ("failed to produce diagnostic") → replaced with a plain for-loop, works fine.

## Plan
**Objectif**: Section "Stockage" dans ProfileView (onglet Moi) : photos/vidéos/total utilisés + barre de quota (quotaSizeInBytes) via GET /api/server/statistics. Le client existe déjà (getServerStatistics, P0 AC-803).

**Hypothèses** (ground truth vérifié):
- `ServerStatsResponseDto` + `UsageByUserDto` (Sources/Core/Types/DTOs+Server.swift:6-24) — usageByUser[0].quotaSizeInBytes = quota courant.
- `MockImmichClient.getServerStatistics` (:619-625) — canonical bump/globalError/`serverStatisticsResponse ??` fallback (requiert setStub non-optionnel nil → fallback 0).
- `DependencyContainer` (Sources/DependencyContainer.swift:20-59) — pattern make*ViewModel; `client: ImmichAPIClient` :8.
- `RootView` (:21-31) init construit tous les VMs via container; `ProfileView(trash: trash)` :90.
- `ProfileView.swift` — Form, Section "Compte" (:15-22), "Gestion" (:24-38). Doc-string :7 dit "full profile/settings screen (server, storage, about) deferred" → cette card livre le stockage.
- Exemple formatage existant: ExifFormatterTests accepte variantes locale (MB|Mo).
- Card methodology: checks grep tokens = syntaxe RÉELLE du code (leçons map-extras/storage).

**Approche retenue**: A — VM dédié `StorageStatsViewModel` (@Observable @MainActor, client injecté, load() idempotent via guard isLoading, Int64 conversion, quota = premier usageByUser > 0) + fabrique container + injection RootView @State + Section Form avec LabeledContent + ProgressView quota (tint immichPrimary), `.task { await storage.load() }` + `.refreshable`. Formatage ByteCountFormatter.countStyle .file (static nonisolated). Tests VM (success/quota zero/quota manquant/failure) + format (variantes locale MB|Mo|MO, GB|Go|GO).
**B rejeté**: pas de VM, appel direct dans ProfileView — casserait le pattern MVVM + non testable (client privé dans AuthViewModel).
**C rejeté**: Stats dans AuthViewModel — couplage auth/storage, testable mais moche.

**Étapes**:
1. NEW `Sources/Features/Profile/StorageStatsViewModel.swift` — @Observable @MainActor final class; let client: any ImmichClient; var photos/videos/usage/quotaSizeInBytes (Int64)/isLoading/errorMessage + private(set) didLoad; `func load() async` (guard !isLoading; defer; do getServerStatistics → map Int64; quota = usageByUser.first(where: { $0.quotaSizeInBytes > 0 })?.quotaSizeInBytes; catch errorMessage); `nonisolated static func format(_ bytes: Int64) -> String` ByteCountFormatter.
2. `Sources/DependencyContainer.swift` — `func makeStorageStatsViewModel() -> StorageStatsViewModel` après makeSharedLinksViewModel.
3. `Sources/RootView.swift` — @State storage + init makeStorageStatsViewModel() + ProfileView(trash: trash, storage: storage).
4. `Sources/Features/Profile/ProfileView.swift` — `@State var storage: StorageStatsViewModel`; Section "Stockage" entre Compte et Gestion: LabeledContent Photos/Vidéos (`storage.photos.formatted()`), LabeledContent "Utilisation" (storage.format(storage.usage)), si quota > 0 → ProgressView(value: min(Double(usage)/Double(quota), 1)) tint immichPrimary + LabeledContent "Quota" (format); si errorMessage → Label immichError + Button "Réessayer" (Task load). `.task { await storage.load() }` sur Form + `.refreshable { await storage.load() }`.
5. NEW `Tests/StorageStatsViewModelTests.swift` — 6 tests (ci-dessous).
6. xcodegen generate (2 nouveaux fichiers). Build + suite complète → /tmp/immich_storage_stats_test_summary.txt.
7. ACs + memory.md entry.

## Acceptance Contract

### Approches candidates
**A (retenue)**: VM dédié + fabrique container + injection RootView + Section Form .task/.refreshable. Pattern codebase (tous les VMs), testable, PRD §4-aligned.
**B**: Appel client direct dans ProfileView (client via AuthViewModel). Non testable, hors pattern.
**C**: Stats dans AuthViewModel. Couplage de domaines, cohérence auth fragile.

### Approche retenue + rationale
A. Conforme pattern MVVM/DI du projet; ByteCountFormatter locale-safe; quota optionnel (serveurs sans quota → pas de barre, pas de crash).

### Critères

```
### AC-1030 [type: new]
Assertion: StorageStatsViewModel existe, encapsule getServerStatistics + quotaSizeInBytes (quota = premier usageByUser avec quota > 0), expose format statique ByteCountFormatter.
Check post-impl: sh -c 'f=Sources/Features/Profile/StorageStatsViewModel.swift; grep -q "let client: any ImmichClient" "$f" && grep -q "getServerStatistics()" "$f" && grep -q "quotaSizeInBytes" "$f" && grep -q "ByteCountFormatter" "$f" && grep -q "func load() async" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier inexistant)
Post-state attendu: PASS
```

```
### AC-1031 [type: new]
Assertion: DependencyContainer expose makeStorageStatsViewModel().
Check post-impl: sh -c 'grep -q "func makeStorageStatsViewModel" Sources/DependencyContainer.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1032 [type: new]
Assertion: RootView construit le VM et l'injecte dans ProfileView.
Check post-impl: sh -c 'grep -q "@State private var storage: StorageStatsViewModel" Sources/RootView.swift && grep -q "makeStorageStatsViewModel()" Sources/RootView.swift && grep -q "ProfileView(trash: trash, storage: storage)" Sources/RootView.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1033 [type: new]
Assertion: ProfileView ajoute la section Stockage: LabeledContent Photos/Vidéos/Utilisation, barre ProgressView quota, erreur + retry, chargement .task + refreshable.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -q "Stockage" "$f" && grep -q "LabeledContent" "$f" && grep -q "ProgressView" "$f" && grep -q "storage.load()" "$f" && grep -q "refreshable" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune section Stockage)
Post-state attendu: PASS
```

```
### AC-1034 [type: new]
Assertion: StorageStatsViewModelTests couvre success/quota absent/failure/format (≥ 4 tests test_storage*).
Check post-impl: sh -c 'n=$(grep -c "func test_storage" Tests/StorageStatsViewModelTests.swift); test "$n" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1035 [type: regression]
Assertion: Suite complète ≥ 376 tests, 0 échec (baseline card map-extras).
Check post-impl: sh -c 'rtk grep -q "TEST SUCCEEDED" /tmp/immich_storage_stats_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_storage_stats_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 376 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (summary absent)
Post-state attendu: PASS
```