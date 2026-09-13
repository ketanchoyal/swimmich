# Task: shared-link-viewer

Status: plan — carte créée le 2026-09-13 en **retrait du périmètre de #17** (shared-links-enriched). Aucun code écrit.

## Pourquoi cette carte existe

`shared-links-enriched.acceptance.md` (version du 8 septembre) et l'issue #17 demandaient trois routes pour un « viewer public » : `GET /shared-links/public/:slug`, `POST /shared-links/:slug/assets`, `POST /shared-links/:slug/check-password`. **Aucune n'existe**, et le client Flutter n'a pas cette feature non plus (seulement une page liste + une page création/édition). C'est donc une feature **neuve**, pas un écart de parité : elle a sa carte, au lieu de gonfler #17.

## Contrat réel à utiliser (vérifié 2026-09-13)

| Besoin | Route réelle |
|---|---|
| Ouvrir un lien reçu | `GET /api/shared-links/me` avec `?key=<base64url>` **ou** `?slug=<slug>` (auth `sharedLink: true`) |
| Vérifier un mot de passe | `POST /api/shared-links/login` avec `?key=`/`?slug=` et body `{password}` → renvoie le DTO **et pose un cookie** |
| Lister/consulter un asset partagé | routes assets ordinaires avec `?key=` en query |
| Uploader depuis un lien | `POST /api/assets?key=…` (multipart), gardé par `requireUploadAccess` : **401 si `sharedLink.allowUpload` est faux** |

Preuves : OpenAPI `main` (`open-api/immich-openapi-specs.json`, sha256 `bace1792…`) ; `server/src/controllers/shared-link.controller.ts` (`@Get('me')`, `@Post('login')`) ; `server/src/services/shared-link.service.ts` (`login`, `getMine`) ; `server/src/services/auth.service.ts:494` (`validateSharedLinkKey` — `Buffer.from(key, key.length === 100 ? 'hex' : 'base64url')`) ; `server/src/utils/access.ts` (`requireUploadAccess`).

## Prérequis techniques (la vraie raison du retrait)

1. **Le transport ne sait pas porter une clé de partage.** `ImmichAPIClient.sendAuthedRaw` exige un bearer et jette `APIError.unauthorized` sinon ; `ImmichHeader` (`Sources/Core/Constants.swift`) n'a aucune notion de clé de partage. Il faut un chemin « sans bearer, avec `?key=` » (nouveau `sendSharedLinkRaw`), sans mélanger ce cas avec `sendNoAuth` (qui est le pré-login : ping/version/config/login).
2. **Le cookie de `POST /shared-links/login` doit survivre** : un `URLSessionConfiguration.ephemeral` (tests) ou une session par défaut (app) — il faut décider où vivent les cookies de partage, sachant que l'app configure aussi une session avec `TrustEvaluatingURLSessionDelegate` pour les certificats auto-signés.
3. **UI à spécifier** : saisie de mot de passe, grille d'assets du lien, upload invité (avec le 401 `allowUpload` à expliquer à l'utilisateur), sortie de lien mort (`expiresAt` dépassé, lien révoqué → 401 « Invalid share key »).

## Critères (à rejouer en pré-état avant exécution)

```
### AC-4000 [type: new]
Assertion: le client expose une lecture de lien partagé par clé/slug, sans bearer.
Check post-impl: sh -c 'grep -qE "func getSharedLinkMine" Sources/Core/Protocols/ImmichClient.swift && grep -qE "func getSharedLinkMine" Sources/Services/ImmichAPIClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-4001 [type: new]
Assertion: transport asservi — GET /api/shared-links/me?key=… sans en-tête Authorization.
Check post-impl: sh -c 'grep -qE "Test Case .*ImmichAPIClientTests test_SLV_getMine_sendsKeyWithoutBearer[^ ]* passed" /tmp/immich_sharedlinkviewer_unit.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-4002 [type: new]
Assertion: POST /api/shared-links/login porte {password} et conserve le cookie de session.
Check post-impl: sh -c 'grep -qE "Test Case .*ImmichAPIClientTests test_SLV_login_postsPasswordAndKeepsCookie[^ ]* passed" /tmp/immich_sharedlinkviewer_unit.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-4003 [type: new]
Assertion: scénario de bout en bout sur stub committé — lien à slug protégé par mot de passe : refus puis succès.
Check post-impl: sh -c 'test -f UITests/stubs/immich_stub_shared_link_viewer.py && grep -qE "Test Case .*test_SLV_viewer.* passed" /tmp/immich_sharedlinkviewer_uitest.log && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-4004 [type: guard]
Assertion: aucune route inventée (`public/:slug`, `:slug/assets`, `check-password`) n'apparaît dans le code.
Check post-impl: sh -c '! grep -rqE "shared-links/public|checkSharedLinkPassword|getSharedLinkPublic|uploadToSharedLink" Sources/ && echo PASS || echo FAIL'
Pre-state attendu: PASS
Post-state attendu: PASS
```

```
### AC-4005 [type: regression]
Assertion: suite complète ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_sharedlinkviewer_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_sharedlinkviewer_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 736 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
