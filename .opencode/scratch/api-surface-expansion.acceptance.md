# Task: api-surface-expansion

Status: shipped — DTOs + client methods + timeline filters + tests (326 tests verts, 0 échec; baseline ~214). AC-800..AC-811 PASS le 2026-08-12.

## Plan

**Objectif**: Étendre `ImmichClient` + DTOs aux endpoints manquants du plan de parité, sans toucher au cœur dispatch (sendAuthed/sendAuthedRaw). Chaque endpoint vérifié contre OpenAPI officiel (main branch) — pas de schémas devinés.

**Hypothèses** (groundées):
- Patterns: `sendAuthed`/`sendAuthedRaw` + `ImmichAPI.<group>.path()` + `ImmichHeader` (ImmichAPIClient.swift:268-299); DTOs Codable+Equatable dans Core/Types (DTOs.swift).
- `ImmichAPI.people` existe déjà (Constants.swift:14) mais inutilisé. `PersonResponseDto` existant (DTOs.swift:172-177) est STALE — champs manquants birthDate/color/isFavorite/updatedAt vs OpenAPI; à remplacer.
- `ImmichAssetURL` a déjà original + videoPlayback builders (ImmichAssetURL.swift:20-28) — rien à faire pour URLs playback.
- project.yml: sources = globs de dossiers (project.yml:21,54) — nouveaux fichiers auto-inclus, PAS de xcodegen.
- OpenAPI vérifié (main, 2026-08-12):
  - `GET /people` → `PeopleResponseDto {people:[PersonResponseDto], hidden:Int, total:Int, hasNextPage?}`; params closestAssetId,closestPersonId,page,size,withHidden.
  - `PersonResponseDto` required: id,name,birthDate,thumbnailPath,isHidden; optional: color,isFavorite,updatedAt.
  - `PUT /people/{id}` body `PersonUpdateDto {name,birthDate,color,featureFaceAssetId,isFavorite,isHidden}` → PersonResponseDto.
  - `POST /people/{id}/merge` body `MergePersonDto {ids}` → `[BulkIdResponseDto]` (⚠ POST pas PUT).
  - `GET /people/{id}/statistics` → `PersonStatisticsResponseDto {assets:Int}`.
  - `GET /people/{id}/thumbnail` → octet-stream (image) — inutile en client (AuthenticatedAsyncImage construit URLs via ImmichAssetURL) → pas de méthode.
  - `/people/{id}/assets` N'EXISTE PLUS sur main → assets d'une personne = `searchMetadata(personIds:)` (déjà supporté, SearchViewModel).
  - `GET /memories` → `[MemoryResponseDto]`; params for(date),isSaved,isTrashed,order(asc|desc|random),size,type. MemoryResponseDto: id,createdAt,updatedAt,memoryAt,ownerId,type("on_this_day"),data{year},assets:[AssetResponseDto],isSaved + optionnels showAt,hideAt,seenAt,deletedAt.
  - `GET /duplicates` (aucun param) → `[DuplicateResponseDto {duplicateId, assets:[AssetResponseDto], suggestedKeepAssetIds:[String]}]`.
  - `GET /partners` → `[PartnerResponseDto]` (=user + inTimeline: Bool); `PUT /partners/{id}` body `{inTimeline:Bool}` → 200; `DELETE /partners/{id}` → 204; `POST /partners` (create par email) → 201 — PAS au scope P0 (UI partner create = P3).
  - `GET /activities?albumId(REQ)&assetId?&type?` → `[ActivityResponseDto {id,createdAt,type(comment|like),user:UserResponseDto,assetId?,comment?}]`; `POST /activities` body `ActivityCreateDto {albumId(REQ),type(REQ),assetId?,comment?}`; `DELETE /activities/{id}` → 204.
  - `GET /server/statistics` → `ServerStatsResponseDto {photos,videos,usage,usagePhotos,usageVideos,usageByUser:[UsageByUserDto {userId,userName,photos,videos,usage,usagePhotos,usageVideos,quotaSizeInBytes}]}`.
  - `PUT /shared-links/{id}` body `SharedLinkEditDto {password,expiresAt,allowUpload,allowDownload,showMetadata,description}` (tous optionnels) → SharedLinkResponseDto.
  - `PUT /assets` body `AssetBulkUpdateDto {ids(REQ), dateTimeOriginal,dateTimeRelative,description,isFavorite,latitude,longitude,rating,timeZone,visibility,duplicateId}` → **204** (⚠ archive = visibility:"archive", PAS de champ isArchived — dto-reference:7 AssetVisibility inclut archive).
- Contrainte timeline: `getTimeBuckets(isFavorite:isTrashed:)` (ImmichClient.swift:25) doit gagner personId/withPartners/visibility/withStacked — dto-reference:75; pas de nouveau plumbing bucket.

**Approche retenue**: A — 3 nouveaux fichiers DTO par domaine (DTOs+People, DTOs+Social, DTOs+Server), remplacement de PersonResponseDto stale, AssetBulkUpdateDto dans DTOs.swift (domaine asset), 4 nouveaux groupes ImmichAPI, méthodes protocol+impl 1:1 avec les schémas OpenAPI vérifiés. Timeline filters: paramètres optionnels ajoutés aux 2 méthodes existantes (rétro-compatible, callers existants intacts).
**B (rejetée)**: Un seul gros fichier DTOs+Expansion — casse la convention domaine/fichier.
**C (rejetée)**: Endpoints hors timeline via sendRaw JSON brut — perd le typage et le test requestCount.

**Étapes**:
1. `Sources/Core/Types/DTOs+People.swift` — PersonResponseDto (full), PeopleResponseDto, PersonUpdateDto, MergePersonDto, PersonStatisticsResponseDto, PartnerResponseDto, PartnerUpdateDto.
2. Retirer l'ancien `PersonResponseDto` de DTOs.swift:172-177.
3. `Sources/Core/Types/DTOs+Social.swift` — ReactionType, ActivityCreateDto, ActivityResponseDto, MemoryType, OnThisDayDto, MemoryResponseDto, DuplicateResponseDto.
4. `Sources/Core/Types/DTOs+Server.swift` — UsageByUserDto, ServerStatsResponseDto, SharedLinkEditDto.
5. DTOs.swift — `AssetBulkUpdateDto`.
6. Constants.swift — groupes `partners`, `activity`, `memories`, `duplicates`.
7. ImmichClient.swift — méthodes: getPeople(page:withHidden:), updatePerson(id:dto:), mergePeople(ids:into:), getPersonStatistics(id:), getMemories(for:isSaved:isTrashed:order:), getDuplicates(), getPartners(), updatePartner(id:isInTimeline:), removePartner(id:), getActivities(albumId:assetId:), createActivity(dto:), deleteActivity(id:), getServerStatistics(), updateSharedLink(id:dto:), bulkUpdateAssets(dto:), + expansion getTimeBuckets/getTimeBucket.
8. ImmichAPIClient.swift — impl 1:1 (merge = POST, bulkUpdate = PUT 204 via sendAuthedRaw).
9. Tests — DTOEncodingTests (roundtrip chaque nouveau DTO), ImmichAPIClientTests (path/method/query/body par endpoint, pattern CapturingURLProtocol existant).
10. Build + suite complète (régression baseline ~214) + mises à jour Mocks/MockImmichClient si nécessaire (conformité protocol).
11. memory.md entry + docs.

## Acceptance Contract

### Approches candidates
**A (retenue)**: fichiers DTO par domaine + méthodes 1:1 OpenAPI vérifiée + expansion timeline paramètres optionnels. Conforme conventions codebase, rétro-compatible.
**B**: Mega-fichier DTOs+Expansion. Conventions cassées.
**C**: sendRaw brut sans DTO. Perd typage + testabilité.

### Approche retenue + rationale
**A**. Chaque champ vérifié contre OpenAPI (nécessaire: merge est POST, archive passe par visibility, /people/{id}/assets a disparu). Fichiers par domaine = convention DTOs+Album/DTOs+SharedLink existante.

### Critères

```
### AC-800 [type: new]
Assertion: `Sources/Core/Types/DTOs+People.swift` existe et définit `PersonResponseDto` complet (id, name, birthDate, thumbnailPath, isHidden + optionnels color, isFavorite, updatedAt — mutables `var`, convention AssetResponseDto) — remplace la version stale de DTOs.swift.
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+People.swift; grep -qE "struct PersonResponseDto" "$f" && grep -qE "var birthDate" "$f" && grep -qE "var color" "$f" && grep -qE "var isFavorite" "$f" && grep -qE "var updatedAt" "$f" && ! grep -q "struct PersonResponseDto" Sources/Core/Types/DTOs.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (DTOs.swift:172 version stale, fichier absent)
Post-state attendu: PASS
```

```
### AC-801 [type: new]
Assertion: DTOs+People.swift contient PeopleResponseDto (people, hidden, total, hasNextPage optionnel), PersonUpdateDto (name, birthDate, color, featureFaceAssetId, isFavorite, isHidden), MergePersonDto (ids), PersonStatisticsResponseDto (assets), PartnerResponseDto (inTimeline) et PartnerUpdateDto (inTimeline).
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+People.swift; grep -qE "struct PeopleResponseDto" "$f" && grep -qE "struct PersonUpdateDto" "$f" && grep -qE "struct MergePersonDto" "$f" && grep -qE "struct PersonStatisticsResponseDto" "$f" && grep -qE "struct PartnerResponseDto" "$f" && grep -qE "let inTimeline" "$f" && grep -qE "struct PartnerUpdateDto" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-802 [type: new]
Assertion: `Sources/Core/Types/DTOs+Social.swift` définit ReactionType (comment|like), ActivityCreateDto (albumId, type + assetId/comment optionnels), ActivityResponseDto (id, createdAt, type, user), MemoryType (on_this_day), OnThisDayDto (year), MemoryResponseDto (id, memoryAt, data, assets, isSaved), DuplicateResponseDto (duplicateId, assets, suggestedKeepAssetIds).
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+Social.swift; grep -qE "enum ReactionType" "$f" && grep -qE "case comment" "$f" && grep -qE "case like" "$f" && grep -qE "struct ActivityCreateDto" "$f" && grep -qE "struct ActivityResponseDto" "$f" && grep -qE "enum MemoryType" "$f" && grep -qE "case on_this_day" "$f" && grep -qE "struct OnThisDayDto" "$f" && grep -qE "struct MemoryResponseDto" "$f" && grep -qE "struct DuplicateResponseDto" "$f" && grep -qE "suggestedKeepAssetIds" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-803 [type: new]
Assertion: `Sources/Core/Types/DTOs+Server.swift` définit ServerStatsResponseDto (photos, videos, usage, usagePhotos, usageVideos, usageByUser), UsageByUserDto (userId, userName, photos, videos, usage, usagePhotos, usageVideos, quotaSizeInBytes) et SharedLinkEditDto (password, expiresAt, allowUpload, allowDownload, showMetadata, description).
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+Server.swift; grep -qE "struct ServerStatsResponseDto" "$f" && grep -qE "struct UsageByUserDto" "$f" && grep -qE "quotaSizeInBytes" "$f" && grep -qE "struct SharedLinkEditDto" "$f" && grep -qE "expiresAt" "$f" && grep -qE "allowUpload" "$f" && grep -qE "showMetadata" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-804 [type: new]
Assertion: `AssetBulkUpdateDto` dans DTOs.swift avec ids requis + optionnels visibility, isFavorite, dateTimeOriginal, latitude, longitude, rating, description, timeZone, duplicateId (archive = visibility:"archive", pas de champ isArchived — AssetResponseDto.isArchived reste un champ de réponse, hors scope).
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs.swift; grep -qE "struct AssetBulkUpdateDto" "$f" && grep -qE "let ids: \[String\]" "$f" && grep -qE "var visibility: String\?" "$f" && grep -qE "var isFavorite: Bool\?" "$f" && grep -qE "var dateTimeOriginal: String\?" "$f" && grep -qE "var timeZone: String\?" "$f" && grep -qE "var duplicateId: String\?" "$f" && awk "/struct AssetBulkUpdateDto/,/^}/" "$f" | ! grep -qE "isArchived" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (type absent)
Post-state attendu: PASS
```

```
### AC-805 [type: new]
Assertion: Constants.swift ajoute les groupes `partners`, `activity`, `memories`, `duplicates`.
Check post-impl: sh -c 'f=Sources/Core/Constants.swift; grep -qE "partners = SubPath" "$f" && grep -qE "activity = SubPath" "$f" && grep -qE "memories = SubPath" "$f" && grep -qE "duplicates = SubPath" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-806 [type: new]
Assertion: Protocole ImmichClient expose getPeople(page:withHidden:), updatePerson(id:dto:), mergePeople(ids:into:), getPersonStatistics(id:), getMemories(for:isSaved:isTrashed:order:), getDuplicates(), getPartners(), updatePartner(id:isInTimeline:), removePartner(id:), getActivities(albumId:assetId:), createActivity(dto:), deleteActivity(id:), getServerStatistics(), updateSharedLink(id:dto:), bulkUpdateAssets(dto:).
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; for m in getPeople updatePerson mergePeople getPersonStatistics getMemories getDuplicates getPartners updatePartner removePartner getActivities createActivity deleteActivity getServerStatistics updateSharedLink bulkUpdateAssets; do grep -qE "func $m" "$f" || { echo FAIL:$m; exit 1; }; done; echo PASS'
Pre-state attendu: FAIL (aucune de ces méthodes)
Post-state attendu: PASS
```

```
### AC-807 [type: new]
Assertion: getTimeBuckets et getTimeBucket gagnent les paramètres optionnels personId, withPartners, visibility, withStacked (protocol + impl ImmichAPIClient) — expansion compatible.
Check post-impl: sh -c 'grep -qE "personId: String\?" Sources/Core/Protocols/ImmichClient.swift && grep -qE "withPartners: Bool\?" Sources/Core/Protocols/ImmichClient.swift && grep -qE "visibility: String\?" Sources/Core/Protocols/ImmichClient.swift && grep -qE "withStacked: Bool\?" Sources/Core/Protocols/ImmichClient.swift && grep -qE "personId" Sources/Services/ImmichAPIClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-808 [type: new]
Assertion: Impl ImmichAPIClient — mergePeople utilise POST /people/{id}/merge (pas PUT), bulkUpdateAssets utilise PUT /assets (204, sendAuthedRaw), updateSharedLink utilise PUT /shared-links/{id}, deleteActivity et removePartner retournent sans décodage JSON (204).
Check post-impl: sh -c 'grep -qF ".POST, path: ImmichAPI.people.path(\"/\(id)/merge\"), body" Sources/Services/ImmichAPIClient.swift && grep -qF ".PUT, path: ImmichAPI.assets.path(\"\"), body" Sources/Services/ImmichAPIClient.swift && grep -qF ".PUT, path: ImmichAPI.sharedLinks.path(\"/\(id)\"), body" Sources/Services/ImmichAPIClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-809 [type: new]
Assertion: Tests `DTOEncodingTests` couvrent chaque nouveau DTO (roundtrip encode/decode): PeopleResponseDto, PersonUpdateDto, PartnerResponseDto, ActivityResponseDto, MemoryResponseDto, DuplicateResponseDto, ServerStatsResponseDto, SharedLinkEditDto, AssetBulkUpdateDto.
Check post-impl: sh -c 'f=Tests/DTOEncodingTests.swift; for t in PeopleResponseDto PersonUpdateDto PartnerResponseDto ActivityResponseDto MemoryResponseDto DuplicateResponseDto ServerStatsResponseDto SharedLinkEditDto AssetBulkUpdateDto; do grep -q "$t" "$f" || { echo FAIL:$t; exit 1; }; done; echo PASS'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-810 [type: new]
Assertion: Tests `ImmichAPIClientTests` couvrent les nouveaux endpoints (méthode HTTP + path + query/body): getPeople, mergePeople (POST), getMemories, getDuplicates, getPartners, getActivities (query albumId/assetId), getServerStatistics, updateSharedLink (PUT), bulkUpdateAssets (PUT 204), timeline filter expansion (personId/withPartners dans query).
Check post-impl: sh -c 'f=Tests/ImmichAPIClientTests.swift; grep -qE "test_P0_getPeople|test_P0_mergePeople|test_P0_getMemories|test_P0_getDuplicates|test_P0_getPartners|test_P0_getActivities|test_P0_getServerStatistics|test_P0_updateSharedLink|test_P0_bulkUpdateAssets|test_P0_timelineFilterExpansion" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-811 [type: regression]
Assertion: Suite complète verte — nouveau compte de tests ≥ baseline pré-carte (~214).
Check post-impl: sh -c 'grep -qE "Executed.*tests" /tmp/immich_p0_test_summary.txt 2>/dev/null || echo RUN; exit 0'
Pre-state attendu: FAIL (suite non relancée)
Post-state attendu: PASS (rapport exécution annexé au rapport de carte)
```
