# Task: partners-ui

Status: done — **14/14 AC PASS** (2026-09-13). Suite complète **736 tests, TEST SUCCEEDED** (iPhone 17 ; baseline mesurée à 724 sur `HEAD` dans un worktree dédié) et scénario de bout en bout `test_06_partners` vert contre le stub **committé** `UITests/stubs/immich_stub_partners.py`.

## Résultat (2026-09-13)

| AC | Résultat | Preuve |
|----|----------|--------|
| AC-3100 | PASS | `PartnerCreateDto` + `PartnerDirection` (`DTOs+People.swift:72-90`) |
| AC-3101 | PASS | `getPartners(direction:)` non optionnel + `createPartner(sharedWithId:)` ; surcharge sans direction supprimée |
| AC-3102 | PASS | query `direction` + corps `{sharedWithId}` (`ImmichAPIClient.swift:322-336`) |
| AC-3103 | PASS | 4 tests de transport : `test_P0_getPartners_sendsRequiredDirection`, `test_partners_createPartnerPostsSharedWithId`, `test_P0_updatePartner_putsPartnerPath`, `test_P0_removePartner_deletesPartnerPath` |
| AC-3104 | PASS | `PartnersViewModel` : 2 collections + 4 opérations + `loadCandidates` |
| AC-3105 | PASS | `PartnersView` (2 sections, câblage) + `PartnerRow` (action par mode, identifiants) |
| AC-3106 | PASS | `InvitePartnerSheet` : annuaire − soi − déjà partenaires, CTA armé à la sélection, état vide |
| AC-3107 | PASS | ligne « Partners » dans la section Management de `ProfileView` |
| AC-3108 | PASS | `PartnerRow`/`PartnerAvatarCircle` déplacés ; plus aucun composant partenaire dans `SharedLinksView` |
| AC-3109 | PASS | `SharedLinksViewModel` purgé (état + 3 méthodes) ; mock à deux fixtures + `lastPartnersDirection` |
| AC-3110 | PASS | `PartnersViewModelTests` : 14 tests |
| AC-3111 | PASS | `UITests/stubs/immich_stub_partners.py` + `test_06_partners` |
| AC-3112 | PASS | le stub répond **400** à `/api/partners` sans `direction` ; le scénario passe quand même |
| AC-3113 | PASS | 736 tests ≥ 724, TEST SUCCEEDED |

**Tests ajoutés (12 nets)** : `PartnersViewModelTests` 14 (directions, invitation, gardes de portée, annuaire, filtre, sélection) ; `ImmichAPIClientTests` : 3 de plus (l'ancien `test_P0_getPartners_hitsPartnersEndpoint` remplacé par 4) ; `SharedLinksViewModelTests` −5 (les tests partenaires y testaient une liste unique qui n'existe plus).

**Preuve d'exécution du contrat réseau** — journal du stub après `test_06_partners` (`GET /__requests`), c'est-à-dire ce que l'app a réellement envoyé :

```json
[{"method":"GET","path":"/api/partners","direction":"shared-with"},
 {"method":"GET","path":"/api/partners","direction":"shared-by"},
 {"method":"POST","path":"/api/partners","sharedWithId":"cccccccc-3333-4333-8333-000000000003"},
 {"method":"DELETE","path":"/api/partners/bbbbbbbb-2222-4222-8222-000000000002"}]
```

Aucune requête sans `direction` (celle qui rendait 400), **aucun `PUT`** (l'écran n'en envoie pas faute de partenaire entrant modifié dans ce parcours) et le `DELETE` porte sur le partenaire **sortant** — jamais sur l'entrant, dont le retrait aurait révoqué un accès que l'utilisateur n'a pas accordé.

**Pièges rencontrés et corrigés**
1. **`.buttonStyle(.plain)` sur un `Button` dans une `List` avale le tap (iOS 26).** La feuille d'invitation s'affichait parfaitement, la ligne semblait cliquable, et `selectCandidate` n'était jamais appelé : le CTA « Invite » restait grisé. Le contrôle visuel (capture de la feuille) montrait bien la liste **sans** coche après le tap. Correctif : style de bouton par défaut de la `List` + `contentShape(Rectangle())` + couleurs de texte explicites. **Même classe de défaut que le picker de piles le 2026-09-13** (un `Button` autour d'`AssetThumbnailCell`) : dans ce dépôt, un tap de ligne qui ne fait rien est presque toujours un `Button`/`buttonStyle` qui intercepte le geste — et seul un test d'exécution le voit.
2. **`statusMessage` de la carte vs code réel** : l'extraction de `PartnerRow` hors de `SharedLinksView` (étape 7) a déplacé les identifiants d'accessibilité dans un nouveau fichier — les checks d'AC-3105 et AC-3110 ont été repointés sur les fichiers livrés (sinon ils échouaient sur du code pourtant correct).
3. **`grep` d'un nom de test inexistant** : AC-3110 exigeait `test_error_surfacesMessage`, jamais écrit ; les noms du check sont désormais ceux du fichier.
4. **Le stub `GET /api/users` n'est pas l'annuaire** : un non-admin sur serveur privé ne reçoit que lui-même — l'état vide de la feuille d'invitation est un comportement serveur, pas une régression (testé côté VM par `test_loadCandidates_flagsRestrictedDirectory`).
5. **Le partage est unidirectionnel** : le partenaire **entrant** reste un candidat d'invitation légitime (c'est ainsi que sa photothèque apparaît dans mon planning). Seuls les partenaires **sortants** sont exclus de l'annuaire — l'inverse produisait un faux échec du scénario.

## Révision du 2026-09-13 — ce que la carte d'origine affirmait à tort

| Affirmation d'origine | Réalité vérifiée | Preuve |
|---|---|---|
| `getPartners()` sans query est « wire » et suffit | `direction` est **requis** : sans lui le serveur répond **400**. La section partenaires de `SharedLinksView` est donc cassée au runtime aujourd'hui, alors que son AC grep est vert | OpenAPI (4 versions : `direction` `required: true`) ; `server/src/app.module.ts` (`APP_PIPE: ZodValidationPipe`) ; `server/src/dtos/partner.dto.ts` |
| `getPartners(direction: PartnerDirection?)` (optionnel) | doit être **non optionnel** : il n'existe aucun mode « toutes directions » | idem |
| `createPartner(email:)` → `POST /api/partners` | le corps est `{sharedWithId: <uuid>}` — **un userId, jamais un email**. L'email doit être résolu via `GET /api/users` | `server/src/dtos/partner.dto.ts` ; Flutter `mobile/lib/domain/services/partner.service.dart` (`getCandidates` + `create(sharedWithId:)`) |
| Une seule liste de partenaires | le DTO renvoyé est **toujours l'autre** utilisateur, et le sens est inverse de l'intuition : `shared-by` = **ceux que j'ai ajoutés** (« Sharing »), `shared-with` = **ceux qui partagent avec moi** (« Shared with me ») | `PartnerService.search` + `mapPartner` ; web `web/src/routes/(user)/sharing/+page.ts` (`SharedWith`) ; Flutter `partner.page.dart` (`.sharedBy`) |
| Chaque ligne porte toggle timeline **et** remove | impossible : `PUT /api/partners/{id}` n'accepte que les lignes `shared-with`, `DELETE` que les lignes `shared-by` — les deux mutations ne portent pas le même id | `PartnerService.update` (`sharedById: id, sharedWithId: moi`) vs `remove` (`sharedById: moi, sharedWithId: id`) |
| AC-3105 : lien « Partners » dans `ProfileView`, `systemImage: "person.2"` | `person.2` est **déjà pris** par « People » (`ProfileView.swift:60`) ; le plan et l'issue disaient « Shared tab » → contradiction interne. Décision ci-dessous | `ProfileView.swift:57-61` |
| AC-3109 : suite `-ge 200` | baseline réelle **724** | `.omp/backlog/ImmichSwiftUI-backlog.md:9` |
| AC-3103/3104/3108 : `grep -q "createPartner"` **dans le fichier de vue** | un mot dans un commentaire satisfait le check — même défaut que l'`addAssetToStack` de la carte stacks | `.opencode/scratch/stacks-ui.acceptance.md` (Révision) |
| « RootView — Add PartnerShellView in Shared tab » | décision ci-dessous | `RootView.swift:122`, `SharedLinksView.swift:112-152` |

### Décision de rattachement (seule déviation assumée par rapport à l'issue #14)

`PartnersView` est un **écran dédié poussé depuis le hub « Me »** (`ProfileView`, section Management), et le bloc partenaires est **retiré** de `SharedLinksView`.

1. Toutes les listes de gestion du dépôt sont déjà poussées depuis ce hub : Trash, Backup, Duplicates, People, Tags, Stacks (`ProfileView.swift:39-72`).
2. La ligne fusionnée de `SharedLinksView` ne peut pas exprimer la matrice d'actions par direction (voir le tableau ci-dessus) : elle propose le toggle timeline **et** Remove sur chaque ligne, or chacune des deux requêtes n'est valide que sur une direction.
3. Le partage partenaire est un réglage de compte : le web le range dans `User Settings > Partner Sharing` (`docs/docs/features/partner-sharing.md`).
4. Un seul point d'entrée ⇒ une seule surface à maintenir.

Variante si l'on veut coller à l'issue : garder l'écran dans l'onglet Shared (`RootView.swift:122`, icône `person.2.fill`). Coût : soit deux points d'entrée, soit un onglet « Shared » qui mélange deux types de listes aux actions incompatibles.

**Noms** : `PartnerShellView`/`PartnerShellViewModel` (issue) deviennent `PartnersView`/`PartnersViewModel` — convention du dépôt (`StacksViewModel`/`StackView`, `TagsView`, `DuplicatesView`). **Pas de `UserSearchView` imbriquée** : la feuille d'invitation *est* le sélecteur (une recherche + la liste des candidats), un `NavigationStack` imbriqué n'ajoute rien.

## Plan

**Objectif** : parité Flutter de la gestion des partenaires — écran dédié à deux directions (« Shared with me » / « Sharing »), invitation par sélection dans l'annuaire de l'instance, toggle « Show in timeline » sur les partenaires **entrants**, retrait des partenaires **sortants** — plus le branchement des 2 endpoints manquants (`direction` requis, `POST /api/partners`).

**Hypothèses** (vérifiées le 2026-09-13, dépôt + `immich-app/immich@main`) :
- `PartnerResponseDto { id, name, email, profileImagePath, avatarColor, profileChangedAt, inTimeline }` — `Sources/Core/Types/DTOs+People.swift:57` ; `PartnerUpdateDto { inTimeline }` (requis) — `:68`.
- Wire aujourd'hui : `getPartners()` **sans query** (`ImmichClient.swift:113`, `ImmichAPIClient.swift:324`), `updatePartner(id:isInTimeline:)` (`:328`), `removePartner(id:)` (`:332`).
- `getUsers()` → `GET /api/users` (`ImmichAPIClient.swift:463`). **Non-admin sur serveur privé ne reçoit que `[lui-même]`** (sauf `server.publicUsers`) : précédent documenté et déjà filtré `$0.id != currentUserId` dans `AlbumShareViewModel.swift:102-104`.
- L'id du user courant est disponible côté client : `auth.userId` (`AuthViewModel.swift:51`, déjà utilisé `AlbumDetailView.swift:214`). Aucun appel partenaire n'a besoin de le transmettre — le serveur prend « moi » dans le token ; il ne sert qu'à exclure soi-même de l'annuaire.
- `ImmichAPI.partners = SubPath(root: "/partners")` (`Constants.swift:23`) ; les query params passent par le paramètre `query:` (`getActivities`, `ImmichAPIClient.swift:338-341`).
- UI partenaires actuelle, à **déplacer, pas à dupliquer** : `SharedLinksView.swift:112-152` (section + confirmation), `:346` `struct PartnerRow`, `:388` `struct PartnerAvatarCircle`, et `SharedLinksViewModel.swift:18-78` (`loadPartners`, `togglePartnerTimeline`, `removePartner`).
- Identifiants d'accessibilité déjà en place sur la ligne : `partnerTimelineToggle-<id>` (`SharedLinksView.swift:368`) — à conserver ; le bouton poubelle n'en a pas (`:377`).
- Harnais de transport existant : `CapturingURLProtocol` (`Tests/ImmichAPIClientTests.swift:4-60`) — capture méthode + URL + corps.
- Harnais de bout en bout existant : stub Python + XCUITest (`UITests/ImmichRenderScreenshots.swift:215`, `:288`). ⚠ le stub vit dans `/tmp/immich_stub_stacks.py`, **non commité** : il sera perdu au prochain nettoyage. Cette carte en commit un.

**Approche retenue** : A — écran dédié dans le hub « Me », deux sections par direction, actions asymétriques conformes au serveur, branchement des 2 endpoints.
**B (rejetée)** : tout garder dans `SharedLinksView` → ligne fusionnée, matrice d'actions inexprimable, et un onglet « Shared » qui traite deux objets différents.
**C (rejetée)** : 6ᵉ onglet → trop pour une fonction secondaire.

**Étapes** :
1. EDIT `Sources/Core/Types/DTOs+People.swift` — NEW `PartnerCreateDto { sharedWithId: String }` + `enum PartnerDirection: String { case sharedBy = "shared-by"; case sharedWith = "shared-with" }`.
2. EDIT `Sources/Core/Protocols/ImmichClient.swift:113` — `func getPartners(direction: PartnerDirection)` (**non optionnel** ; la surcharge sans paramètre disparaît) + `func createPartner(sharedWithId: String)`.
3. EDIT `Sources/Services/ImmichAPIClient.swift:324` — `getPartners` envoie `query: [URLQueryItem(name: "direction", value: direction.rawValue)]` ; `createPartner` = `sendAuthed(.POST, path: ImmichAPI.partners.path(""), body: AnyEncodable(PartnerCreateDto(sharedWithId:)))`.
4. NEW `Sources/Features/Partners/PartnersViewModel.swift` — `sharedWithMe` (`direction: .sharedWith`), `sharing` (`.sharedBy`), `load()`, `invite(userId:)`, `setInTimeline(partnerId:enabled:)`, `remove(partnerId:)`, `loadCandidates()`, `inviteCandidates`/`filteredCandidates`, `searchQuery`, `selectedCandidateId`/`selectCandidate(_:)`, `isBusy`, `errorMessage`. Les deux mutations **refusent** un id absent de la collection correspondante (garde de contrat serveur).
5. NEW `Sources/Features/Partners/PartnersView.swift` — sections « Shared with me » (toggle timeline) / « Sharing » (Remove + confirmation), toolbar `+` → `InvitePartnerSheet`, états vides `ContentUnavailableView`.
6. NEW `Sources/Features/Partners/InvitePartnerSheet.swift` — `inviteCandidates` = annuaire − soi − partenaires déjà en `.sharedBy`, recherche nom/email, CTA « Invite » désactivé sans sélection, état vide si l'annuaire n'est pas exposé.
7. MOVE `PartnerRow` + `PartnerAvatarCircle` (`SharedLinksView.swift:341-407`) → `Sources/Features/Partners/PartnerRow.swift`.
8. EDIT `Sources/Features/SharedLinks/SharedLinksView.swift` — retirer la section partenaires, `showPartnerRemoveConfirm`, le `confirmationDialog` partenaire, l'alerte d'erreur partenaire, les appels `loadPartners()` du `.task`/`.refreshable`. L'état vide reste « No shared links ».
9. EDIT `Sources/Features/SharedLinks/SharedLinksViewModel.swift` — retirer `partners`, `isPartnersLoading`, `partnersError`, `loadPartners()`, `togglePartnerTimeline(id:enabled:)`, `removePartner(id:)`.
10. EDIT `Sources/Features/Profile/ProfileView.swift` — `@State var partners: PartnersViewModel` + `NavigationLink { PartnersView(vm: partners) } label: { Label("Partners", …) }` dans Management ; EDIT `Sources/DependencyContainer.swift` (`makePartnersViewModel()`) et `Sources/RootView.swift:175` (instance + passage à `ProfileView`). Icône **non contrainte par un AC** (`person.2` est pris par « People »).
11. EDIT `Tests/Mocks/MockImmichClient.swift:628` — `getPartners(direction:)` enregistrant `lastPartnersDirection` avec **deux fixtures séparées** (`partnersSharedByResponse` / `partnersSharedWithResponse`, pas une liste unique) ; `createPartner(sharedWithId:)` enregistrant `lastCreatePartnerSharedWithId`.
12. Cutover des appelants : `Tests/SharedLinksViewModelTests.swift:124-176` (5 tests partenaires → `PartnersViewModelTests`) et `Tests/ImmichAPIClientTests.swift:461` (asserter le query param, pas seulement le chemin).
13. Tests + stub committé + `xcodegen` + suite complète.

## Acceptance Contract

### Approches candidates
**A (retenue)** : écran dédié hub « Me », deux sections par direction, actions asymétriques.
**B** : `SharedLinksView` conservé, ligne fusionnée. **C** : 6ᵉ onglet.

### Approche retenue + rationale
**A**. Le serveur impose deux directions et deux portées de mutation distinctes : un écran à deux sections est la seule forme qui les représente sans mentir à l'utilisateur. Réutilise `PartnerRow`/`PartnerAvatarCircle` (déplacés) et le harnais `CapturingURLProtocol` déjà en place.

### Critères

```
### AC-3100 [type: new]
Assertion: PartnerCreateDto { sharedWithId } et PartnerDirection (valeurs wire "shared-by" / "shared-with") dans DTOs+People.swift.
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+People.swift; grep -qE "struct PartnerCreateDto" "$f" && grep -qE "let sharedWithId" "$f" && grep -qE "enum PartnerDirection" "$f" && grep -qE "case sharedBy = \"shared-by\"" "$f" && grep -qE "case sharedWith = \"shared-with\"" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (seuls PartnerResponseDto l.57 et PartnerUpdateDto l.68 existent)
Post-state attendu: PASS
```

```
### AC-3101 [type: new]
Assertion: ImmichClient expose getPartners(direction:) NON optionnel + createPartner(sharedWithId:), et la surcharge sans direction disparaît — elle ne peut produire qu'un 400.
Check post-impl: sh -c 'f=Sources/Core/Protocols/ImmichClient.swift; grep -qE "func getPartners\(direction: PartnerDirection\)" "$f" && grep -qE "func createPartner\(sharedWithId: String\)" "$f" && ! grep -qE "func getPartners\(\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`func getPartners()` l.113)
Post-state attendu: PASS
```

```
### AC-3102 [type: new]
Assertion: ImmichAPIClient envoie le query param direction (sans lui, 400) et poste le corps {sharedWithId}.
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; grep -qE "name: \"direction\"" "$f" && grep -qE "direction.rawValue" "$f" && grep -qE "func createPartner\(sharedWithId" "$f" && grep -qE "PartnerCreateDto\(sharedWithId" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun query param sur /api/partners)
Post-state attendu: PASS
```

```
### AC-3103 [type: new — vérification d'exécution du contrat réseau]
Assertion: les 4 routes partenaires sont exercées sur un transport asservi (méthode + chemin + query + corps réels) — seul contrôle capable d'attraper le 400 du jour.
Check post-impl: sh -c 'f=Tests/ImmichAPIClientTests.swift; for t in test_P0_getPartners_sendsRequiredDirection test_partners_createPartnerPostsSharedWithId test_P0_updatePartner_putsPartnerPath test_P0_removePartner_deletesPartnerPath; do grep -qE "$t" "$f" || { echo FAIL-$t; exit 1; }; done; grep -qE "direction=shared-by" "$f" && grep -qE "direction=shared-with" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL-test_P0_getPartners_sendsRequiredDirection (le check nomme le premier test manquant). Mesuré : `test_P0_getPartners_hitsPartnersEndpoint` (l.461) asserte le chemin mais **jamais la query** — le 400 est invisible au test
Post-state attendu: PASS
Note: `getPartners` doit être appelé avec `.sharedBy` **et** `.sharedWith`, et l'URL capturée doit contenir `direction=shared-by` / `direction=shared-with`.
```

```
### AC-3104 [type: new]
Assertion: PartnersViewModel expose les deux collections par direction et les quatre opérations.
Check post-impl: sh -c 'f=Sources/Features/Partners/PartnersViewModel.swift; test -f "$f" && grep -qE "var sharedWithMe" "$f" && grep -qE "var sharing" "$f" && grep -qE "func load\(" "$f" && grep -qE "func invite\(userId" "$f" && grep -qE "func setInTimeline\(partnerId" "$f" && grep -qE "func remove\(partnerId" "$f" && grep -qE "func loadCandidates" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3105 [type: new]
Assertion: PartnersView rend une section par direction et branche chaque action sur la bonne collection ; PartnerRow ne rend l'action que pour le mode correspondant (identifiants d'exécution inclus).
Check post-impl: sh -c 'v=Sources/Features/Partners/PartnersView.swift; r=Sources/Features/Partners/PartnerRow.swift; test -f "$v" && test -f "$r" && grep -qE "vm.sharedWithMe" "$v" && grep -qE "vm.sharing" "$v" && grep -qE "setInTimeline" "$v" && grep -qE "remove\(partnerId" "$v" && grep -qE "InvitePartnerSheet" "$v" && grep -qE "partnerTimelineToggle-" "$r" && grep -qE "partnerRemove-" "$r" && grep -qE "case incoming" "$r" && grep -qE "case outgoing" "$r" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichiers absents)
Post-state attendu: PASS
Note: l'AC d'origine testait `grep -q "createPartner"` **dans la vue** — un mot en commentaire suffisait — et cherchait les identifiants de ligne dans `PartnersView.swift`, alors que la ligne vit dans `PartnerRow.swift` (extraction faite en cours d'implémentation). Le check visite maintenant les deux fichiers : les sections et le câblage dans la vue, l'action par mode et les identifiants dans la ligne.
```

```
### AC-3106 [type: new]
Assertion: InvitePartnerSheet propose l'annuaire de l'instance en excluant l'utilisateur courant, désactive le CTA sans sélection, et affiche un état vide quand le serveur n'expose pas l'annuaire (non-admin sans publicUsers).
Check post-impl: sh -c 'f=Sources/Features/Partners/InvitePartnerSheet.swift; test -f "$f" && grep -qE "loadCandidates" "$f" && grep -qE "currentUserId" "$f" && grep -qE "invite\(userId" "$f" && grep -qE "ContentUnavailableView" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3107 [type: new]
Assertion: ProfileView route vers PartnersView dans la section Management (aucune icône imposée : person.2 est déjà prise par « People »).
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "PartnersView" "$f" && grep -qE "PartnersViewModel" "$f" && grep -qE "Label\(\"Partners\"" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (Management = Trash, Backup, Duplicates, People, Tags, Stacks, l.39-72)
Post-state attendu: PASS
```

```
### AC-3108 [type: new — cutover propre]
Assertion: SharedLinksView ne porte plus les partenaires ni leurs composants : une seule surface, dans Features/Partners.
Check post-impl: sh -c 'a=Sources/Features/SharedLinks/SharedLinksView.swift; b=Sources/Features/Partners/PartnerRow.swift; test -f "$b" && ! grep -qE "struct PartnerRow" "$a" && ! grep -qE "PartnerAvatarCircle" "$a" && ! grep -qE "showPartnerRemoveConfirm" "$a" && ! grep -qE "loadPartners" "$a" && grep -qE "struct PartnerRow" "$b" && grep -qE "struct PartnerAvatarCircle" "$b" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (PartnerRow l.346 et PartnerAvatarCircle l.388 dans SharedLinksView.swift ; loadPartners appelé l.63/68)
Post-state attendu: PASS
```

```
### AC-3109 [type: new — cutover propre]
Assertion: SharedLinksViewModel ne porte plus d'état partenaire, et le mock expose la direction + l'id de création.
Check post-impl: sh -c 'v=Sources/Features/SharedLinks/SharedLinksViewModel.swift; m=Tests/Mocks/MockImmichClient.swift; ! grep -qE "var partners|func loadPartners|togglePartnerTimeline|removePartner" "$v" && grep -qE "func getPartners\(direction:" "$m" && grep -qE "lastPartnersDirection" "$m" && grep -qE "partnersSharedByResponse" "$m" && grep -qE "partnersSharedWithResponse" "$m" && grep -qE "func createPartner\(sharedWithId:" "$m" && grep -qE "lastCreatePartnerSharedWithId" "$m" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`SharedLinksViewModel.swift:18-78`, `MockImmichClient.swift:628-649`)
Post-state attendu: PASS
```

```
### AC-3110 [type: new]
Assertion: PartnersViewModelTests couvre les comportements qui portent le contrat : chargement par direction, invitation, **aucun PUT pour un partenaire sortant**, **aucun DELETE pour un partenaire entrant**, retrait effectif après succès, erreur conservée, annuaire filtré et restreint.
Check post-impl: sh -c 'f=Tests/PartnersViewModelTests.swift; test -f "$f" && for t in test_load_splitsByDirection test_invite_postsSharedWithId test_setInTimeline_ignoresOutgoingPartner test_remove_ignoresIncomingPartner test_remove_dropsRowOnSuccess test_setInTimeline_failure_keepsRow test_loadCandidates_excludesSelfAndExistingPartners test_loadCandidates_flagsRestrictedDirectory test_selectCandidate_togglesSelection; do grep -qE "$t" "$f" || { echo FAIL-$t; exit 1; }; done && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; les 5 tests actuels vivent dans `SharedLinksViewModelTests.swift:124-176` et testent une liste unique — à déplacer, pas à garder en double)
Post-state attendu: PASS
Note: noms alignés sur le fichier livré (14 tests) ; le check exige en plus les deux gardes de portée de mutation, les deux états de l'annuaire et la sélection du candidat.
```

```
### AC-3111 [type: new — vérification d'exécution de bout en bout]
Assertion: un scénario XCUITest piloté par un stub **committé** exerce l'écran livré : ouvrir Partners depuis le hub, voir un entrant (toggle) et un sortant (remove), retirer le sortant et voir la ligne disparaître.
Check post-impl: sh -c 'u=UITests/ImmichRenderScreenshots.swift; s=UITests/stubs/immich_stub_partners.py; test -f "$s" && grep -qE "test_06_partners" "$u" && grep -qE "partnerRemove-" "$u" && grep -qE "immich_stub_partners" "$u" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (stub absent du dépôt : celui des stacks vit dans `/tmp/immich_stub_stacks.py`, non commité, donc déjà perdu au 1er nettoyage de /tmp)
Post-state attendu: PASS
```

```
### AC-3112 [type: new — anti-régression du 400]
Assertion: le stub REFUSE (400) toute requête /api/partners sans direction, et le scénario de bout en bout passe : c'est la preuve que l'app envoie bien direction. Un grep sur la source ne peut pas l'établir — même angle mort que la clôture 8/8 d'OAuth2 le 2026-09-10 (une feature fermée alors qu'aucune connexion ne pouvait aboutir).
Check post-impl: sh -c 's=UITests/stubs/immich_stub_partners.py; grep -qE "direction" "$s" && grep -qE "\"400\"|400" "$s" && grep -qE "shared-by" "$s" && grep -qE "shared-with" "$s" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun stub partenaires)
Post-state attendu: PASS
```

```
### AC-3113 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (724 tests, 2026-09-13) et TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_partners_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_partners_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 724 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
Note: l'original portait `-ge 200` pour une baseline de 724 — garde-fou inopérant.
```
