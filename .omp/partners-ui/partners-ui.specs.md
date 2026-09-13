# Task: partners-ui — Spec

**Objectif** : parité Flutter de la gestion des partenaires dans ImmichSwiftUI — écran dédié à deux directions, invitation par sélection dans l'annuaire de l'instance, toggle « Show in timeline » sur les partenaires entrants, retrait des partenaires sortants — plus le branchement des 2 endpoints manquants (`GET /api/partners?direction=`, `POST /api/partners`).

**Références Flutter** : `mobile/lib/pages/library/partner/partner.page.dart`, `mobile/lib/presentation/pages/partner_detail.page.dart`, `mobile/lib/presentation/actions/partner.action.dart`, `mobile/lib/domain/services/partner.service.dart`.

> **Révision du 2026-09-13.** Cette spec a été réécrite après vérification du contrat serveur (OpenAPI publié `main` + `v1.106.0/v1.135.0/v1.140.0/v1.142.0`, `server/src/services/partner.service.ts`, `server/src/dtos/partner.dto.ts`, clients web et Flutter). Trois points de la version d'origine étaient faux et sont corrigés plus bas : `direction` est **requis** (le `getPartners()` sans query du dépôt produit un 400), la création prend un **userId** et non un email, et les deux mutations ne s'appliquent **pas** aux mêmes lignes.

## Hypothèses (vérifiées le 2026-09-13)

- `PartnerResponseDto { id, name, email, profileImagePath, avatarColor, profileChangedAt, inTimeline }` — `Sources/Core/Types/DTOs+People.swift:57` ; `PartnerUpdateDto { inTimeline }`, requis — `:68`.
- Wire aujourd'hui : `getPartners()` **sans query** (`ImmichClient.swift:113`, `ImmichAPIClient.swift:324`), `updatePartner(id:isInTimeline:)` (`:328`), `removePartner(id:)` (`:332`).
- `getUsers()` → `GET /api/users` (`ImmichAPIClient.swift:463`). **Non-admin sur serveur privé ne reçoit que `[lui-même]`** (sauf `server.publicUsers`) — limitation déjà documentée et filtrée (`AlbumShareViewModel.swift:102-104`).
- `auth.userId` existe (`AuthViewModel.swift:51`) et ne sert qu'à exclure soi-même de l'annuaire : le serveur prend « moi » dans le token.
- `ImmichAPI.partners = SubPath(root: "/partners")` (`Constants.swift:23`) ; query params via le paramètre `query:` du client (`getActivities`, `ImmichAPIClient.swift:338-341`).
- UI existante à déplacer : `SharedLinksView.swift:112-152` + `:346` (`PartnerRow`) + `:388` (`PartnerAvatarCircle`) ; `SharedLinksViewModel.swift:18-78`. Identifiant déjà posé : `partnerTimelineToggle-<id>`.
- Harnais de transport : `CapturingURLProtocol` (`Tests/ImmichAPIClientTests.swift:4-60`). Harnais de bout en bout : stub Python + XCUITest (`UITests/ImmichRenderScreenshots.swift:215`, `:288`) — le stub stacks vit dans `/tmp`, non commité.

## Contrat serveur (le point qui décide de la conception)

| Route | Corps / paramètres | S'applique à |
|---|---|---|
| `GET /api/partners?direction=shared-by\|shared-with` | `direction` **requis** | les deux listes |
| `POST /api/partners` | `{sharedWithId: <uuid>}` | création |
| `PUT /api/partners/{id}` | `{inTimeline: Bool}` ; serveur : `sharedById = id, sharedWithId = moi` | **lignes `shared-with` seulement** |
| `DELETE /api/partners/{id}` | serveur : `sharedById = moi, sharedWithId = id` | **lignes `shared-by` seulement** |

Sémantique des directions (le DTO renvoyé est **toujours l'autre** utilisateur) :
- `direction=shared-by` → lignes où `sharedById == moi` → renvoie `sharedWith` = **les gens que j'ai ajoutés** (« Sharing »). Le web l'expose via `SharedWith` sur sa page sharing, le Flutter via `.sharedBy` sur sa page « partners ».
- `direction=shared-with` → lignes où `sharedWithId == moi` → renvoie `sharedBy` = **les gens qui partagent leur photothèque avec moi** (« Shared with me ») ; c'est la direction sur laquelle porte le toggle timeline du Flutter (`partner_detail.page.dart`).

## Approches

**A (retenue)** — écran dédié `PartnersView` poussé depuis le hub « Me », deux sections par direction, actions asymétriques.
**B (rejetée)** — tout garder dans `SharedLinksView` : la ligne fusionnée ne peut pas porter la matrice d'actions (le toggle du timeline n'est valide que sur une direction, le retrait sur l'autre) ; l'onglet « Shared » traiterait deux objets différents.
**C (rejetée)** — 6ᵉ onglet : trop lourd pour une fonction secondaire.

Rattachement : `ProfileView` section Management, comme Trash, Backup, Duplicates, People, Tags et Stacks (`ProfileView.swift:39-72`). Le web range le partage partenaire dans `User Settings > Partner Sharing` (`docs/docs/features/partner-sharing.md`). Le bloc partenaires est **retiré** de `SharedLinksView` (cutover propre, une seule surface).

## Étapes

1. EDIT `Sources/Core/Types/DTOs+People.swift` — `PartnerCreateDto { sharedWithId }`, `PartnerDirection` (`shared-by` / `shared-with`).
2. EDIT `Sources/Core/Protocols/ImmichClient.swift:113` — `getPartners(direction:)` non optionnel + `createPartner(sharedWithId:)` ; suppression de la surcharge sans direction.
3. EDIT `Sources/Services/ImmichAPIClient.swift:324` — query `direction` + POST du corps `{sharedWithId}`.
4. NEW `Sources/Features/Partners/PartnersViewModel.swift` — `sharedWithMe`, `sharing`, `load()`, `invite(userId:)`, `setInTimeline(partnerId:enabled:)`, `remove(partnerId:)`, `loadCandidates()`, `inviteCandidates`/`filteredCandidates`, `searchQuery`, `selectedCandidateId`, `isBusy`, `errorMessage`.
5. NEW `Sources/Features/Partners/PartnersView.swift` — deux sections + toolbar `+` + `ConfirmationDialog` de retrait + états vides.
6. NEW `Sources/Features/Partners/InvitePartnerSheet.swift` — candidats (annuaire − soi − déjà partenaires), recherche, CTA désactivé sans sélection, état vide si annuaire non exposé.
7. MOVE `PartnerRow` + `PartnerAvatarCircle` → `Sources/Features/Partners/PartnerRow.swift`.
8. EDIT `SharedLinksView.swift` / `SharedLinksViewModel.swift` — retrait complet du bloc partenaires (UI, état, appels, alertes, confirmation).
9. EDIT `ProfileView.swift` + `DependencyContainer.swift` (`makePartnersViewModel()`) + `RootView.swift:175` — lien « Partners » et instance.
10. EDIT `Tests/Mocks/MockImmichClient.swift` — `getPartners(direction:)` avec **deux fixtures** et `createPartner(sharedWithId:)` avec capture de l'id.
11. Tests : `PartnersViewModelTests` (6 comportements, dont le refus des mutations hors portée), 4 tests de transport, 1 scénario XCUITest sur stub committé.

## Acceptance Contract

Critères détaillés : `.opencode/scratch/partners-ui.acceptance.md` — **AC-3100 … AC-3113**.

Répartition : AC-3100–3102 (DTOs + client), AC-3103 (contrat réseau exercé sur transport asservi), AC-3104–3106 (ViewModel + vues + feuille d'invitation), AC-3107 (routage du hub), AC-3108–3109 (cutover sans doublon), AC-3110 (tests de comportement), AC-3111–3112 (exécution de bout en bout + stub qui refuse un `direction` manquant), AC-3113 (régression ≥ 724).
