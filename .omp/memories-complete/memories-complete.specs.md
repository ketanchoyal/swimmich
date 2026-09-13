# Task: memories-complete

> **LIVRÉ le 2026-09-13** — 9/9 AC PASS, suite 749 → 772 tests, `test_08_memories` de bout en bout contre `UITests/stubs/immich_stub_memories.py`. La carte de référence est `.opencode/scratch/memories-complete.acceptance.md` (réécrite sur le contrat serveur réel). **Les sections « Endpoints à ajouter » et « Étapes » ci-dessous ont été corrigées le 2026-09-13** : la version d'origine annonçait `PATCH /api/memories/{id}` et `POST /api/memories/{id}/assets` (tous deux 404) et demandait des types de mémoire et un champ titre que le serveur n'expose pas. Détail des corrections : §2.4 du backlog.

**Objectif** : Compléter la feature Memories pour atteindre la parité Flutter. Actuellement seul le tab "OnThisDay" est implémenté. Il manque le save/unsave, la création de mémoires, et le visionnage individuel complet.

**Hypothèses** :
- `MemoriesView.swift` + `MemoriesViewModel.swift` existants.
- `getMemories()` → `[MemoryResponseDto]` wire (DTOs+Social.swift:48-62).
- `MemoryResponseDto` expose `isSaved`, `showAt`, `hideAt`, `seenAt`, `deletedAt` — mais les méthodes d'update n'existent pas dans le client.
- `MemoryType` enum : `.on_this_day`, `.unknown`.
- `MemoryMomentView` affiche les cartes OnThisDay avec grille d'assets.
- Le viewer de mémoire (memories-redesign.acceptance.md) existe déjà.

**Endpoints à ajouter** (verbes vérifiés le 2026-09-13 sur l'OpenAPI publié `main` sha `bace1792…` et `v1.135.0`, plus `server/src/controllers/memory.controller.ts`) :
- `GET /api/memories/{id}` — détails d'une mémoire.
- `PUT /api/memories/{id}` — update (`{isSaved?}`, `{memoryAt?}`, `{seenAt?}`) — **PUT**, pas PATCH (un PATCH rend 404).
- `DELETE /api/memories/{id}` — delete (204).
- `POST /api/memories` — create from selected assets (`data:{year}` + `memoryAt` + `type` requis, **aucun champ nom**).
- `PUT /api/memories/{id}/assets` — add assets — **PUT**, pas POST ; corps **`BulkIdsDto` (`{ids}`)**, réponse **`BulkIdResponseDto`** (champ `id`, erreur `NO_PERMISSION`).
- `DELETE /api/memories/{id}/assets` — remove assets (même corps, réponse 200 et non 204).
- `GET /api/memories/statistics` — `{total}` (compte les lignes, sans le filtre « a des assets » de la liste).

**Approche retenue** : A — ajouter les méthodes client CRUD + étendre MemoriesViewModel/MemoriesView avec save/unsave, create, et les types additionnels.
- **B (rejetée)** : créer un nouveau module Memories2. Le module existant fait 80% du travail.
- **C (rejetée)** : tous les endpoints en une seule card. Scope trop large — split en create/save + type extensions.

## Étapes

1. **DTOs** — Ajouter dans `DTOs+Social.swift` :
   - `MemoryCreateDto` : `{ assetIds: [String], data: OnThisDayDto, memoryAt: String, type: MemoryType, isSaved: Bool? }` — `data`, `memoryAt` et `type` sont **requis** côté serveur ; `isSaved: true` à la création (le ménage supprime les mémoires non sauvegardées de plus de 30 jours).
   - `MemoryUpdateDto` : `{ isSaved: Bool?, memoryAt: String?, seenAt: String? }` — c'est tout le schéma serveur.
   - `MemoryStatisticsResponseDto` : `{ total: Int }`.
   - `MemoryType` : **inchangé** — l'enum serveur est `["on_this_day"]` seul, `.first_day`/`.yearly_recap` n'existent pas.
2. **ImmichClient** — Ajouter :
   - `func getMemory(id: String) async throws -> MemoryResponseDto` (GET).
   - `func updateMemory(id: String, dto: MemoryUpdateDto) async throws -> MemoryResponseDto` (**PUT**).
   - `func deleteMemory(id: String) async throws` (DELETE).
   - `func createMemory(dto: MemoryCreateDto) async throws -> MemoryResponseDto` (POST).
   - `func addAssetsToMemory(id: String, assetIds: [String]) async throws -> [BulkIdResponseDto]` (PUT).
   - `func removeAssetsFromMemory(id: String, assetIds: [String]) async throws -> [BulkIdResponseDto]` (DELETE).
   - `func getMemoriesStatistics() async throws -> MemoryStatisticsResponseDto`.
3. **ImmichAPIClient** — Implémenter les 7 nouvelles méthodes.
4. **MemoriesViewModel** — Étendre avec :
   - `func saveMemory(id:)` / `func unsaveMemory(id:)` — `PUT {isSaved}`.
   - `func createMemory()` — POST depuis la sélection du picker (`orderedSelection`), avec `data.year` et `memoryAt` tirés du **même jour** (minuit UTC du jour local choisi : la carte relit la date en UTC).
   - `func deleteMemory(id:)` — DELETE.
   - `func addAssets(toMemoryId:assetIds:)` / `func removeAssets(fromMemoryId:assetIds:)` — l'écran se ferme quand la mémoire perd sa dernière photo (`GET /api/memories` filtre les mémoires sans asset).
5. **MemoriesView** — Étendre : bookmark par carte, menu contextuel (save/unsave, ajouter des photos, supprimer), bouton « + » dans la barre, `CreateMemorySheet` + `AddPhotosToMemorySheet`. **Pas de sélecteur de type ni de champ titre** — le serveur n'en a pas.
6. **`AssetMultiSelectGrid`** (`Sources/Features/Timeline/`) — la grille multi-sélection est partagée par les quatre feuilles (piles + mémoires) ; `StackPhotoPicker.swift` supprimé.
7. **Tests** — `MemoriesViewModelTests` +16, `ImmichAPIClientTests` +7 (transport), stub committé + `test_08_memories`.
8. **xcodegen + suite**.

## Acceptance Contract

Les critères de cette feature vivent dans la carte `.opencode/scratch/memories-complete.acceptance.md` (AC-3200…AC-3208), réécrite le 2026-09-13 sur le contrat serveur réel.

L'ancien bloc `AC-MM01…AC-MM07` de ce fichier a été **supprimé** : il pinnait les trois demandes sans objet serveur (`MemoryType.first_day`/`.yearly_recap`, un champ titre) et deux « checks » qui ne vérifiaient rien (`grep -c "Memory" >= 14`, `grep -q "saveMemory\|unsaveMemory\|createMemory\|deleteMemory"` — un seul mot satisfaisait la ligne), plus une borne de régression obsolète (`>= 200` pour une baseline de 749).

### Résultat (2026-09-13)
**9/9 AC PASS** (AC-3200…AC-3208). Suite **749 → 772 tests, TEST SUCCEEDED** (iPhone 17). `test_08_memories` vert contre le stub committé. Preuve de contrat réseau (journal du stub) et défauts corrigés : voir `.opencode/scratch/memories-complete.acceptance.md` et §2.4 du backlog.
