# Task: shared-link-viewer

Status: **livré** — carte créée le 2026-09-13 en **retrait du périmètre de #17** (shared-links-enriched), réécrite sur le contrat réel puis implémentée le même jour. Issue **#22**.

## Pourquoi cette carte existe

`shared-links-enriched.acceptance.md` (version du 8 septembre) et l'issue #17 demandaient trois routes pour un « viewer public » : `GET /shared-links/public/:slug`, `POST /shared-links/:slug/assets`, `POST /shared-links/:slug/check-password`. **Aucune n'existe**, et le client Flutter n'a pas cette feature non plus (seulement une page liste + une page création/édition). C'est donc une feature **neuve**, pas un écart de parité : elle a sa carte, au lieu de gonfler #17.

## Contrat réel (vérifié le 2026-09-13, re-vérifié à l'implémentation)

| Besoin | Route réelle |
|---|---|
| Ouvrir un lien reçu | `GET /api/shared-links/me` avec `?key=<base64url>` **ou** `?slug=<slug>` (auth `sharedLink: true`) |
| Vérifier un mot de passe | `POST /api/shared-links/login` avec `?key=`/`?slug=` et body `{password}` → renvoie le DTO **et pose un cookie** |
| Lister les photos d'un lien ALBUM | `POST /api/search/metadata?key=` avec `albumIds: [id]` — **seule** recherche autorisée sous auth partagée |
| Lister les photos d'un lien INDIVIDUAL | aucune route : le DTO les porte (`assets`) |
| Uploader depuis un lien | `POST /api/assets?key=…` (multipart), gardé par `requireUploadAccess` : **401 si `allowUpload` est faux** |

Preuves : OpenAPI `main` (`open-api/immich-openapi-specs.json`, sha256 `bace1792…` : `GET /shared-links/me` et `POST /shared-links/login` portent seuls les params `key`/`slug`) ; `server/src/controllers/shared-link.controller.ts` (`@Get('me')`, `@Post('login')`) ; `server/src/services/shared-link.service.ts` (`getMine` compare le token de cookie, `login` renvoie `{sharedLink, token}`) ; `server/src/middleware/auth.guard.ts` + `services/auth.service.ts:238` (le `key`/`slug` de la **query** est ce qui authentifie) ; `server/src/utils/access.ts` (`requireUploadAccess`) ; `server/src/services/search.service.ts:93` (`"Shared link access is only allowed in combination with an albumIds filter"`) ; `server/src/services/asset-media.service.ts:262` (`edited = true` forcé pour un shared link — c'est ce qui rend `size=fullsize` sûr) ; `web/src/lib/utils/shared-links.ts` (`loadSharedLink` : `error.data.message === 'Password required'`).

## Ce qui a été construit

**Transport (le vrai prérequis)** — `ImmichAPIClient.sendSharedLinkRaw` est un chemin distinct : pas de bearer, credential en query, cookie de login rejoué, et **401 qui n'atteint jamais `authDelegate`** (un 401 ici parle du lien, pas de la session — `sendAuthedRaw` aurait déconnecté l'utilisateur, et `sendNoAuth` est le chemin pré-login). Le cookie vit en mémoire (`_sharedLinkCookie`), un seul slot : le serveur valide le token contre *son* lien, un token périmé est simplement ignoré.

**4 méthodes visiteur** sur `ImmichClient` + `ImmichAPIClient` : `getSharedLinkMine`, `loginToSharedLink`, `getSharedLinkAlbumAssets`, `uploadAssetToSharedLink`. Types : `SharedLinkCredential` (enum `key`/`slug` — le serveur lit l'un **ou** l'autre, jamais les deux), `SharedLinkLoginDto`, et `SharedLinkURL.reference(from:)` qui lit un lien collé (`/s/<slug>`, `/share/<key>`, sans schéma, ou jeton nu désambiguïsé par forme).

**Écran** — `Sources/Features/SharedLinks/` : `SharedLinkViewerViewModel` (phases `entry`/`passwordRequired`/`loading`/`opened`/`deadLink`/`failed`, pagination de l'album, upload invité) et `SharedLinkViewerView` (feuille depuis l'onglet Partage, grille, pager plein écran réutilisant `ZoomableImageView`). `AssetThumbnailCell` gagne `sharedLink:` (credential dans l'URL de vignette + menu contextuel du propriétaire supprimé) ; `ImmichAssetURL` gagne le même paramètre.

## Critères (rejouables)

```
### AC-4000 [type: new]
Assertion: le client expose la lecture d'un lien par clé/slug, sans bearer.
Check post-impl: sh -c 'for s in getSharedLinkMine loginToSharedLink getSharedLinkAlbumAssets uploadAssetToSharedLink; do grep -q "func $s" Sources/Core/Protocols/ImmichClient.swift || exit 1; grep -q "func $s" Sources/Services/ImmichAPIClient.swift || exit 1; done; grep -q "func sendSharedLinkRaw" Sources/Services/ImmichAPIClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (les 4 méthodes n'existaient pas)
Post-state attendu: PASS
```

```
### AC-4001 [type: new]
Assertion: transport asservi — la lecture sort sans en-tête `Authorization`, avec le credential en query, et son 401 ne déconnecte pas la session.
Check post-impl: sh -c 'grep -qE "Test Case .*test_SLV_getMine_sendsKeyWithoutBearer[^ ]* passed" /tmp/immich_sharedlinkviewer_unit.log && grep -qE "Test Case .*test_SLV_getMine_sendsSlugWhenTheLinkHasOne[^ ]* passed" /tmp/immich_sharedlinkviewer_unit.log && grep -qE "Test Case .*test_SLV_getMine_surfacesTheLinksOwn401WithoutSigningOut[^ ]* passed" /tmp/immich_sharedlinkviewer_unit.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL (journal absent)
Post-state attendu: PASS
```

```
### AC-4002 [type: new]
Assertion: `POST /api/shared-links/login` porte `{password}` et le cookie de session est conservé — la requête suivante le rejoue.
Check post-impl: sh -c 'grep -qE "Test Case .*test_SLV_login_postsPasswordAndKeepsCookie[^ ]* passed" /tmp/immich_sharedlinkviewer_unit.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL (journal absent)
Post-state attendu: PASS
```

```
### AC-4003 [type: new]
Assertion: scénario de bout en bout sur stub committé — lien à slug protégé par mot de passe : refus puis succès, lecture par cookie, recherche album, lien mort, lien sans upload.
Check post-impl: sh -c 'test -f UITests/stubs/immich_stub_shared_link_viewer.py && grep -qE "Test Case .*test_SLV_viewer.* passed" /tmp/immich_sharedlinkviewer_uitest.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL (stub et scénario absents)
Post-state attendu: PASS
```

```
### AC-4004 [type: guard]
Assertion: aucune route inventée (`public/:slug`, `:slug/assets`, `check-password`) n'apparaît dans le code.
Check post-impl: sh -c '! grep -rqE "shared-links/public|checkSharedLinkPassword|getSharedLinkPublic|uploadToSharedLink\(" Sources/ && echo PASS || echo FAIL'
Pre-state attendu: PASS
Post-state attendu: PASS
```

```
### AC-4005 [type: regression]
Assertion: suite unitaire ≥ 805 (baseline 772 du 2026-09-13), TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_sharedlinkviewer_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_sharedlinkviewer_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 805 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (le pré-état mesuré, 772, est sous le seuil)
Post-state attendu: PASS
```

**Le seuil de AC-4005 est celui de la suite unitaire** (`-only-testing:ImmichSwiftUITests`). Un `xcodebuild test` complet embarque les scénarios XCUITest, qui exigent chacun *leur* stub sur le port 8421 : un run unique ne peut pas être vert pour `test_05`/`test_06`/`test_07`/`test_08`/`test_SLV_viewer` à la fois. Le journal des scénarios est donc le leur (`/tmp/immich_sharedlinkviewer_uitest.log`), et la régression se compte sur la suite unitaire.

## Pré-état mesuré (2026-09-13, HEAD `e318d44`)

| AC | Pré-état | Sortie |
|----|----------|--------|
| AC-4000 | FAIL | 5 routes partagées seulement (`getSharedLinks`, `createSharedLink`, `updateSharedLink`, `addAssetsToSharedLink`, `deleteSharedLink`) ; `sendAuthedRaw` exige un token (`ImmichAPIClient.swift:601`) |
| AC-4001 | FAIL | 0 test `test_SLV_*` |
| AC-4002 | FAIL | 0 test `test_SLV_*` |
| AC-4003 | FAIL | stub et scénario absents |
| AC-4004 | PASS | 0 occurrence (garde) |
| AC-4005 | FAIL | 772 tests, pas de journal de scénario |

## Résultat (2026-09-13) — **6/6 AC PASS**

| AC | Résultat | Preuve |
|----|----------|--------|
| AC-4000 | PASS | 4 méthodes + `sendSharedLinkRaw` ; `SharedLinkCredential`, `SharedLinkLoginDto`, `SharedLinkURL.reference(from:)` |
| AC-4001 | PASS | 6 tests `test_SLV_*` de transport verts (`/tmp/immich_sharedlinkviewer_unit.log`) |
| AC-4002 | PASS | cookie `immich_shared_link_token` rejoué sur la requête suivante, pinné par le nom de la constante |
| AC-4003 | PASS | `test_SLV_viewer` vert (112 s) contre `UITests/stubs/immich_stub_shared_link_viewer.py`, **deux runs consécutifs** |
| AC-4004 | PASS | 0 occurrence des routes fantômes |
| AC-4005 | PASS | **805 tests, TEST SUCCEEDED** (772 → 805, +33) — `/tmp/immich_sharedlinkviewer_test.log` |

**Preuve de contrat réseau** — journal du stub après `test_SLV_viewer` (`GET /__requests`), c'est-à-dire ce que l'app a réellement envoyé (`cookie=true` = le cookie de login était présent ; `auth=false` = aucun bearer) :

```
GET  /api/shared-links/me      slug=trip-2026  cookie=false auth=false
POST /api/shared-links/login   slug=trip-2026  cookie=false auth=false  password=nope
POST /api/shared-links/login   slug=trip-2026  cookie=false auth=false  password=hunter2
GET  /api/shared-links/me      slug=trip-2026  cookie=true  auth=false        ← la lecture qui débloque
POST /api/search/metadata      albumIds=["22222222-2222-4222-8222-000000000002"]
GET  /api/assets/<id>/thumbnail?size=thumbnail&c=&slug=trip-2026              ← les vignettes publiques
GET  /api/shared-links/me      slug=open-link  cookie=false auth=false
GET  /api/shared-links/me      slug=gone-2026  cookie=false auth=false  → 401
```

Ce journal prouve les quatre points qu'un grep ne peut pas voir : le **401 initial** sur un lien protégé, le **cookie** qui fait passer la lecture suivante (le stub garde `/me` sur `is_has_session_cookie`, comme `SharedLinkService.getMine`), le **refus du mauvais mot de passe**, et l'**absence totale de bearer** — l'app est connectée, un `Authorization` accidentel aurait lu le lien en tant que propriétaire. Les captures `/tmp/shot-69…74` montrent l'écran d'entrée, l'invite de mot de passe, la grille de l'album, le pager plein écran, le lien en lecture seule et le lien mort.

**Écarts nets sur la suite** : `SharedLinkViewerViewModelTests` +20 (nouveau fichier, 20 tests), `SharedLinkURLTests` +6 (`5 → 11`), `ImmichAPIClientTests` +7 (`42 → 49`) = **+33** ; suite 772 → **805**, `TEST SUCCEEDED`.

## Défauts trouvés en exécutant (et corrigés)

1. **Un 401 de lien déconnectait l'application.** Le chemin visiteur réutilisait `validate`, qui prévient `authDelegate` sur tout 401 (FM-4) : demander le mot de passe d'un lien aurait renvoyé l'utilisateur à l'écran de connexion. Corrigé par `validateSharedLinkResponse` (aucune notification) + journalisation du corps brut, seul discriminateur entre « mot de passe requis », « mot de passe faux » et « lien mort ». Pinné par `test_SLV_getMine_surfacesTheLinksOwn401WithoutSigningOut` (compteur du délégué à 0).
2. **`XCTAssertTrue` sur `Authorization` absent ne suffit pas.** Le test de transport passait avec un `?key=` correct mais un chemin qui aurait pu être le chemin authentifié : le stub journalise désormais la présence de l'en-tête, et le scénario l'asserte sur chaque visite.
3. **Vignette publique : `size=fullsize` redirige vers `original`.** `AssetMediaService.viewThumbnail` renvoie `{targetSize: 'original'}` quand fullsize est demandé sur une image web-supportée — une route qui exige `AssetDownload`, qu'un lien peut ne pas accorder. Le serveur force `edited = true` sous auth partagée, ce qui neutralise la redirection ; sans cela, les photos d'un lien en lecture seule auraient été cassées en plein écran.
4. **Un lien ALBUM n'a pas d'assets dans son DTO.** `AlbumResponseDto` n'a pas de champ `assets` (vérifié dans `mapAlbum`), et la recherche sans filtre est refusée sous auth partagée — d'où `searchMetadata(albumIds:)`, sinon la grille d'un lien album serait vide.
5. **Faux négatif du harnais : vignettes en cache.** `AuthenticatedAsyncImage` met les vignettes en cache disque par URL ; avec des ids d'assets fixes, le deuxième run trouvait les images en cache et la requête prouvant le credential n'était plus émise — le scénario passait une fois puis échouait. Le stub régénère donc ses ids d'assets à chaque `/__reset`, et le scénario cherche les cellules par préfixe d'identifiant.
6. **Vignettes illisibles dans les stubs.** Les octets JPEG 1×1 embarqués (ici et dans `immich_stub_memories.py`) ne se décodent pas — `ImageIO` échoue, les tuiles tombent sur le placeholder d'échec et une capture montre une grille d'images cassées alors que l'app est correcte. **Corrigé le 2026-09-13** dans les deux stubs qui servent une grille : PNG 8×8 généré (`zlib`, couleur dérivée de l'id), servi avec `Cache-Control: no-store`. Le `immich_stub_shared_links.py` ne sert aucune vignette, il n'était pas concerné.

## Résidu i18n (même classe que backup / partners / memories)

Les ~18 chaînes neuves (« Open a shared link », « Password required », « Read only », « This link is no longer available », « That password is not right. », …) **n'ont pas d'entrée dans `Resources/Localizable.xcstrings`** : l'extraction de Xcode ne tourne pas en build CLI, et un build Xcode incrémental supprime des clés valides. Les libellés déjà connus du catalogue s'affichent localisés (« Close » → « Fermer »), les neufs restent en anglais — exactement le mix visible sur les captures. Périmètre de #21 (i18n).

## Suivi (non bloquant)

- L'upload invité n'est **pas** piloté par le scénario : le sélecteur de photos est un `PHPickerViewController` hors processus, que XCUITest ne peut pas manipuler. Il est couvert par les tests unitaires (chemin, refus 401, recharge) et par le stub, qui modélise la route et son garde-fou.
- `allowDownload` est affiché mais n'ajoute pas d'action de téléchargement : `GET /assets/{id}/original` est déjà wire côté propriétaire ; le geste invité (enregistrer dans Photos) reste à spécifier.
