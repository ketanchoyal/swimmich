# Task: profile-picture

> **Audit 2026-09-15 — écart G16** : le client iOS n'a aucune surface « photo de profil » alors que
> l'upstream Flutter a une page dédiée (`/tmp/immich_router.dart:131` →
> `AutoRoute(page: ProfilePictureCropRoute.page)`, page
> `mobile/lib/presentation/pages/profile/profile_picture_crop.page.dart`) et que le serveur expose
> trois routes stables (`POST`/`DELETE /api/users/profile-image`, `GET /api/users/{id}/profile-image`) :
> `UserAvatarCircle.swift` ne dessine que des initiales, aucune vue ne charge d'image de profil.

**Objectif** : depuis « Me » → Account, l'utilisateur ouvre une vue « Profile Picture », y choisit une
photo de sa photothèque, la recadre en carré avec un cadre déplaçable, l'envoie
(`POST /api/users/profile-image`) et voit l'avatar changer immédiatement — dans la vue et dans les
avatars partagés de l'app ; il peut ensuite la supprimer (`DELETE /api/users/profile-image`) et
retomber sur ses initiales.

**Hors périmètre** :
- pas de choix de format ni de ré-encodage serveur (le serveur accepte un binaire, point) ;
- pas de suppression de la photo d'un **autre** utilisateur : `DELETE /api/users/profile-image` n'a
  pas de paramètre `{id}` ; pas d'édition de la photo des tiers (seul l'affichage l'est, étape 9) ;
- pas de modification de `avatarColor` ; pas d'appareil photo (`UIImagePickerController`) — la source
  est la photothèque, comme l'upstream.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main`, le 2026-09-15) :
- **Écriture** — OpenAPI publié `main` : `POST /api/users/profile-image`,
  `operationId: createProfileImage`, corps `multipart/form-data` schéma `CreateProfileImageDto` = un
  seul champ `file` (`type: string, format: binary, required`) ; réponse `201` =
  `CreateProfileImageResponseDto { userId: uuid, profileImagePath: string, profileChangedAt:
  date-time }`, les trois requis. `DELETE /api/users/profile-image`,
  `operationId: deleteProfileImage`, réponse `204` sans corps.
- **Lecture** (vérifiée par mes soins dans `/tmp/immich-openapi-main.json`) :
  `GET /api/users/{id}/profile-image` — `operationId: getProfileImage`, paramètre de chemin `id`
  (uuid), réponse `200` en `application/octet-stream` (`format: binary`),
  `x-immich-permission: userProfileImage.read`, `x-immich-state: Stable`. Les trois routes déclarent
  la même sécurité — `bearer` / `cookie` / `api_key` uniquement, aucun jeton en query string.
- **Identité fraîche** : `GET /api/users/me` existe et renvoie `UserAdminResponseDto`, qui porte déjà
  `profileImagePath`, `avatarColor`, `profileChangedAt` (`Sources/Core/Types/DTOs+Admin.swift:10-12`).
- `Sources/Services/MultipartBody.swift` sait déjà écrire **n'importe quel** champ fichier (surface
  publique : `append(name:filename:contentType:data:)` l.21, `writeStreamed(fileField:fields:to:)`
  l.46 — streaming disque par blocs de 1 Mio, jamais l'image entière en RAM, `contentType` l.94).
- `Sources/Services/ImmichAPIClient.swift:614` — `private func makeUploadBody(fileURL:filename:fields:)`
  existe mais **code en dur** `("assetData", "application/octet-stream")` ; ses deux appelants sont
  `ImmichAPIClient.swift:335` (upload depuis un lien partagé) et `:658` (`uploadAsset`).
- `Sources/Core/Types/EditState.swift:9-16` + `:46` : `CropAspectRatio` a déjà un cas `.square` et
  `EditState.cropRect` est un `CGRect` **normalisé 0..1, origine haut-gauche UIKit, relatif à l'extent
  ORIGINAL** — exactement la représentation d'un cadre de recadrage écran ; `EditPipeline` (l.18,61)
  le convertit en `CIImage` (flip Y compris), rien n'est à réécrire.
- `Sources/Services/AuthenticatedAsyncImage.swift:11-13` :
  `struct AuthenticatedAsyncImage { let url: URL?; let token: String?; … }` — le seul chargeur d'image
  authentifié de l'app (People, Memories, Albums, Duplicates), il pose l'en-tête `Authorization`.
- **État actuel qui rend la feature nécessaire** : `UserAvatarCircle`
  (`Sources/DesignSystem/Components/UserAvatarCircle.swift:7`) ne prend qu'un `UserResponseDto` et
  dessine `Circle().fill(Color(hex: user.avatarColor))` + `Text(initials)`, sans jamais lire
  `user.profileImagePath` (présent : `Sources/Core/Types/DTOs.swift:135`) ; ses sept appelants
  (étape 9) affichent donc des initiales même quand le serveur a une photo, et la section Account de
  `Sources/Features/Profile/ProfileView.swift:28-34` n'a que deux `LabeledContent` — aucun avatar.
- MVVM strict : `Sources/DependencyContainer.swift:81+` expose les fabriques `make*ViewModel()` qui
  injectent `client as any ImmichClient` ; `ProfileView` **porte** son `NavigationStack` (l.22), donc
  une vue poussée depuis lui n'en déclare pas (règle suivie par `LanguageSettingsView`).

**Approche retenue** : A — trois méthodes ajoutées au protocole `ImmichClient` (lecture d'identité,
upload, suppression), un `ProfilePictureViewModel` `@Observable @MainActor` qui recadre en carré en
réutilisant `EditState`/`EditPipeline`, et une vue poussée sans `NavigationStack` bâtie sur
`PhotosPicker` + le chargeur authentifié existant.
- **B (rejetée)** : envoyer l'image telle quelle, sans recadrage → mesurable : l'avatar est rendu
  `.scaledToFill()` puis `.clipped()` dans un `Circle`, donc une photo 4:3 est rognée au hasard de son
  centre et le visage sort du cadre ; c'est pourquoi l'upstream impose `ProfilePictureCropRoute` avant
  l'upload, et aucune route serveur ne recadre (`CreateProfileImageDto` n'a qu'un champ `file`).
- **C (rejetée)** : charger l'image avec `AsyncImage(url:)` en mettant le jeton dans l'URL
  (`?accessToken=…`) → mesurable : les trois routes profil ne déclarent que `bearer`/`cookie`/`api_key`
  (OpenAPI ci-dessus), un jeton en query ne serait jamais lu → 401 sur chaque avatar ; et
  `AuthenticatedAsyncImage`, déjà utilisé par 5 écrans, répond à ce besoin via le `ImageCache` partagé.

## Étapes
1. **DTO de réponse** — EDIT `Sources/Core/Types/DTOs.swift` : ajouter
   `struct CreateProfileImageResponseDto: Codable, Equatable { let userId: String; let
   profileImagePath: String; let profileChangedAt: String }` à côté de `UserResponseDto`
   (l.134-138), commentaire citant route et schéma OpenAPI.
2. **Protocole client** — EDIT `Sources/Core/Protocols/ImmichClient.swift` : sous `// MARK: - Users`
   (l.254-255, à côté de `func getUsers()`), déclarer `func getMyUser() async throws ->
   UserAdminResponseDto`, `func uploadProfileImage(fileURL: URL, filename: String, contentType:
   String) async throws -> CreateProfileImageResponseDto` et `func deleteProfileImage() async throws`.
   Aucune méthode existante n'est modifiée.
3. **Généraliser l'assembleur multipart** — EDIT `Sources/Services/ImmichAPIClient.swift:614` :
   `makeUploadBody(fileURL:filename:fields:)` devient `makeUploadBody(fieldName: String, contentType:
   String, fileURL:filename:fields:)` et transmet ces valeurs à `writeStreamed(fileField: (fieldName,
   filename, contentType, fileURL), …)` au lieu des littéraux. Les deux appelants (`:335`, `:658`)
   passent explicitement `fieldName: "assetData", contentType: "application/octet-stream"` : l'upload
   d'assets reste inchangé au caractère près, la fonction devient réutilisable.
4. **Implémentation HTTP** — EDIT `Sources/Services/ImmichAPIClient.swift`, nouvelle section
   `// MARK: - Profile picture (gap G16)` après `getUsers()` (l.609) :
   - `getMyUser()` : `try await sendAuthed(.GET, path: ImmichAPI.users.path("/me"))` ;
   - `uploadProfileImage(fileURL:filename:contentType:)` : `makeUploadBody(fieldName: "file",
     contentType: contentType, fileURL:, filename:, fields: [])` → `baseRequest(.POST, path:
     ImmichAPI.users.path("/profile-image"), query: [], auth: true)` + en-tête `Content-Type`
     (`multipart.contentType`, forme de `uploadAsset` l.658-663) → `dispatchUpload(request, fromFile:
     multipart.file)` avec `defer { try? FileManager.default.removeItem(at: multipart.file) }`, puis
     décodage de `CreateProfileImageResponseDto`. Aucun `x-immich-checksum` : en-tête réservé aux
     assets (`ImmichAPI.checksumHeader`) ;
   - `deleteProfileImage()` : `_ = try await sendAuthedRaw(.DELETE, path:
     ImmichAPI.users.path("/profile-image"), body: nil)` — 204 sans corps, forme de `deleteAPIKey`
     (l.587).
5. **URL de lecture** — EDIT `Sources/Services/ImmichAssetURL.swift` : ajouter `static func
   profileImage(userId: String, changedAt: String?, baseURL: URL) -> URL` =
   `baseURL.appendingPathComponent(ImmichAPI.users.path("/\(userId)/profile-image"))` plus un
   `URLQueryItem(name: "v", value: changedAt)` quand `changedAt` est non nil — même rôle de
   brise-cache que `thumbhash` dans `thumbnail(…)` (l.23-35) : `ImageCache` indexe par URL, sans `v`
   une photo remplacée resterait cachée.
6. **ViewModel** — NEW `Sources/Features/Profile/ProfilePictureViewModel.swift` :
   `@Observable @MainActor final class ProfilePictureViewModel` avec `private let client: any
   ImmichClient`, `private let baseURL: URL?`, `private let token: String?` et l'état
   `enum Phase { idle, loading, saving, deleting }`, `private(set) var phase: Phase = .idle`,
   `private(set) var profile: UserAdminResponseDto?`, `var errorMessage: String?`,
   `private(set) var pendingImage: UIImage?`, `private(set) var cropRect: CGRect` (normalisé 0..1,
   défaut carré centré). Comportements :
   - `load()` → `phase = .loading`, `profile = try await client.getMyUser()` ; sur échec `errorMessage`
     renseigné et le `profile` précédent conservé (pattern `MapViewModel`) ;
   - `avatarURL` via `ImmichAssetURL.profileImage(userId:changedAt:baseURL:)` et
     `hasPhoto { !(profile?.profileImagePath ?? "").isEmpty }` ;
   - `choose(_ image:)` → garde `pendingImage`, `cropRect = Self.centeredSquare(...)`, refuse avec
     `errorMessage` une image dont le plus petit côté fait moins de 128 px ;
   - `static func centeredSquare(for size: CGSize) -> CGRect` : carré centré en espace normalisé,
     reprenant l'arithmétique de `PhotoEditorViewModel.setAspectRatio` (l.182-202) ;
   - `save()` → rend `EditState(aspectRatio: .square, cropRect: cropRect)` sur `CIImage(image:
     pendingImage!)`, applique `EditPipeline.applyEditState(to:state:)`, redimensionne à 512×512,
     encode en JPEG qualité 0.9 sous `profile.jpg` dans le dossier temporaire, appelle
     `client.uploadProfileImage(...)`, puis remplace `profile` par la version portant les
     `profileImagePath`/`profileChangedAt` de la réponse ; fichier temporaire supprimé dans un `defer` ;
   - `deletePhoto()` → `client.deleteProfileImage()` puis `profile.profileImagePath = ""` (le 204 ne
     renvoie rien : `profileChangedAt` inchangé) ; `clearError()` → `errorMessage = nil`.
7. **Vue** — NEW `Sources/Features/Profile/ProfilePictureView.swift` : `struct ProfilePictureView:
   View` avec `@Bindable var vm: ProfilePictureViewModel` et `@Environment(AuthViewModel.self)
   private var auth` — **pas** de `NavigationStack` (poussée depuis `ProfileView`).
   - En-tête : avatar 120 pt — `AuthenticatedAsyncImage(url: vm.avatarURL, token: auth.accessToken)`
     `.scaledToFill()` clippé en `Circle` quand `vm.hasPhoto`, sinon le rendu d'initiales ;
     `.accessibilityIdentifier("profilePictureAvatar")`.
   - `PhotosPicker(selection:matching: .images)` → `.onChange` charge `UIImage(data:)` puis
     `vm.choose(...)`. Recadrage : quand `vm.pendingImage != nil`, un `GeometryReader` affiche l'image
     en `.scaledToFit()` avec un masque assombri autour de `vm.cropRect` et un `DragGesture` qui
     déplace le carré en le bornant dans 0..1 — la conversion écran → normalisé passe par
     `EditPipeline.gestureRectToNormalized(_:in:)` (l.111), pas par un calcul ad hoc.
   - Actions : « Save » (`profilePictureSave`, désactivé si `pendingImage == nil` ou
     `phase == .saving`) et « Remove Photo » (destructif, `.confirmationDialog`, affiché seulement si
     `vm.hasPhoto`, identifiant `profilePictureRemove`) ; `.alert("Could not update profile picture",
     isPresented:)` piloté par `vm.errorMessage` ; `.task { await vm.load() }` ; formulaire
     `.disabled` pendant `.saving`/`.deleting`.
8. **Avatar partagé** — EDIT `Sources/DesignSystem/Components/UserAvatarCircle.swift` : ajouter
   `var baseURL: URL? = nil` et `var token: String? = nil` ; `body` affiche
   `AuthenticatedAsyncImage(url: ImmichAssetURL.profileImage(userId: user.id, changedAt:
   user.profileChangedAt, baseURL: baseURL), token: token)` `.scaledToFill()` clippé en `Circle`
   quand `!user.profileImagePath.isEmpty && baseURL != nil`, sinon le `ZStack` d'initiales actuel.
   `initials(from:)` reste inchangé (il sert de repli).
9. **Appelants de l'avatar** — EDIT sept sites, pour que la photo apparaisse partout et pas seulement
   dans « Me » : `Sources/Features/PhotoViewer/PhotoViewer.swift:1030` et
   `Sources/Features/Partners/InvitePartnerSheet.swift:47` ; sous `Sources/Features/Albums/` :
   `AlbumDetailView.swift:601`, `ActivityFeedSheet.swift:112`, `AlbumShareSheet.swift:109`, `:131`,
   `:232` — ajouter `baseURL: auth.baseURL, token: auth.accessToken` (ces vues portent déjà
   `@Environment(AuthViewModel.self)`).
10. **Injection** — EDIT `Sources/DependencyContainer.swift` : `func makeProfilePictureViewModel() ->
    ProfilePictureViewModel { ProfilePictureViewModel(client: client as any ImmichClient, baseURL:
    baseURL, token: accessToken) }`, en suivant la forme des fabriques voisines (l.123-133) : c'est le
    seul point qui connaît les identifiants.
11. **Câblage racine** — EDIT `Sources/RootView.swift` : `_profilePicture = State(initialValue:
    container.makeProfilePictureViewModel())` dans `AuthenticatedRoot.init` (l.118-135), et
    `ProfileView(… profilePicture: profilePicture)` à la ligne 234.
12. **Section Account** — EDIT `Sources/Features/Profile/ProfileView.swift` : `@State var
    profilePicture: ProfilePictureViewModel` (bloc l.13-24) puis, en tête de la section Account
    (l.28-34), un `NavigationLink { ProfilePictureView(vm: profilePicture) } label:` portant l'avatar
    40 pt (`UserAvatarCircle` alimenté par `auth`) + `Text("Profile Picture")` et
    `.accessibilityIdentifier("profilePictureRow")` ; les `LabeledContent` Name/Email restent dessous
    et le `NavigationStack` du formulaire reste le seul de la pile.
13. **Stubs de test** — EDIT `Tests/MockImmichClient.swift` : ajouter `var getMyUserResponse:
    UserAdminResponseDto?`, `var getMyUserError: Error?`, `var uploadProfileImageResponse:
    CreateProfileImageResponseDto?`, `var uploadProfileImageError: Error?`,
    `var deleteProfileImageError: Error?` et `var deleteProfileImageCallCount = 0`, dans le style des
    stubs existants (`getUsersResponse`, `deleteAPIKeyError`).
14. `xcodegen generate` (si un fichier a été ajouté) puis suite complète
    `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation
- **Nom exact du brise-cache** : `?v=<profileChangedAt>` est posé par analogie avec le web Immich et
  avec `thumbhash` chez nous ; l'OpenAPI ne déclare aucun query param sur
  `GET /users/{id}/profile-image`. Trancher avec `grep -rn "profile-image"
  <checkout immich>/web/src/lib/utils.ts`, ou contre un serveur : `curl -sI
  "$BASE/api/users/<id>/profile-image?v=0" -H "Authorization: Bearer $TOKEN"`. Si le serveur refuse le
  paramètre, replier sur une invalidation de clé dans `ImageCache`.
- **Format accepté par le serveur** : `CreateProfileImageDto` ne contraint pas le `contentType` ;
  l'upstream envoie un JPEG nommé `file`. Vérifier que `image/jpeg` passe avec `grep -rn
  "profile-image" <checkout immich>/server/src/controllers/user.controller.ts` (`FileInterceptor`).
- **Orientation EXIF** : `EditPipeline.applyEditState` suppose un `CIImage` déjà orienté (l'éditeur
  applique l'orientation EXIF au chargement). Une photo de photothèque avec `imageOrientation != .up`
  donnerait un carré tourné de 90°. Trancher par un test unitaire sur une fixture JPEG EXIF 6, ou en
  normalisant l'orientation dans `choose(_:)`.
- **`baseURL`/`accessToken` exposés par `DependencyContainer`** : l'étape 10 le suppose (c'est le cas
  pour `makeSharedLinkViewerViewModel`, l.123-127) — vérifier par lecture de
  `Sources/DependencyContainer.swift:1-80`, sinon passer `auth.baseURL`/`auth.accessToken` depuis `ProfileView`.
- **`UserAdminResponseDto` est majoritairement immuable par `let`**
  (`Sources/Core/Types/DTOs+Admin.swift:9-15`) : la mise à jour locale post-upload doit reconstruire la
  structure membre à membre, avec la liste exacte des champs. Trancher avec `jq -c
  '.components.schemas.UserAdminResponseDto.properties | keys' /tmp/immich-openapi-main.json` et le
  `init` de `DTOs+Admin.swift`, plutôt que d'ajouter un init partiel.
