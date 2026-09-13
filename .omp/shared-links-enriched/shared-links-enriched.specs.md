# Task: shared-links-enriched — Spécification

**Statut** : spécification **réécrite le 2026-09-13** sur le contrat réel du serveur et sur le dépôt réel. La version d'origine (8 septembre) décrivait trois routes qui n'existent pas et cinq « enrichissements » dont deux étaient déjà livrés ; elle est conservée en fin de fichier, sous « Version d'origine — ce qu'elle affirmait à tort ».

**Objectif** : fermer les cinq écarts réels avec le client Flutter sur les shared links — builder d'URL publique (bug), champ `slug` à la création et à l'édition, presets d'expiration, feuille de partage, écran « lien prêt » après création.

**Hors périmètre** (carte + issue **#22**, `.opencode/scratch/shared-link-viewer.acceptance.md`) : le viewer public — ouvrir un lien reçu, saisie de mot de passe, upload par un visiteur. Feature neuve, **sans parité Flutter** (le client mobile n'a qu'une page liste + une page création/édition), et qui exige une plomberie d'auth absente : `sendAuthedRaw` exige un bearer et jette `APIError.unauthorized` sinon, et `ImmichHeader` n'a aucune notion de clé de partage.

## Contrat serveur vérifié (2026-09-13)

Vérifié sur l'OpenAPI publié (`main`, `open-api/immich-openapi-specs.json`, sha256 `bace1792…`) et sur les sources serveur (`shared-link.controller.ts`, `shared-link.service.ts`, `shared-link.repository.ts`).

| Route | Contrat |
|---|---|
| `GET /api/shared-links` | params `albumId?`, `id?` — permission `SharedLinkRead` |
| `POST /api/shared-links` | body `SharedLinkCreateDto` — `type` requis, `slug` optionnel (« Custom URL slug ») |
| `PATCH /api/shared-links/{id}` | body `SharedLinkEditDto` — **`patch`, pas `put`** (le `PUT` du client rendait 404) |
| `GET /api/shared-links/{id}` | permission `SharedLinkRead` |
| `DELETE /api/shared-links/{id}` | 204 |
| `GET /api/shared-links/me` | `?key=<base64url>` ou `?slug=<slug>` — scope `sharedLink` : c'est LA route de visite d'un lien public |
| `POST /api/shared-links/login` | `?key=`/`?slug=` + body `{password}` → DTO + cookie |
| `PUT /api/shared-links/{id}/assets` | body `AssetIdsDto` — propriétaire (`SharedLinkUpdate`), `type == INDIVIDUAL` sinon 400 |
| `DELETE /api/shared-links/{id}/assets` | idem, retrait |

Routes **inexistantes**, inventées par la carte d'origine : `GET /shared-links/public/:slug`, `POST /shared-links/:slug/assets`, `POST /shared-links/:slug/check-password`. L'upload par un visiteur est la route ordinaire `POST /api/assets?key=…`, gardée par `requireUploadAccess` (401 si `sharedLink.allowUpload` est faux) — cf. carte #22.

**Trois subtilités qui décident du code :**

1. `SharedLinkService.update` écrit `slug: dto.slug || null` : un slug **omis est effacé** (contrairement à `password` et `expiresAt`, que le repository laisse intacts quand le champ est absent). Le formulaire d'édition renvoie donc **toujours** le slug courant.
2. `SharedLinkService.create` pose `allowUpload: dto.allowUpload ?? true` et `allowDownload: dto.showMetadata === false ? false : (dto.allowDownload ?? true)` — les booleens sont optionnels côté client.
3. `addAssets` filtre les doublons (`DUPLICATE`) et les assets sans permission `AssetShare` (`NO_PERMISSION`) puis réécrit la liste complète des assets du lien.

## Format d'URL publique (bug n° 1)

Référence Flutter — `mobile/lib/utils/url_helper.dart` :

```dart
String? buildSharedLinkUrl({required String? baseUrl, required String key, String? slug}) {
  final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  final path = (slug != null && slug.isNotEmpty) ? 's/$slug' : 'share/$key';
  return '$normalizedBaseUrl$path';
}
```

Appelants Flutter (`shared_link_item.dart`, `shared_link_edit.page.dart`) : `base = externalDomain.isNotEmpty ? externalDomain : getServerUrl()`. Côté web, les routes correspondantes sont `(user)/s/[slug]` et `/share/[key]`.

L'app hardcode `baseURL.appendingPathComponent("/share/\(link.key)")` à deux endroits — `SharedLinkRow.url` (`SharedLinksView.swift`) et `PhotoShareViewModel.createPublicLink` — donc elle ignore le slug **et** `externalDomain` : lien mort pour un lien à slug, et pour tout serveur derrière un reverse-proxy. `ServerConfigDto.externalDomain` existe déjà (`Sources/Core/Types/DTOs.swift`) et est affiché à l'onboarding.

**Correctif** : un seul builder `Sources/Core/Utilities/SharedLinkURL.swift` (struct portant `serverURL` + `externalDomain`), les deux appelants migrent, l'ancien code disparaît. `AuthViewModel.restoreSession()` charge en plus `serverConfig()`, sinon `externalDomain` reste inconnu après un relaunch (il n'était chargé qu'en passant par l'onboarding).

## Périmètre livré

| # | Écart vs Flutter | Livrable |
|---|---|---|
| 1 | URL publique | `SharedLinkURL` (un builder), 2 appelants migrés |
| 2 | champ `slug` | `slug` sur `SharedLinkCreateDto` + `SharedLinkEditDto` ; champ `/s/` à la création (onglet Shared + feuille album) et à l'édition |
| 3 | expiration | `SharedLinkExpiryPicker` : 9 presets (Never, 30 min, 1 h, 6 h, 1 j, 7 j, 30 j, 90 j, 1 an) + date/heure, partagé création/édition |
| 4 | feuille de partage | `ShareLink` à côté du bouton copier dans `SharedLinkRow` (onglet Shared **et** feuille d'album) |
| 5 | retour post-création | écran « lien prêt » après création : lien copié, URL affichée, `ShareLink` |

Plus, sur la même surface : `updateSharedLink` passe en `PATCH` (le `PUT` rendait 404), et `addAssetsToSharedLink(id:assetIds:)` entre au protocole comme miroir de surface (`PUT /shared-links/{id}/assets`, convention `api-surface-expansion` — le protocole porte déjà des méthodes sans consommateur UI, `getExploreData` par exemple).

## Fichiers

| Fichier | Nature |
|---|---|
| `Sources/Core/Utilities/SharedLinkURL.swift` | NEW — builder unique |
| `Sources/Core/Types/DTOs+SharedLink.swift` | `slug` sur `SharedLinkCreateDto` |
| `Sources/Core/Types/DTOs+Server.swift` | `slug` sur `SharedLinkEditDto`, route `PATCH` |
| `Sources/Core/Protocols/ImmichClient.swift` | `addAssetsToSharedLink`, doc `PATCH` |
| `Sources/Services/ImmichAPIClient.swift` | `PATCH`, `addAssetsToSharedLink` |
| `Sources/Features/Auth/AuthViewModel.swift` | `serverConfig()` au restore |
| `Sources/Features/SharedLinks/SharedLinkExpiryPicker.swift` | NEW — presets + date/heure |
| `Sources/Features/SharedLinks/SharedLinksViewModel.swift` | création (slug + expiration, renvoie le lien), `addAssets` |
| `Sources/Features/SharedLinks/SharedLinksView.swift` | slug + presets à la création, écran « lien prêt », URL + `ShareLink` dans la ligne |
| `Sources/Features/SharedLinks/EditSharedLinkSheet.swift` | slug + presets |
| `Sources/Features/SharedLinks/SharedLinkSheet.swift` | slug + presets (création album), `SharedLinkURL` |
| `Sources/Features/PhotoViewer/PhotoShareViewModel.swift` | URL via le builder |
| `Tests/Mocks/MockImmichClient.swift` | `addAssetsToSharedLink` |
| `UITests/stubs/immich_stub_shared_links.py` | NEW — stub committé |
| `UITests/ImmichRenderScreenshots.swift` | `test_07_sharedLinks` |

## Tests

- `Tests/SharedLinkURLTests.swift` : slug → `/s/<slug>` ; sans slug → `/share/<key>` ; `externalDomain` prioritaire sur l'URL du serveur ; URL du serveur quand `externalDomain` est vide.
- `Tests/ImmichAPIClientTests.swift` (transport asservi `CapturingURLProtocol`) : `POST /api/shared-links` porte le slug ; `PATCH /api/shared-links/{id}` porte le slug ; `PUT /api/shared-links/{id}/assets` porte `AssetIdsDto`. Le test `test_P0_updateSharedLink_hitsPutEndpoint` est **remplacé** : il pinnait un verbe faux (le serveur n'expose que `PATCH`).
- `Tests/SharedLinksViewModelTests.swift` : création avec slug + expiration, lien renvoyé ; ajout d'assets.
- `UITests/ImmichRenderScreenshots.swift/test_07_sharedLinks` contre le stub committé : créer un lien à slug, lire l'URL affichée (elle doit porter l'`externalDomain` du stub et `/s/<slug>`), la copier et voir le retour visuel. XCUITest ne peut pas lire un presse-papier inter-processus sans l'invite de consentement iOS : le feedback in-app est la preuve du tap (même classe de garde que le `.buttonStyle(.plain)` avalant les taps).

**Pièges du dépôt à respecter** : `.buttonStyle(.plain)` sur un `Button` dans une `List` avale le tap ; `.accessibilityLabel` sur un conteneur fusionne ses enfants ; le hub « Me » et toute `Form`/`List` sont paresseux (scroller avant d'assertir) ; les CTA sont localisés → viser les `accessibilityIdentifier`.

## Version d'origine — ce qu'elle affirmait à tort

Conservée pour la traçabilité (carte `.opencode/scratch/shared-links-enriched.acceptance.md` et issue #17 : même dérive).

- **`GET public/:slug`, `POST :slug/assets`, `POST :slug/check-password`** : inexistantes. Voir le tableau du contrat.
- **« copy-link manquant »** : déjà livré (`UIPasteboard` dans `SharedLinkRow`, `PhotoShareViewModel`).
- **« expiry picker manquant »** : le `DatePicker` + `hasExpiry` existaient dans `EditSharedLinkSheet` ; seuls les presets manquaient.
- **« le slug est le chemin URL `/share/{slug}` »** : faux — `/s/<slug>` quand un slug existe, `/share/<key>` sinon.
- **`PUT /api/shared-links/{id}`** : le serveur n'expose que `PATCH`.
- **`checkSharedLinkPassword(slug:), uploadToSharedLink(slug:)`** annoncés comme endpoints manquants côté client : ce sont des routes inventées ; l'équivalent réel côté propriétaire est `PUT /api/shared-links/{id}/assets` (id, pas slug ; `INDIVIDUAL` seulement).
