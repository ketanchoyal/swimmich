# Task: shared-links-enriched

Status: done — **10/10 AC PASS** (2026-09-13). Suite complète **749 tests, TEST SUCCEEDED** (iPhone 17 ; baseline 736 sur `HEAD` `7034dd7`), scénario de bout en bout `test_07_sharedLinks` vert contre le stub **committé** `UITests/stubs/immich_stub_shared_links.py`. Carte **réécrite le 2026-09-13 sur le contrat réel du serveur** (l'originale décrivait une surface qui n'existe pas) ; pré-état de chaque check mesuré avant implémentation (voir plus bas).

## Ce que la carte d'origine affirmait à tort (corrigé ici, comme pour partners-ui)

| Affirmation d'origine | Réalité vérifiée | Preuve |
|---|---|---|
| `GET /api/shared-links/public/:slug` — accès public sans token pour la preview | **n'existe pas.** La visite d'un lien public est `GET /api/shared-links/me?key=<base64url>` ou `?slug=<slug>`, le scope passant par les query params `key`/`slug` (`ImmichQuery`) résolus par `AuthService.validateSharedLinkKey/Slug` | OpenAPI `main` (`/shared-links/me` seuls, security `sharedLink`), `server/src/controllers/shared-link.controller.ts:91` |
| `POST /api/shared-links/:slug/assets` — upload depuis un lien public | **n'existe pas.** L'ajout d'assets par le **propriétaire** est `PUT /api/shared-links/{id}/assets` (body `AssetIdsDto`, `type == INDIVIDUAL` sinon 400, permission `SharedLinkUpdate`) ; l'upload par un **visiteur** est la route ordinaire `POST /api/assets?key=…`, gardée par `requireUploadAccess` (401 si `allowUpload` est faux) | OpenAPI (`/shared-links/{id}/assets` → `put`, `delete`), `shared-link.controller.ts:151`, `server/src/services/shared-link.service.ts:150-155` |
| `POST /api/shared-links/:slug/check-password` | **n'existe pas.** `POST /shared-links/login` body `{password}` avec `?key=`/`?slug=` → renvoie le DTO + pose un cookie | OpenAPI (`/shared-links/login`), `shared-link.controller.ts:69` |
| « `copy-link` manquant » | **déjà livré** : `SharedLinksView.swift` (UIPasteboard dans `SharedLinkRow`) + `PhotoShareViewModel` | `git grep UIPasteboard` |
| « expiry picker manquant » | **existe** (`EditSharedLinkSheet`, `DatePicker` + `hasExpiry`) ; il ne manque que les **presets** | `EditSharedLinkSheet.swift` (version d'origine) |
| `PUT /api/shared-links/{id}` = édition | le serveur n'expose que **`PATCH`** (`@Patch(':id')`). Le client envoyait `PUT` → **404 au runtime**, alors que `test_P0_updateSharedLink_hitsPutEndpoint` était vert (il pinnait le verbe faux) | OpenAPI `/shared-links/{id}` → `delete,get,patch` ; `shared-link.controller.ts:124` |
| Le slug est le chemin URL `/share/{slug}` | le chemin dépend du slug : `${base}/s/<slug>` s'il existe, sinon `${base}/share/<key>`, et `base = externalDomain` si non vide, sinon l'URL du serveur | `mobile/lib/utils/url_helper.dart` `buildSharedLinkUrl` ; routes web `(user)/s/[slug]` et `/share/[key]` |

**Décision de périmètre** : le **viewer public** (ouvrir un lien reçu, upload invité, saisie de mot de passe) est une feature **neuve sans parité Flutter** — le client mobile n'a qu'une page liste + une page création/édition — et il exige une plomberie d'auth absente (`sendAuthedRaw` exige un bearer et jette `APIError.unauthorized` sinon ; `ImmichHeader` n'a aucune notion de clé de partage). Il est **retiré de #17** et devient la carte + l'issue **#22** (`.opencode/scratch/shared-link-viewer.acceptance.md`), au lieu de gonfler cette tâche de trois routes inventées.

## Périmètre réel (les 5 écarts vs Flutter)

1. **Bug — builder d'URL publique.** Flutter : `externalDomain` sinon serveur, puis `/s/<slug>` sinon `/share/<key>`. L'app hardcode `/share/<key>` à deux endroits (`SharedLinksView.swift` dans `SharedLinkRow.url`, `PhotoShareViewModel.swift` dans `createPublicLink`) → lien mort pour un slug ou un serveur derrière reverse-proxy. L'issue #17 ne le mentionne pas.
2. **Champ `slug`** absent de `SharedLinkCreateDto` et `SharedLinkEditDto` alors que le serveur l'accepte sur les deux routes (`slug` nullable, « Custom URL slug »). Flutter l'envoie à la création et à l'édition, avec le préfixe `/s/` affiché dans le champ.
3. **Presets d'expiration** : Flutter en a 9 (Never, 30 min, 1 h, 6 h, 1 j, 7 j, 30 j, 90 j, 1 an) + date/heure ; l'app a un `DatePicker` nu.
4. **Feuille de partage** : Flutter offre `Share.share(link)` à côté du copier ; l'app n'a que `UIPasteboard`.
5. **Retour post-création** : Flutter copie le lien et affiche un écran « lien prêt » ; l'app ajoute la ligne et ferme.

**Détail serveur à respecter** : `SharedLinkService.update` écrit `slug: dto.slug || null` — un slug **omis est effacé** (à la différence de `password`/`expiresAt`, simplement laissés intacts). Le formulaire d'édition doit donc toujours renvoyer le slug courant, jamais l'omettre — c'est ce que fait Flutter (`slug = slugController.text != existing ? … : existingLink!.slug`). `SharedLinkCreateDto.type` reste requis ; `PUT /shared-links/{id}/assets` ne vaut que pour un lien `INDIVIDUAL`.

**Aucune des cinq routes inventées ne doit réapparaître** : `checkSharedLinkPassword`, `getSharedLinkPublic`, `uploadToSharedLink` sont supprimés du périmètre (AC-3908).

## Plan

**Étapes**

1. **NEW `Sources/Core/Utilities/SharedLinkURL.swift`** — un seul builder : `base = externalDomain` (trim, slash final normalisé) si non vide, sinon l'URL du serveur ; chemin `s/<slug>` si slug non vide, sinon `share/<key>` ; `nil` si aucune base. Les deux appelants migrent, l'ancien code disparaît.
2. **DTOs** — `slug: String?` sur `SharedLinkCreateDto` (`DTOs+SharedLink.swift`) et `SharedLinkEditDto` (`DTOs+Server.swift`) ; commentaire de route `PUT` → `PATCH`.
3. **Client** — `updateSharedLink` passe en `.PATCH` (le verbe `PUT` rend 404) ; `addAssetsToSharedLink(id:assetIds:)` → `PUT /api/shared-links/{id}/assets` body `AssetIdsDto` (miroir de surface, convention `api-surface-expansion`).
4. **`AuthViewModel.restoreSession()`** — récupère aussi `serverConfig()` : `externalDomain` n'était chargé qu'au passage par l'onboarding, donc inconnu après un relaunch (le builder retombait sur l'URL du serveur).
5. **`SharedLinkExpiryPicker`** (NEW) — 9 presets + date/heure, partagé par la création et l'édition.
6. **`CreateSharedLinkSheet`** — champ slug (`/s/` en préfixe), presets, puis écran « lien prêt » qui copie et offre `ShareLink`.
7. **`EditSharedLinkSheet`** — champ slug (toujours renvoyé) + presets.
8. **`SharedLinkSheet`** (album) — slug + presets à la création, `SharedLinkURL` au lieu de `baseURL`.
9. **`SharedLinkRow`** — URL via le builder + `ShareLink` à côté du copier (la ligne est partagée par l'onglet Shared et la feuille d'album).
10. **`PhotoShareViewModel`** — URL via le builder.
11. **Tests** — `SharedLinkURLTests` (4 cas), 3 tests de transport (`CapturingURLProtocol`), tests VM, scénario XCUITest `test_07_sharedLinks` sur stub **committé**.
12. **Catalogue** — les chaînes neuves extraites dans `Resources/Localizable.xcstrings` et commitées (les traductions `fr` restent le périmètre de #21).

**Approches candidates** — **A (retenue)** : corriger le contrat + livrer les 5 écarts, viewer public en carte séparée. **B** (rejetée) : livrer le viewer public dans #17 → périmètre doublé pour une feature sans parité et sans plomberie d'auth. **C** (rejetée) : ne livrer que copy-link → 20 % des écarts.

## Critères

Chaque check est rejouable tel quel. Les checks d'exécution lisent un journal de run (`grep` sur une **sortie de test**, jamais sur la source — [f53ab10f]).

```
### AC-3900 [type: new]
Assertion: un seul builder d'URL existe et les deux appelants ne construisent plus l'URL à la main.
Check post-impl: sh -c 'test -f Sources/Core/Utilities/SharedLinkURL.swift && grep -q -e /s/ Sources/Core/Utilities/SharedLinkURL.swift && grep -q -e /share/ Sources/Core/Utilities/SharedLinkURL.swift && ! grep -q -e /share/ Sources/Features/SharedLinks/SharedLinksView.swift && ! grep -q -e /share/ Sources/Features/PhotoViewer/PhotoShareViewModel.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (SharedLinkURL.swift absent, /share/ présent dans les 2 appelants)
Post-state attendu: PASS
```

```
### AC-3901 [type: new]
Assertion: 4 cas d'URL passent — slug → /s/<slug> ; sans slug → /share/<key> ; externalDomain prioritaire ; serveur sinon.
Check post-impl: sh -c 'n=$(grep -cE "Test Case .*SharedLinkURLTests test_.* passed" /tmp/immich_sharedlinks_unit.log); test "$n" -ge 4 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (classe absente, journal absent)
Post-state attendu: PASS
```

```
### AC-3902 [type: new]
Assertion: POST /api/shared-links envoie le slug (transport asservi).
Check post-impl: sh -c 'grep -qE "Test Case .*ImmichAPIClientTests test_SL_createSharedLink_sendsSlug[^ ]* passed" /tmp/immich_sharedlinks_unit.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3903 [type: new]
Assertion: PATCH /api/shared-links/{id} (verbe corrigé) envoie le slug.
Check post-impl: sh -c 'grep -qE "Test Case .*ImmichAPIClientTests test_SL_updateSharedLink_sendsSlugToPatchEndpoint[^ ]* passed" /tmp/immich_sharedlinks_unit.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL (le test existant pinnait PUT)
Post-state attendu: PASS
```

```
### AC-3904 [type: new]
Assertion: PUT /api/shared-links/{id}/assets avec le corps AssetIdsDto.
Check post-impl: sh -c 'grep -qE "Test Case .*ImmichAPIClientTests test_SL_addAssetsToSharedLink_putsAssetIdsDto[^ ]* passed" /tmp/immich_sharedlinks_unit.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3905 [type: new]
Assertion: la création envoie slug + expiration et renvoie le lien créé (écran « lien prêt »).
Check post-impl: sh -c 'grep -qE "Test Case .*SharedLinksViewModelTests test_createAlbumLink_sendsSlugAndExpiryAndReturnsLink[^ ]* passed" /tmp/immich_sharedlinks_unit.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3906 [type: new]
Assertion: scénario de bout en bout sur stub committé — créer un lien à slug, lire l'URL affichée, la copier.
Check post-impl: sh -c 'test -f UITests/stubs/immich_stub_shared_links.py && grep -qE "Test Case .*test_07_sharedLinks.* passed" /tmp/immich_sharedlinks_uitest.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL (stub et scénario absents)
Post-state attendu: PASS
```

```
### AC-3907 [type: new]
Assertion: les 18 chaînes d'UI neuves sont dans le catalogue (source EN extraite).
Check post-impl: sh -c 'python3 -c "import json;d=json.load(open(\"Resources/Localizable.xcstrings\"))[\"strings\"];ks=[\"Custom URL\",\"Expiration\",\"Expires %@\",\"Expiry date\",\"30 minutes\",\"1 hour\",\"6 hours\",\"1 day\",\"7 days\",\"30 days\",\"90 days\",\"1 year\",\"Never\",\"Custom…\",\"Copy link\",\"Copied\",\"Share link\",\"Link ready\"];m=[k for k in ks if k not in d];assert not m, m" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune de ces clés n'existe)
Post-state attendu: PASS
```

```
### AC-3908 [type: guard]
Assertion: aucune des 3 routes inventées par la carte d'origine ne subsiste dans le code.
Check post-impl: sh -c '! grep -rqE "shared-links/public|shared-links/:slug|checkSharedLinkPassword|getSharedLinkPublic|uploadToSharedLink" Sources/ && echo PASS || echo FAIL'
Pre-state attendu: PASS (jamais implémentées — la garde interdit leur réapparition)
Post-state attendu: PASS
```

```
### AC-3909 [type: regression]
Assertion: suite complète ≥ 736 (baseline 7034dd7), TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_sharedlinks_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_sharedlinks_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 736 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (journal absent)
Post-state attendu: PASS
```

## Pré-état mesuré (2026-09-13, HEAD `7034dd7`)

Chaque check `sh -c` de la carte a été rejoué avant toute implémentation. Attendu : tous FAIL sauf AC-3908 (garde), dont la valeur post-impl doit être identique.

| AC | Pré-état | Sortie |
|----|----------|--------|
| AC-3900 | FAIL | `SharedLinkURL.swift` absent ; `/share/` présent dans les deux appelants |
| AC-3901 | FAIL | `/tmp/immich_sharedlinks_unit.log` absent (classe `SharedLinkURLTests` inexistante) |
| AC-3902 | FAIL | test absent |
| AC-3903 | FAIL | le seul test d'édition pinnait `PUT` (`test_P0_updateSharedLink_hitsPutEndpoint`) |
| AC-3904 | FAIL | méthode absente du protocole |
| AC-3905 | FAIL | `createAlbumLink` renvoie `Bool` |
| AC-3906 | FAIL | `UITests/stubs/immich_stub_shared_links.py` absent |
| AC-3907 | FAIL | 0/16 clés présentes |
| AC-3908 | PASS | 0 occurrence des 3 routes inventées |
| AC-3909 | FAIL | journal absent |

## Résultat (2026-09-13) — **10/10 AC PASS**

| AC | Résultat | Preuve |
|----|----------|--------|
| AC-3900 | PASS | `Sources/Core/Utilities/SharedLinkURL.swift` (builder unique) ; 0 occurrence de `/share/` dans `SharedLinksView.swift` et `PhotoShareViewModel.swift` |
| AC-3901 | PASS | `SharedLinkURLTests` : 5 tests verts (slug, sans slug + slug blanc, externalDomain prioritaire, externalDomain vide, normalisation slash/host nu) |
| AC-3902 | PASS | `ImmichAPIClientTests.test_SL_createSharedLink_sendsSlug` — POST `/api/shared-links`, corps `slug: trip-2026`, `albumId`, `expiresAt` |
| AC-3903 | PASS | `ImmichAPIClientTests.test_SL_updateSharedLink_sendsSlugToPatchEndpoint` — **PATCH** `/api/shared-links/l1`, corps `slug` + `description` |
| AC-3904 | PASS | `ImmichAPIClientTests.test_SL_addAssetsToSharedLink_putsAssetIdsDto` — PUT `/api/shared-links/l1/assets`, corps `assetIds`, réponse `AssetIdsResponseDto` (dont `error: "no_permission"`) |
| AC-3905 | PASS | `SharedLinksViewModelTests.test_createAlbumLink_sendsSlugAndExpiryAndReturnsLink` — slug trimé, `expiresAt` ISO, lien renvoyé puis ajouté à la liste |
| AC-3906 | PASS | `test_07_sharedLinks` vert (82 s) contre `UITests/stubs/immich_stub_shared_links.py` ; URL lue à l'écran = `https://photos.stub.test/s/trip-2026` |
| AC-3907 | PASS | 18 clés dans `Resources/Localizable.xcstrings` (372 clés au total, +18) |
| AC-3908 | PASS | 0 occurrence de `shared-links/public`, `checkSharedLinkPassword`, `getSharedLinkPublic`, `uploadToSharedLink` dans `Sources/` |
| AC-3909 | PASS | **749 tests, TEST SUCCEEDED** (baseline 736 ; +13 nets) — `/tmp/immich_sharedlinks_test.log` |

**Preuve de contrat réseau** — journal du stub après `test_07_sharedLinks` (`GET /__requests`), c'est-à-dire ce que l'app a réellement envoyé :

```json
[{"method":"GET","path":"/api/shared-links","query":""},
 {"method":"POST","path":"/api/shared-links","type":"ALBUM",
  "albumId":"22222222-2222-4222-8222-000000000002","slug":"trip-2026","expiresAt":null}]
```

Le `slug` est sur le fil, et **aucun `PUT /api/shared-links/{id}`** n'a été envoyé (le stub répond 404 à ce verbe, ce qui aurait fait échouer le scénario). L'URL affichée sur l'écran « lien prêt » porte l'`externalDomain` du stub (`https://photos.stub.test`) alors que l'app dialogue avec `127.0.0.1` : c'est la preuve de bout en bout du bug corrigé, invisible pour un grep.

**Écarts nets sur la suite** : `SharedLinkURLTests` +5, `LongDateFormatterTests` +4, `ImmichAPIClientTests` +2 (1 remplacé, 3 ajoutés), `SharedLinksViewModelTests` +2.

## Défauts trouvés en exécutant (et corrigés)

1. **`.accessibilityIdentifier` posé sur un conteneur ÉCRASE les identifiants de tous ses descendants.** Le panneau « lien prêt » portait `sharedLinkReadyScreen` sur son `VStack` : l'arbre d'accessibilité rendait `sharedLinkReadyScreen` pour l'icône, le texte d'URL **et** les deux boutons — les identifiants internes étaient inutilisables, alors que l'écran était parfait. Variante de la famille `.accessibilityLabel` sur un conteneur [3acc19d3] ; l'identifiant du conteneur a été retiré. Diagnostiqué en imprimant `app.debugDescription` au point d'échec.
2. **`LongDateFormatter.parse(isoTimestamp:)` ne parsait PAS l'horodatage du serveur.** `ISO8601DateFormatter()` avec ses options par défaut rejette les millisecondes (`"2024-07-29T14:30:00.000Z"` → `nil`), alors que c'est exactement la forme que le doc-comment de la fonction annonçait. Conséquence sur cette carte : la feuille d'édition initialisait `expiresAt` à `nil` pour un lien **qui avait** une expiration, le picker affichait « Never », et enregistrer n'importe quel autre champ **effaçait silencieusement l'expiration**. Corrigé par deux formateurs hoistés (fractionnaire puis simple), plus `Tests/LongDateFormatterTests` (4 tests) pour garder les deux formes.
3. **Les checks AC `"Test Case .*Class test_name. passed"` ne matchent jamais.** xcodebuild imprime `Test Case '-[Suite.Class test_name]' passed (…)` : après le nom du test viennent **deux** caractères (`]` puis `'`), donc un `.` unique échoue. Les 5 checks d'exécution de cette carte utilisaient cette forme : ils étaient écrits en `. passed` et renvoyaient FAIL sur des tests verts. Corrigés en `[^ ]* passed`. Même famille que le `grep -q` dans un pipe [4e5514db] — un check non rejoué contre une sortie réelle ne vaut rien.
4. **Un test pinnait le mauvais verbe** : `test_P0_updateSharedLink_hitsPutEndpoint` assertait `PUT` là où le serveur n'expose que `PATCH` (404 au runtime). Remplacé par le test PATCH. Même classe que l'AC qui grepait `TimelineView.swift` pour un flag vivant dans le view model.
5. **Une assertion dépendait de la langue du simulateur** (`"July 29, 2024"` rendu en `"29 juillet 2024"`). Réécrite sans pin de libellé.

## Ce qui n'est PAS dans cette carte

Le **viewer public** (ouvrir un lien reçu, mot de passe, upload invité) : carte `.opencode/scratch/shared-link-viewer.acceptance.md`, issue **#22**, pré-état mesuré (5 FAIL / 1 PASS sur la garde). Les trois routes inventées par la version d'origine n'ont jamais été implémentées et la garde AC-3908 interdit leur réapparition.
