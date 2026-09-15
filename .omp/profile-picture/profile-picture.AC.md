# Task: profile-picture

Status: planifié — **aucune AC ouverte** (écart G16 du registre `.omp/backlog/ImmichSwiftUI-backlog.md`).

## Plan (résumé)

**Objectif** : depuis « Me » → Account, l'utilisateur ouvre une vue « Profile Picture », choisit une photo
de sa photothèque, la recadre en carré avec un cadre déplaçable, l'envoie
(`POST /api/users/profile-image`) et voit l'avatar changer immédiatement — dans la vue et dans les
avatars partagés ; il peut ensuite la supprimer (`DELETE /api/users/profile-image`) et retomber sur ses
initiales.

**Approche retenue** : A — trois méthodes ajoutées au protocole `ImmichClient` (`getMyUser`,
`uploadProfileImage`, `deleteProfileImage`), un `ProfilePictureViewModel` `@Observable @MainActor` qui
recadre en carré en **réutilisant** `EditState`/`EditPipeline` (déjà en place), et une vue poussée sans
`NavigationStack` bâtie sur `PhotosPicker` + le chargeur authentifié existant `AuthenticatedAsyncImage`.

**Routes serveur (OpenAPI `main`, vérifiées le 2026-09-15)** : écriture `POST /api/users/profile-image`
(`createProfileImage`, `multipart/form-data`, unique champ `file` binaire, réponse `201`
`CreateProfileImageResponseDto { userId, profileImagePath, profileChangedAt }`) ; suppression
`DELETE /api/users/profile-image` (`deleteProfileImage`, `204` sans corps, **aucun paramètre `{id}`**) ;
**lecture** `GET /api/users/{id}/profile-image` (`getProfileImage`, `200` `application/octet-stream`,
`x-immich-permission: userProfileImage.read`) — cette troisième route est celle que la spec a dû
vérifier séparément de l'upstream Flutter, qui ne monte que la page de recadrage. Les trois déclarent la
même sécurité `bearer`/`cookie`/`api_key`, donc **aucun jeton en query string** (approche C rejetée).

**Étapes** : (1) EDIT `Sources/Core/Types/DTOs.swift` (`CreateProfileImageResponseDto`) ; (2) EDIT
`Sources/Core/Protocols/ImmichClient.swift` (3 méthodes sous `// MARK: - Users`, l.254) ; (3) EDIT
`Sources/Services/ImmichAPIClient.swift` — `makeUploadBody` (l.614) gagne `fieldName`/`contentType`,
ses deux appelants (`:335`, `:658`) passent `"assetData"` littéral, nouvelle section
`// MARK: - Profile picture (gap G16)` ; (4) EDIT `Sources/Services/ImmichAssetURL.swift`
(`profileImage(userId:changedAt:baseURL:)`) ; (5) NEW `Sources/Features/Profile/ProfilePictureViewModel.swift` ;
(6) NEW `Sources/Features/Profile/ProfilePictureView.swift` ; (7) EDIT
`Sources/DesignSystem/Components/UserAvatarCircle.swift` (repli initiales conservé) ; (8) EDIT sept
appelants de l'avatar (`PhotoViewer`, `InvitePartnerSheet`, `AlbumDetailView`, `ActivityFeedSheet`,
`AlbumShareSheet` ×3) ; (9) EDIT `Sources/DependencyContainer.swift` + `Sources/RootView.swift` +
`Sources/Features/Profile/ProfileView.swift` (ligne de hub) ; (10) EDIT `Tests/Mocks/MockImmichClient.swift`
(stubs) ; (11) NEW `Tests/ProfilePictureViewModelTests.swift` ; (12) `xcodegen generate` + suite.

**Incertitudes** : nom exact du brise-cache (`?v=<profileChangedAt>` est posé par analogie avec
`thumbhash` ; l'OpenAPI ne déclare aucun query param — si le serveur le refuse, replier sur
`ImageCache.invalidate`) ; `image/jpeg` accepté par le `FileInterceptor` ; orientation EXIF non
normalisée dans `choose(_:)` ; `UserAdminResponseDto` majoritairement `let` → reconstruction membre à
membre après upload.

## Critères

```
### AC-5160 [type: new — les trois routes réelles, chemins exacts]
Assertion: le protocole ImmichClient expose les trois méthodes de la feature et ImmichAPIClient les
implémente sur les chemins littéraux de l'OpenAPI — `POST` et `DELETE` sur le même
`ImmichAPI.users.path("/profile-image")`, upload multipart sous le champ `file` (jamais `assetData`),
et l'assembleur multipart existant reste utilisé par l'upload d'assets inchangé.
Check post-impl: sh -c 'p=Sources/Core/Protocols/ImmichClient.swift; c=Sources/Services/ImmichAPIClient.swift; grep -qE "func getMyUser\(\) async throws -> UserAdminResponseDto" "$p" && grep -qE "func uploadProfileImage\(fileURL: URL, filename: String, contentType: String\) async throws -> CreateProfileImageResponseDto" "$p" && grep -qE "func deleteProfileImage\(\) async throws" "$p" && n=$(grep -cE "ImmichAPI.users.path\(\"/profile-image\"\)" "$c"); n=${n:-0}; test "$n" -ge 2 && grep -qE "fieldName: \"file\"" "$c" && grep -qE "fieldName: \"assetData\"" "$c" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Core/Protocols/ImmichClient.swift` n'a que `func getUsers()` l.255 ; aucun `ImmichAPI.users.path("/profile-image")` dans `ImmichAPIClient.swift` ; `makeUploadBody` l.614 ne prend ni `fieldName` ni `contentType`)
Post-state attendu: PASS
Note: le `-ge 2` porte sur le compte des DEUX verbes (POST puis DELETE) — greper un seul mot laisserait
passer une carte qui n'implémente que l'envoi.
```

```
### AC-5161 [type: new — le chemin de LECTURE, celui que la spec a dû vérifier]
Assertion: l'URL de lecture de la photo passe par le seul chemin authentifié de l'app
(`ImmichAssetURL.profileImage(userId:changedAt:baseURL:)`) et vise `GET /api/users/{id}/profile-image` —
route absente de l'upstream Flutter (qui ne monte que la page de recadrage) et vérifiée par la spec dans
`/tmp/immich-openapi-main.json`.
Check post-impl: sh -c 'f=Sources/Services/ImmichAssetURL.swift; grep -qE "static func profileImage\(userId: String" "$f" && grep -qE "profile-image" "$f" && grep -qE "profileImagePath" Sources/Core/Types/DTOs+Admin.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`ImmichAssetURL.swift` n'a que `thumbnail(` l.15 ; aucun `profileImage`)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION (`static func profileImage(`) — un grep du seul mot `profileImage`
serait satisfait par un doc-comment citant la route.
```

```
### AC-5162 [type: new — aucune image périmée après changement (invalidation)]
Assertion: l'URL de lecture porte un brise-cache dérivé de `profileChangedAt` (même rôle que `thumbhash`
dans `thumbnail(…)`) ; le ViewModel et l'avatar partagé le reprennent, et le ViewModel remplace son
`profile` par la réponse de l'upload — donc la clé `ImageCache` change et l'ancienne photo ne peut pas
être resservie.
Check post-impl: sh -c 'u=Sources/Services/ImmichAssetURL.swift; v=Sources/Features/Profile/ProfilePictureViewModel.swift; a=Sources/DesignSystem/Components/UserAvatarCircle.swift; grep -qE "URLQueryItem\(name: \"v\"" "$u" && grep -qE "changedAt" "$u" && grep -qE "profileImage\(userId:" "$v" && grep -qE "profileChangedAt" "$v" && grep -qE "profileChangedAt" "$a" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`ImmichAssetURL.swift` ne construit aucune `URLQueryItem(name: "v"…)` ; ni le ViewModel ni `UserAvatarCircle` n'existent/ne lisent `profileChangedAt`)
Post-state attendu: PASS
Note: sans ce paramètre, `ImageCache` (indexé par URL) servirait l'ancienne photo après un upload puis
un retour sur l'écran — la feature « l'avatar change immédiatement » échouerait visuellement.
```

```
### AC-5163 [type: new — états et erreurs du ViewModel]
Assertion: ProfilePictureViewModel est `@Observable @MainActor`, expose l'énumération de phase à quatre
états (idle/loading/saving/deleting), un `errorMessage` optionnel, `clearError()`, et un `load()` qui sur
échec renseigne l'erreur SANS effacer le profil déjà connu (pattern `MapViewModel`).
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfilePictureViewModel.swift; test -f "$f" && grep -qE "@Observable" "$f" && grep -qE "@MainActor" "$f" && grep -qE "enum Phase" "$f" && grep -qE "case idle" "$f" && grep -qE "case loading" "$f" && grep -qE "case saving" "$f" && grep -qE "case deleting" "$f" && grep -qE "var errorMessage: String\?" "$f" && grep -qE "func clearError" "$f" && grep -qE "func load\(\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — aucun dossier `Sources/Features/Profile/ProfilePicture*`)
Post-state attendu: PASS
```

```
### AC-5164 [type: new — le recadrage carré réutilise l'éditeur existant]
Assertion: le carré de recadrage est calculé en espace normalisé 0..1 (`centeredSquare(for:)`), une image
dont le plus petit côté fait moins de 128 px est refusée avec un message, et l'envoi applique
`EditState(aspectRatio: .square)` via `EditPipeline.applyEditState` puis redimensionne à 512 avant
d'encoder en JPEG — pas de pipeline de recadrage réécrit.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfilePictureViewModel.swift; grep -qE "func choose\(" "$f" && grep -qE "centeredSquare" "$f" && grep -qE "128" "$f" && grep -qE "EditState\(aspectRatio: .square" "$f" && grep -qE "EditPipeline" "$f" && grep -qE "512" "$f" && grep -qE "func save\(\)" "$f" && grep -qE "defer" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: `CropAspectRatio.square` et `EditState.cropRect` (normalisé 0..1, origine haut-gauche) existent
déjà (`Sources/Core/Types/EditState.swift:9-16`) — un second pipeline serait du code mort.
```

```
### AC-5165 [type: new — l'écran, poussé donc sans NavigationStack]
Assertion: ProfilePictureView est une vue poussée depuis ProfileView : elle ne déclare AUCUN
`NavigationStack`, offre le choix de photo via `PhotosPicker`, le déplacement du cadre via
`DragGesture` converti par `EditPipeline.gestureRectToNormalized`, les identifiants
`profilePictureAvatar`/`profilePictureSave`/`profilePictureRemove` sur les éléments interactifs, une
confirmation avant suppression et une alerte d'erreur.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfilePictureView.swift; test -f "$f" && grep -qE "struct ProfilePictureView" "$f" && grep -qE "PhotosPicker" "$f" && grep -qE "DragGesture" "$f" && grep -qE "gestureRectToNormalized" "$f" && grep -qE "profilePictureAvatar" "$f" && grep -qE "profilePictureSave" "$f" && grep -qE "profilePictureRemove" "$f" && grep -qE "confirmationDialog" "$f" && grep -qE "\.task" "$f" && ! grep -qE "NavigationStack \{" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION (`NavigationStack {`) — un grep du seul mot échouerait sur le
doc-comment qui explique justement l'absence de stack (piège de la carte stacks-ui). Second
`NavigationStack` imbriqué dans une vue poussée depuis `ProfileView` (qui porte le sien, l.22) = pile
dupliquée.
```

```
### AC-5166 [type: new — la ligne du hub et le câblage racine]
Assertion: la section Account de ProfileView gagne une ligne « Profile Picture » portant son identifiant
qui pousse `ProfilePictureView`, le ViewModel est construit par le composition root (factory
`makeProfilePictureViewModel`) et possédé en un seul exemplaire par RootView, qui le passe à ProfileView.
Check post-impl: sh -c 'p=Sources/Features/Profile/ProfileView.swift; d=Sources/DependencyContainer.swift; r=Sources/RootView.swift; grep -qE "profilePictureRow" "$p" && grep -qE "ProfilePictureView\(vm:" "$p" && grep -qE "var profilePicture: ProfilePictureViewModel" "$p" && grep -qE "func makeProfilePictureViewModel" "$d" && grep -qE "makeProfilePictureViewModel" "$r" && grep -qE "profilePicture: profilePicture" "$r" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (la section Account de `ProfileView.swift:28-34` n'a que deux `LabeledContent` Name/Email ; aucune factory `makeProfilePictureViewModel` dans `DependencyContainer.swift`)
Post-state attendu: PASS
```

```
### AC-5167 [type: new — retombée sur les initiales après suppression]
Assertion: UserAvatarCircle accepte `baseURL`/`token` et affiche la photo seulement quand
`profileImagePath` est non vide, en conservant EXACTEMENT le rendu d'initiales actuel comme repli ; côté
ViewModel, `deletePhoto()` remet `profileImagePath` à vide après un `204` (qui ne renvoie aucun corps),
ce qui fait basculer l'avatar — et tous ses appelants — sur les initiales.
Check post-impl: sh -c 'a=Sources/DesignSystem/Components/UserAvatarCircle.swift; v=Sources/Features/Profile/ProfilePictureViewModel.swift; grep -qE "var baseURL: URL\?" "$a" && grep -qE "var token: String\?" "$a" && grep -qE "AuthenticatedAsyncImage" "$a" && grep -qE "profileImagePath" "$a" && grep -qE "initials\(from:" "$a" && grep -qE "func deletePhoto" "$v" && grep -qE "deleteProfileImage" "$v" && grep -qE "profileImagePath = \"\"" "$v" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`UserAvatarCircle.swift:6` ne déclare que `struct UserAvatarCircle` avec un `user` et dessine `Text(Self.initials(from: user.name))` l.13, sans jamais lire `profileImagePath`)
Post-state attendu: PASS
Note: le repli d'initiales reste atteignable — un avatar qui afficherait un cercle vide après
suppression serait une régression par rapport à l'état actuel.
```

```
### AC-5168 [type: new — tests unitaires + stubs]
Assertion: ProfilePictureViewModelTests expose ≥ 8 cas nommés couvrant le chargement, l'échec de
chargement, le refus d'une image trop petite, le recadrage carré + upload, la suppression, le repli
après suppression et le changement de brise-cache ; `MockImmichClient` gagne les stubs correspondants.
Check post-impl: sh -c 'f=Tests/ProfilePictureViewModelTests.swift; m=Tests/Mocks/MockImmichClient.swift; test -f "$f" && n=$(grep -cE "func test_" "$f" 2>/dev/null); n=${n:-0}; test "$n" -ge 8 && grep -qE "test_load_setsProfile" "$f" && grep -qE "test_load_failure_setsErrorMessage" "$f" && grep -qE "test_choose_rejectsImageSmallerThan128" "$f" && grep -qE "test_save_cropsToSquareAndUploads" "$f" && grep -qE "test_delete_clearsProfileImagePath" "$f" && grep -qE "test_avatarURL_changesWithProfileChangedAt" "$f" && grep -qE "var uploadProfileImageResponse" "$m" && grep -qE "var deleteProfileImageCallCount" "$m" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier de test absent ; `Tests/Mocks/MockImmichClient.swift` n'a ni `uploadProfileImageResponse` ni `deleteProfileImageCallCount`)
Post-state attendu: PASS
Note: le stub vit dans `Tests/Mocks/MockImmichClient.swift` (pas `Tests/MockImmichClient.swift`, chemin
erroné dans la spec — vérifié le 2026-09-15). Un nouveau fichier n'est compilé qu'après
`xcodegen generate` : sans régénération la suite passe « verte » par omission.
```

```
### AC-5169 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests,
`-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED — la généralisation de `makeUploadBody` ne casse
pas l'upload d'assets, ses deux appelants passant toujours `assetData`/`application/octet-stream`.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_profilepicture_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_profilepicture_test.log | grep -oE "[0-9]+" | sort -n | tail -1); n=${n:-0}; test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
