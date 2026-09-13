# Task: memories-complete

Status: done — **9/9 AC PASS** (2026-09-13). Suite complète **772 tests, TEST SUCCEEDED** (iPhone 17 ; baseline 749 sur `HEAD` `e318d44`, +23), scénario `test_08_memories` vert contre le stub **committé** `UITests/stubs/immich_stub_memories.py`. Carte **réécrite le 2026-09-13 sur le contrat réel du serveur** : la version d'origine (AC-3200…AC-3208) décrivait trois choses que le serveur ne fait pas.

## Ce que la carte d'origine affirmait à tort (corrigé ici, comme pour stacks / partners / shared-links)

| Affirmation d'origine | Réalité vérifiée | Preuve |
|---|---|---|
| `PATCH /api/memories/:id` pour l'update | le serveur expose **`PUT`** — `get|put|delete` sur `/memories/{id}`. Un `PATCH` rend 404 | OpenAPI publié `main` (sha `bace1792…`) et `v1.135.0`, `jq '.paths["/memories/{id}"]\|keys'` → `delete,get,put` ; `server/src/controllers/memory.controller.ts:69` (`@Put(':id')`) |
| `POST /api/memories/:id/assets` | **`PUT`** — la route est `put|delete`. Un `POST` rend 404 | `memory.controller.ts:111` (`@Put(':id/assets')`) ; `jq '.paths["/memories/{id}/assets"]\|keys'` sur les deux specs publiées |
| « Ajouter `MemoryType.first_day` / `.yearly_recap` » | `MemoryType` = **`["on_this_day"]` seul**, dans `main` **et** `v1.135.0` : ces deux types n'existent pas côté serveur, un POST qui les envoie part en 400 | `jq '.components.schemas.MemoryType'` sur les deux specs ; `server/src/enum.ts` (`MemoryType`) |
| `CreateMemorySheet` avec un champ **titre** | **aucun DTO mémoire ne porte de nom** — `MemoryResponseDto` = `data:{year}`, `assets`, `memoryAt`, `isSaved`, `showAt`… ; `MemoryCreateDto` requiert `data`, `memoryAt`, `type` (+ `assetIds`) | `server/src/dtos/memory.dto.ts` (`MemoryCreateSchema`, `MemoryResponseSchema`) |
| `MemoryCreateDto { assetIds, isUpcoming?, memoryAt?, type? }` | mauvais : `data` et `memoryAt` et `type` sont **requis**, `assetIds` optionnel, et le vrai corps porte `data:{year}` | idem |
| AC-3208 « suite ≥ **200** tests » | borne obsolète (baseline 749) : le check passait même après une régression massive | mesure du 2026-09-13 |
| Méthodes énumérées « ≥14 mentions de `Memory` » (AC-3201/3205) | compteur de `grep`, pas un contrat — un commentaire satisfaisait le check | — |

**Rien de ces trois points n'a été implémenté** : `first_day`, `yearly_recap` et le champ titre seraient du code mort face à un 400 serveur. La garde AC-3307 interdit leur réapparition.

## Périmètre réel livré

1. **DTOs** — `MemoryCreateDto` (`assetIds`, `data:{year}`, `memoryAt`, `type`, `isSaved`) et `MemoryUpdateDto` (`isSaved`, `memoryAt`, `seenAt`), plus `MemoryStatisticsResponseDto` (`{total}`) dans `DTOs+Social.swift`.
2. **Client** — 7 méthodes sur `ImmichClient` + `ImmichAPIClient` : `getMemory(id:)`, `updateMemory(id:dto:)` (**PUT**), `deleteMemory(id:)` (204), `createMemory(dto:)` (POST), `addAssetsToMemory(id:assetIds:)` (**PUT**, corps `BulkIdsDto`), `removeAssetsFromMemory(id:assetIds:)` (**DELETE**, corps `BulkIdsDto`, réponse 200 `BulkIdResponseDto`), `getMemoriesStatistics()`.
3. **`MemoriesViewModel`** — save/unsave (`PUT {isSaved}`), create, delete, add/remove assets, plus le flux de sélection (pages via `POST /api/search/metadata`, `orderedSelection`).
4. **`MemoriesView`** — bookmark sur chaque carte, menu contextuel (save/unsave, ajouter des photos, supprimer avec confirmation), bouton « + » dans la barre, feuilles `CreateMemorySheet` / `AddPhotosToMemorySheet`.
5. **`MemoryMomentView`** — rangée d'actions (save, ajouter des photos, retirer la photo affichée, supprimer) ; l'écran se ferme quand la mémoire perd sa dernière photo.
6. **`AssetMultiSelectGrid`** (NEW, `Sources/Features/Timeline/`) — la grille multi-sélection était déjà dupliquée par les deux feuilles de piles ; elle sert désormais les quatre feuilles. `StackPhotoPicker.swift` **supprimé**, `CreateStackSheet`/`AddToStackSheet` migrés.

**Détails de contrat à respecter** :
- `PUT`/`DELETE /api/memories/{id}/assets` prennent **`BulkIdsDto` (`{ids}`)** et répondent **`BulkIdResponseDto`** (champ **`id`**, enum d'erreur **`NO_PERMISSION`** en majuscules) — à ne pas confondre avec la route des liens partagés, qui prend `AssetIdsDto` (`{assetIds}`) et répond `AssetIdsResponseDto` (champ `assetId`, `no_permission` en minuscules). Deux DTOs distincts, deux casses distinctes.
- `GET /api/memories` **filtre les mémoires sans asset** (`MemoryService.search`), contrairement à `GET /api/memories/statistics` qui compte les lignes : un total peut donc dépasser la liste. La suppression de la dernière photo fait disparaître la mémoire.
- `size`/`page` de `GET /api/memories` ne s'appliquent **que si `size` est fourni** (`memory.repository.ts:110`). Ce client charge tout d'un coup, donc `statistics` n'a pas d'usage de pagination ici ; c'est ce que fait le web (`size: 250` + `hasNextPage = memories.length < total`).
- Le ménage serveur supprime les mémoires **non sauvegardées** de plus de 30 jours (`MemoryRepository.cleanup`) : une mémoire créée par l'utilisateur part donc avec `isSaved: true`.

## Plan

1. `MemoryCreateDto` / `MemoryUpdateDto` / `MemoryStatisticsResponseDto` — `DTOs+Social.swift`.
2. 7 méthodes dans `ImmichClient` puis `ImmichAPIClient` (verbes **PUT** pour update et add-assets).
3. `MemoriesViewModel` : CRUD + flux de sélection (`beginPicking`, `loadMoreAssets`, `toggleSelection`, `orderedSelection`).
4. `MemoriesView` : bookmark, menu contextuel, bouton « + », feuilles, dialogues.
5. `CreateMemorySheet` + `AddPhotosToMemorySheet` ; `MemoryMomentView` gagne sa rangée d'actions.
6. `AssetMultiSelectGrid` extrait et partagé ; `StackPhotoPicker.swift` supprimé.
7. `MockImmichClient` : 7 méthodes + fixtures par id.
8. Tests : `MemoriesViewModelTests` (+16) et `ImmichAPIClientTests` (+7 transport).
9. Stub committé + scénario XCUITest `test_08_memories`.
10. `xcodegen` + suite complète.

## Critères

Chaque check est rejouable tel quel. Les checks d'exécution lisent un journal de run (`grep` sur une **sortie de test**, jamais sur la source).

```
### AC-3200 [type: new]
Assertion: les 3 DTOs mémoire existent sur le contrat réel (data/memoryAt/type requis, pas de champ nom, types first_day/yearly_recap absents).
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+Social.swift; grep -qE "struct MemoryCreateDto" "$f" && grep -qE "struct MemoryUpdateDto" "$f" && grep -qE "struct MemoryStatisticsResponseDto" "$f" && grep -qE "let data: OnThisDayDto" "$f" && ! grep -qE "first_day|yearly_recap" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun des 3 DTOs ; la carte d'origine demandait au contraire first_day/yearly_recap)
Post-state attendu: PASS
```

```
### AC-3201 [type: new]
Assertion: ImmichClient expose les 7 méthodes mémoire, et l'update/l'ajout d'assets sont en PUT.
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; for m in getMemory updateMemory deleteMemory createMemory addAssetsToMemory removeAssetsFromMemory getMemoriesStatistics; do grep -qE "func $m" "$f" || exit 1; done; grep -qE "getMemory\(id: String\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (seul getMemories existait)
Post-state attendu: PASS
```

```
### AC-3202 [type: new]
Assertion: transport asservi — PUT /api/memories/{id} porte isSaved, POST /api/memories porte les 3 champs requis, PUT/DELETE …/{id}/assets portent BulkIdsDto.
Check post-impl: sh -c 'n=$(grep -cE "Test Case .*ImmichAPIClientTests test_mem_.* passed" /tmp/immich_memories_unit.log); test "$n" -ge 7 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (1 seul test mémoire, en GET)
Post-state attendu: PASS (7)
```

```
### AC-3203 [type: new]
Assertion: le view model porte le CRUD et le contrat de la date (année et memoryAt tirés du même jour, en UTC).
Check post-impl: sh -c 'f=Sources/Features/Memories/MemoriesViewModel.swift; for m in saveMemory unsaveMemory createMemory deleteMemory addAssets removeAssets beginPicking; do grep -qE "func $m" "$f" || exit 1; done; grep -qE "memoryAtString" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (seul load() existait)
Post-state attendu: PASS
```

```
### AC-3204 [type: new]
Assertion: comportement du CRUD — save/unsave, création (payload + fermeture), suppression, ajout/retrait d'assets, et la disparition de la mémoire à sa dernière photo.
Check post-impl: sh -c 'n=$(grep -cE "Test Case .*MemoriesViewModelTests test_(save|unsave|create|delete|add|remove|begin|ordered).* passed" /tmp/immich_memories_unit.log); test "$n" -ge 12 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun test de CRUD)
Post-state attendu: PASS (16)
```

```
### AC-3205 [type: new]
Assertion: l'UI expose bookmark, création, ajout de photos et suppression ; la grille de sélection est partagée par les 4 feuilles (4 sites d'appel, 3 fichiers — les deux feuilles mémoire vivent dans le même fichier) et l'ancienne copie des piles a disparu.
Check post-impl: sh -c 'test ! -f Sources/Features/Stacks/StackPhotoPicker.swift && test -f Sources/Features/Timeline/AssetMultiSelectGrid.swift && n=$(grep -hE "AssetMultiSelectGrid\(" Sources/Features/*/*.swift | wc -l | tr -d " "); test "$n" -eq 4 && grep -qE "memoryBookmark_" Sources/Features/Memories/MemoriesView.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (StackPhotoPicker.swift dans Sources/Features/Stacks/, 2 sites d'appel)
Post-state attendu: PASS
```

```
### AC-3206 [type: new]
Assertion: scénario de bout en bout sur stub committé — save, création depuis une sélection, ajout de photos, vidage (fermeture de l'écran), suppression.
Check post-impl: sh -c 'test -f UITests/stubs/immich_stub_memories.py && grep -qE "Test Case .*test_08_memories.* passed" /tmp/immich_memories_uitest.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL (stub et scénario absents)
Post-state attendu: PASS
```

```
### AC-3207 [type: guard]
Assertion: aucune des trois demandes sans objet serveur (types first_day/yearly_recap, titre de mémoire, verbes PATCH/POST sur les assets) ne réapparaît dans le code.
Check post-impl: sh -c '! grep -rqE "first_day|yearly_recap|memoryTitle|memoryName" Sources/ && ! grep -rqE "sendAuthed\(\.(PATCH|POST), path: ImmichAPI.memories.path\(\"/\\\\\\(id\\)/assets\"" Sources/ && echo PASS || echo FAIL'
Pre-state attendu: PASS (jamais implémentées — la garde interdit leur réapparition)
Post-state attendu: PASS
```

```
### AC-3208 [type: regression]
Assertion: suite complète ≥ 749 (baseline `e318d44`), TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_memories_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_memories_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 749 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (journal absent)
Post-state attendu: PASS
```

## Pré-état mesuré (2026-09-13, HEAD `e318d44`)

Rejoué avant toute implémentation, sur la version `HEAD` des fichiers (les checks de journal sont trivialement FAIL : journaux absents).

| AC | Pré-état | Sortie |
|----|----------|--------|
| AC-3200 | FAIL | `MemoryCreateDto`/`MemoryUpdateDto`/`MemoryStatisticsResponseDto` absents de `DTOs+Social.swift` |
| AC-3201 | FAIL | `ImmichClient.swift:145` = `func getMemories()` seule |
| AC-3202 | FAIL | 1 test mémoire (`test_P0_getMemories_hitsMemoriesEndpoint`) |
| AC-3203 | FAIL | `MemoriesViewModel` = `load()` + présentation |
| AC-3204 | FAIL | 0 test de CRUD |
| AC-3205 | FAIL | `Sources/Features/Stacks/StackPhotoPicker.swift` présent, 2 appelants |
| AC-3206 | FAIL | stub et scénario absents |
| AC-3207 | PASS | 0 occurrence (garde) |
| AC-3208 | FAIL | journal absent |

## Résultat (2026-09-13) — **9/9 AC PASS**

| AC | Résultat | Preuve |
|----|----------|--------|
| AC-3200 | PASS | 3 DTOs dans `DTOs+Social.swift`, `data: OnThisDayDto` requis, ni `first_day` ni `yearly_recap` |
| AC-3201 | PASS | 7 méthodes dans le protocole, `updateMemory`/`addAssetsToMemory` en PUT (`ImmichAPIClient.swift:371-415`) |
| AC-3202 | PASS | 7 tests `test_mem_*` verts dans `ImmichAPIClientTests` |
| AC-3203 | PASS | `MemoriesViewModel` : CRUD + `memoryAtString`/`dayComponents` (ancrage UTC) |
| AC-3204 | PASS | 16 tests de comportement verts dans `MemoriesViewModelTests` (`/tmp/immich_memories_unit.log`) |
| AC-3205 | PASS | `AssetMultiSelectGrid` partagé par 4 feuilles ; `StackPhotoPicker.swift` supprimé |
| AC-3206 | PASS | `test_08_memories` vert (116 s) contre `UITests/stubs/immich_stub_memories.py` |
| AC-3207 | PASS | 0 occurrence des types/titre inventés, 0 verbe fautif sur `{id}/assets` |
| AC-3208 | PASS | **772 tests, TEST SUCCEEDED** (baseline 749 ; +23) — `/tmp/immich_memories_test.log` |

**Preuve de contrat réseau** — journal du stub après `test_08_memories` (`GET /__requests`), c'est-à-dire ce que l'app a réellement envoyé :

```json
[{"method":"GET",    "path":"/api/memories",                                            "query":""},
 {"method":"PUT",    "path":"/api/memories/dddddddd-4444-4444-8444-000000000001",        "isSaved":true, "ids":null},
 {"method":"POST",   "path":"/api/memories",                                             "assetIds":["aaaaaaaa-1111-4111-8111-000000000001","aaaaaaaa-1111-4111-8111-000000000002"],
                                                                                          "memoryAt":"2026-09-13T00:00:00.000Z","type":"on_this_day","data":{"year":2026},"isSaved":true},
 {"method":"GET",    "path":"/api/memories",                                            "query":""},
 {"method":"PUT",    "path":"/api/memories/dddddddd-4444-4444-8444-000000000002/assets", "ids":["aaaaaaaa-1111-4111-8111-000000000003"]},
 {"method":"DELETE", "path":"/api/memories/dddddddd-4444-4444-8444-000000000002/assets", "ids":["aaaaaaaa-1111-4111-8111-000000000002"]},
 {"method":"DELETE", "path":"/api/memories/dddddddd-4444-4444-8444-000000000002/assets", "ids":["aaaaaaaa-1111-4111-8111-000000000001"]},
 {"method":"DELETE", "path":"/api/memories/dddddddd-4444-4444-8444-000000000002/assets", "ids":["aaaaaaaa-1111-4111-8111-000000000003"]},
 {"method":"DELETE", "path":"/api/memories/dddddddd-4444-4444-8444-000000000001",        "ids":null}]
```

Ce journal prouve les quatre points qu'un grep ne peut pas voir : `PUT` (jamais `PATCH`) pour l'update, `isSaved: true` sur le POST de création (l'invariant des 30 jours), `PUT`/`DELETE` — pas `POST` — sur `{id}/assets`, et la suppression de la mémoire vidée. Les captures `/tmp/shot-32…38` montrent la liste à 1 puis 2 cartes, le bookmark qui bascule, et l'état vide final.

**Écarts nets sur la suite** : `MemoriesViewModelTests` +16 (`19 → 35` fonctions `test_` du fichier) et `ImmichAPIClientTests` +7 (`35 → 42`) = **+23** ; suite 749 → **772**, `TEST SUCCEEDED`.

## Défauts trouvés en exécutant (et corrigés)

1. **La date choisie dérivait d'un jour selon le fuseau.** `DatePicker` rend un instant à minuit **local** ; en le formatant tel quel, la carte relisait la date en UTC (`MemoryCardPresentation.monthDayLabel` fixe le fuseau UTC pour qu'une mémoire ne dérive jamais) — « 4 mai » saisi à Tokyo ressortait « 3 mai ». Corrigé par `MemoriesViewModel.memoryAtString(for:)` : minuit UTC **du jour local choisi**, et `data.year` tiré du même `dayComponents`. Le test de création l'a attrapé (`hasPrefix("2019-05-04T")`), `test_memoryAtString_anchorsThePickedDayAtUTCMidnight` pinne la raison (aller-retour jusqu'au libellé affiché).
2. **Les deux routes « assets » ne parlent pas le même dialecte.** `PUT /api/memories/{id}/assets` répond `BulkIdResponseDto`, dont l'enum d'erreur est **`NO_PERMISSION`** (majuscules) — la route des liens partagés répond `AssetIdsResponseDto` avec `no_permission` (minuscules). Le premier jet du test de transport utilisait la casse des liens partagés et échouait en `decoding`. Corrigé dans la fixture, et l'assertion pinne désormais `BulkIdErrorReason` explicitement.
3. **`GET /api/memories/statistics` n'a pas d'usage de pagination ici.** `size`/`page` ne s'appliquent que si `size` est fourni (`memory.repository.ts:110`) et ce client ne le fournit pas : le total peut légitimement dépasser la longueur de la liste (le serveur compte les lignes, `search` filtre les vides). L'endpoint est câblé (il est nommé par #15, et c'est ce que le web utilise avec `size: 250`), sans écran consommateur — la limite est écrite dans le doc-comment du protocole et du DTO plutôt que masquée par un compteur trompeur.

## Correctif de stub (2026-09-13, après clôture)

`test_08_memories` était vert, mais ses captures montraient une grille de **vignettes cassées** : le stub servait un JPEG 1×1 que ImageIO **ne décode pas**, donc `AuthenticatedAsyncImage` tombait sur son placeholder d'échec. Défaut du harnais, pas de l'app. Corrigé dans `UITests/stubs/immich_stub_memories.py` :

1. vignettes = **PNG 8×8 généré** (`zlib`, couleur dérivée de l'asset id — chaque cellule de capture est donc distincte), `Content-Type: image/png` ;
2. réponses `Cache-Control: no-store`, et **`thumbhash` régénéré à chaque `/__reset`**. Le second point est le vrai piège : le `URLCache` de l'app est en `returnCacheDataElseLoad`, donc un corps illisible déjà en cache est rejoué **sans qu'aucune requête ne parte** — le premier correctif semblait sans effet (le stub servait déjà du PNG valide, la grille restait cassée, et le journal du stub montrait que la requête de vignette n'était plus émise du tout). Le `thumbhash` alimente le `c=` des URL de vignette, comme celui du vrai serveur, qui change quand les pixels changent.

Rejoué : `test_08_memories` **trois fois de suite**, vert (116 s, 0 échec). Les captures `/tmp/shot-32…38` montrent maintenant de vraies tuiles colorées.

**Flakiness trouvée au passage et corrigée** : `openMemoriesTab`/`openSharedTab` tapaient `app.tabBars.buttons[label]` sans `firstMatch` — iOS 26 rend la barre d'onglets dans ses formes étendue **et** minimisée pendant l'animation, la requête matchait deux boutons et `.tap()` levait « Find single matching element » (un run sur trois a échoué). Même classe que `app.tabBars.buttons["Albums"].tap()` (test_02) : les trois passent maintenant par `.firstMatch`, comme le `tapButton` du même fichier.

## Ce qui n'est PAS dans cette carte

- `MemoryType.first_day` / `.yearly_recap`, le champ **titre** de la feuille de création, et les verbes `PATCH`/`POST` sur `{id}/assets` : contraires au contrat serveur (voir le tableau du haut), jamais implémentés, et interdits par AC-3207.
- La **pagination** de la liste (le client charge toutes les mémoires en une requête : le serveur en crée quelques-unes par an) et l'affichage d'un total.
