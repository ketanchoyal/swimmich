# Task: sync-badge

> **Audit 2026-09-15 — écart G6** : aucun état de sauvegarde n'est lisible par tuile, faute de pont
> entre le ledger de sauvegarde (`Sources/Services/BackupLedger.swift`, alimenté par `BackupEngine`)
> et le rendu (`AssetThumbnailCell.topLeadingBadges`,
> `Sources/Features/Timeline/AssetThumbnailCell.swift:152-175`) — le seul badge de statut d'asset
> existant est `offlineBadge` (cache disque, `Sources/Features/Offline/OfflineAssetIndex.swift`),
> qui répond à une autre question. Le client Flutter rend cette paire d'icônes (`cloud-off` /
> `cloud-check`) sur chaque tuile de sa liste d'assets
> (`mobile/lib/widgets/settings/asset_list_settings/*`, `docs/docs/features/mobile-app.mdx` § *Sync
> only selected photos*).

**Objectif** : un réglage « Afficher l'état de sauvegarde » dans l'écran Backup allume un badge sur
chaque tuile de la timeline indiquant si ce média est prouvé sauvegardé sur le serveur
(`checkmark.icloud`) ou si la copie serveur n'est pas celle poussée par cet appareil
(`icloud.slash`), l'absence d'information ne rendant rien. L'état vient du ledger local, déjà
alimenté à chaque upload et à chaque réconciliation, complété par l'`assetId` serveur renvoyé par
`POST /api/assets/bulk-upload-check`.

**Hors périmètre** : refonte de la réconciliation du ledger ; badge sur la PhotoViewer ; badge sur
les tuiles de `TrashView` / `SharedLinkViewerView` (elles instancient le même `AssetThumbnailCell`,
donc le badge y apparaît mécaniquement mais n'est ni testé ni asserté là) ; galerie des médias
**locaux** de l'appareil équivalente à `asset_list_settings` du client Flutter — elle n'existe pas
dans ce dépôt et n'est pas créée ici ; toute nouvelle route serveur.

**Hypothèses** (vérifiées dans le dépôt et contre `immich-app/immich@main`, le 2026-09-15) :
- `AssetThumbnailCell` lit déjà un index partagé par l'environnement plutôt que par paramètre :
  `@Environment(OfflineAssetIndex.self) private var offline: OfflineAssetIndex?`
  (`Sources/Features/Timeline/AssetThumbnailCell.swift:22`, avec le commentaire l.19-21 qui motive
  ce choix : « this cell is instantiated from six different grids, and a parameter would eventually
  be forgotten at one of them ») — c'est la couture à réutiliser. L'index est injecté globalement
  par `Sources/RootView.swift:173` (`.environment(container.offlineIndex)`) et construit dans
  `Sources/DependencyContainer.swift:69`.
- `topLeadingBadges` (`AssetThumbnailCell.swift:152-175`) est un `VStack` qui empile déjà 360° /
  `offlineBadge` / `stackBadge`, posé par `.overlay(alignment: .topLeading)` (l.72) ; la capsule
  commune est `badge<Content>(_:)` (l.240-251, `.ultraThinMaterial` + bord blanc 0,25) et
  `offlineBadge` (l.188-195) est le patron exact à copier, `accessibilityIdentifier("offlineBadge")`
  posé sur **l'élément badge lui-même** et non sur le conteneur (l.185-187 documente le piège : un
  identifiant sur un conteneur écrase celui des descendants).
- `AssetThumbnailCell.asset` est un `AssetReactItem` (`Sources/Core/Types/AssetReactItem.swift`) :
  `let id: String` est un **UUID serveur**, pas un identifiant de photothèque. La timeline ne sert
  que des assets serveur (`Sources/Features/Timeline/TimelineViewModel.swift:161` `getTimeBuckets`,
  `:213` `getTimeBucket`) et aucun écran ne rend de tuile portant un `PHAsset.localIdentifier` (`rg
  -n "PHAsset|localIdentifier" Sources/Features` → seul
  `Sources/Features/Upload/UploadViewModel.swift`), d'où l'API d'index à **deux espaces de noms
  explicites**, sans heuristique sur la forme de l'id.
- `BackupLedgerStoring` (`Sources/Core/Protocols/BackupLedgerStoring.swift:12-25`) expose
  `isBackedUp(id:signature:)`, `markBackedUp(id:signature:checksum:)`, `entriesForReconciliation()
  -> [(id: String, checksum: String)]`, `forget(ids:)`, `lastReconciliation`,
  `recordReconciliation(at:)` ; l'id de ledger est `BackupCandidate.id` (identifiant de
  photothèque), la clé de tri de `BackupEngine.run()` étant `!ledger.isBackedUp(id: $0.id,
  signature: $0.fileModifiedAt)` (`Sources/Services/BackupEngine.swift:264`). Le fichier est
  versionné (`BackupLedger.currentVersion = 2`, `Sources/Services/BackupLedger.swift`) avec repli v1
  `[String: String]`, et les entrées v1 n'ont **pas** de checksum (documenté l.18-21 de la classe) :
  un `serverAssetId` optionnel est une extension de même nature.
- `POST /api/assets/bulk-upload-check` (`operationId: checkBulkUpload`, tag `Assets`, security
  `bearer`) : corps `AssetBulkUploadCheckDto { assets: [AssetBulkUploadCheckItem] }`,
  `AssetBulkUploadCheckItem { checksum: String /* Base64 or hex encoded SHA1 */, id: String /*
  client-side identifier echoed in the response */ }`, réponse `AssetBulkUploadCheckResponseDto {
  results: [AssetBulkUploadCheckResult] }` avec `AssetBulkUploadCheckResult { action:
  AssetUploadAction, id: String, assetId?: uuid, isTrashed?: Bool, reason?: AssetRejectReason }` —
  c'est **le seul endroit où le serveur renvoie l'UUID d'un asset déjà présent** pour un identifiant
  client donné.
- Le client et le ledger existent déjà : `ImmichClient.bulkUploadCheck(_:)`
  (`Sources/Core/Protocols/ImmichClient.swift:278`, impl
  `Sources/Services/ImmichAPIClient.swift:673`), DTO `AssetBulkUploadCheckRequest`
  (`Sources/Core/Types/DTOs.swift:217`) / `Response` (`:225`), appelés depuis
  `BackupEngine.swift:443` (upload) et `:628` (réconciliation, `entriesForReconciliation()` à
  `:620`).
- Les deux chemins du ledger qui **tiennent déjà** l'UUID serveur : `ledger.markBackedUp(...)` du
  chemin reject (`BackupEngine.swift:451`, la réponse de check porte `assetId` sur un `action ==
  "reject"`) et celui du chemin accept après upload (`:550`). `ledger.save()` est appelé une fois
  par chunk et en fin de run (`:363`, `:382`).
- Le réglage vit dans `BackupSettingsStore` (`Sources/Features/Upload/UploadViewModel.swift:24`),
  `@Observable`, avec ses clés `isEnabled` (`:27`), `autoDetectNewPhotos` (`:50`), `albumScope`
  (`:56`), `excludedAlbumIDs` (`:69`) et un `snapshot() -> BackupSettings` (`:140`) consommé par
  `BackupEngine.run()` ; l'écran est `BackupSettingsView` dans le même fichier (`:444`), poussé
  depuis le hub « Me ».

**Approche retenue** : A — un **index de statut cloud observable**, alimenté par le ledger et lu par
l'environnement.
- Le ledger gagne `serverAssetId` (donnée déjà reçue, jamais persistée) ; un
  `CloudBackupStatusIndex` `@MainActor @Observable` construit deux ensembles (`uploadedServerIDs`,
  `uploadedLocalIDs`) et répond `status(forServerAssetID:)` / `status(forLocalAssetID:)`.
  `AssetThumbnailCell` lit cet index depuis l'environnement (patron `offline` l.22) et ne fait qu'un
  `if let status` — aucune logique de statut dans la vue, conforme au MVVM strict.
- **B (rejetée)** : appeler `bulkUploadCheck` depuis `TimelineViewModel` à chaque page de buckets →
  impossible sans checksum : la réponse de `getTimeBucket` (`TimelineViewModel.swift:213`) ne porte
  pas de SHA1 et le recalculer exigerait de re-télécharger chaque original, exactement le coût que
  le ledger existe pour éviter (`BackupLedger.swift`, commentaire de `Entry.checksum`).
- **C (rejetée)** : dériver le statut en comparant `asset.id` à la clé du ledger, sans champ
  `serverAssetId` → les deux espaces de noms ne se rencontrent jamais (l'UUID serveur n'apparaît
  nulle part dans le ledger), le badge resterait éteint sur toute la timeline : aucune preuve
  possible, donc feature morte.

## Étapes
1. **Statut de badge** — NEW `Sources/Core/Types/CloudBackupStatus.swift` : `enum CloudBackupStatus:
   Equatable, Sendable { case uploaded, localOnly }` avec un `var systemImage: String {
   "checkmark.icloud" / "icloud.slash" }` et un `var localizedLabel: String` (« Saved on server » /
   « Only on this device »).
2. **Ledger v3** — EDIT `Sources/Core/Protocols/BackupLedgerStoring.swift` :
   `markBackedUp(id:signature:checksum:serverAssetId:)` (dernier paramètre `String? = nil`), plus
   `func uploadedServerAssetIDs() -> Set<String>` et `func hasUploaded(id: String) -> Bool` ; les
   deux derniers sont volontairement des lectures d'ensemble (un lookup `O(1)` par tuile) et non un
   parcours d'entrées comme `entriesForReconciliation()`.
3. **Ledger v3 (stockage)** — EDIT `Sources/Services/BackupLedger.swift` : `Entry` gagne
   `serverAssetId: String?`, `Snapshot.currentVersion` passe à 3, `ensureLoaded()` accepte v3 puis
   retombe sur v2 puis sur la map v1 (le champ est optionnel : un fichier v2 se décode tel quel) ;
   les nouveaux accesseurs reconstruisent les ensembles sous `lock`.
4. **Alimentation du ledger** — EDIT `Sources/Services/BackupEngine.swift` : au chemin reject
   (`:451`) passer `result.assetId` (nil si `action == "accept"`), au chemin accept (`:550`) passer
   l'id de la réponse d'upload ; ajouter `var onLedgerChange: (@Sendable () -> Void)?` appelé après
   chaque `ledger.save()` (`:363`, `:382`) et après `reconcileLedgerIfDue()` (`:646-648`).
5. **Index de statut** — NEW `Sources/Services/CloudBackupStatusIndex.swift` : `@MainActor
   @Observable final class CloudBackupStatusIndex` avec `private(set) var isEnabled = false`,
   `private(set) var uploadedServerIDs: Set<String>`, `private(set) var uploadedLocalIDs:
   Set<String>` ; `func refresh(ledger: any BackupLedgerStoring)` recharge les deux ensembles, `func
   status(forServerAssetID id: String) -> CloudBackupStatus?` (`.uploaded` si présent, `nil` sinon —
   **jamais** `.localOnly` pour un id serveur, cf. Incertitudes), `func status(forLocalAssetID id:
   String) -> CloudBackupStatus?` (`.uploaded` / `.localOnly`).
6. **Réglage** — EDIT `Sources/Features/Upload/UploadViewModel.swift` : `BackupSettingsStore` gagne
   `showSyncBadge: Bool` persisté sous la clé `photoBackupShowSyncBadge` (défaut `false`, même
   patron que `autoDetectNewPhotos:50`), le champ entre dans `BackupSettings` (`snapshot():140`) ;
   `UploadViewModel` gagne `func syncBadgeIndex()` qui pousse `settings.showSyncBadge` dans l'index
   ; `BackupSettingsView` (`:444`) gagne une `Toggle("Show backup status on thumbnails", isOn:
   $settings.showSyncBadge)` avec `accessibilityIdentifier("syncBadgeToggle")`, dans la section qui
   porte déjà les bascules de la même famille.
7. **Câblage** — EDIT `Sources/DependencyContainer.swift` : `let cloudStatus =
   CloudBackupStatusIndex()` à côté de `offlineIndex` (`:48`, `:69`) ; après construction du moteur,
   poser `engine.onLedgerChange = { [weak cloudStatus] in Task { @MainActor in
   cloudStatus?.refresh(ledger: ledger) } }` **et** un `refresh` initial avec le ledger persistant
   (l'app doit afficher le bon état dès le premier lancement, avant tout run) ;
   `makeUploadViewModel()` pousse le réglage lu au démarrage.
8. **Environnement** — EDIT `Sources/RootView.swift:173` : `.environment(container.cloudStatus)`
   juste après `.environment(container.offlineIndex)`.
9. **Rendu** — EDIT `Sources/Features/Timeline/AssetThumbnailCell.swift` :
   `@Environment(CloudBackupStatusIndex.self) private var cloudStatus: CloudBackupStatusIndex?`
   (commentaire miroir de l.19-21) ; `private var cloudBadge: some View` construite avec `badge {
   Image(systemName: status.systemImage) }`, `accessibilityElement(children: .ignore)`,
   `accessibilityIdentifier(status == .uploaded ? "cloudBackedUpBadge" : "cloudLocalOnlyBadge")`,
   `accessibilityLabel(status.localizedLabel)` — identifiant sur le badge, jamais sur le `VStack`
   (l.185-187) ; insertion dans `topLeadingBadges` (`:152-175`) **après** `offlineBadge` et avant
   `stackBadge`, et garde `if cloudStatus?.isEnabled == true, let status =
   cloudStatus?.status(forServerAssetID: asset.id)`. Un seul `if`, aucune mutation : la vue reste
   stateless.
10. **i18n** — EDIT `Resources/Localizable.xcstrings` : les deux libellés du badge et le libellé de
    la bascule, avec `fr` renseigné, `String(localized:)` côté code (catalogue, cf. décision i18n du
    2026-09-14).
11. **Tests** — NEW `Tests/CloudBackupStatusIndexTests.swift` : ledger en mémoire
    (`BackupLedger.inMemory()`) → `markBackedUp(id:signature:checksum:serverAssetId:)` puis
    `refresh(ledger:)` ; assert `status(forServerAssetID:) == .uploaded`, `status(forLocalAssetID:)
    == .uploaded`, `status(forLocalAssetID: "jamais-vu") == .localOnly`, `status(forServerAssetID:
    "uuid-inconnu") == nil`, et `isEnabled == false` → toutes les réponses `nil` (badge éteint =
    feature muette). EDIT le fichier de mock qui conforme `BackupLedgerStoring` (`rg -ln
    "BackupLedgerStoring" Tests` → un seul fichier) pour la nouvelle signature.
12. `xcodegen generate` (fichiers ajoutés aux étapes 1, 5, 11) puis suite complète
    `-only-testing:ImmichSwiftUITests`.

## Incertitudes à lever à l'implémentation
- **Signification exacte de `.localOnly` sur une tuile de timeline** : la timeline ne sert que des
  UUID serveur (`TimelineViewModel.swift:161`), donc `icloud.slash` y serait faux pour un asset
  uploadé depuis un autre appareil. L'étape 5 renvoie donc `nil` (aucun badge) pour un id serveur
  inconnu du ledger, plutôt que d'afficher un mensonge ; si l'on veut vraiment l'état « seulement
  sur l'appareil », il faut la galerie locale absente du dépôt. Trancher avec : `rg -n
  "AssetThumbnailCell\(" Sources` (7 surfaces, toutes serveur) puis `rg -n "localIdentifier|PHAsset"
  Sources/Features`.
- **Nom exact du mock de ledger** : `rg -ln "BackupLedgerStoring" Tests` (le fichier qui conforme le
  protocole est unique et vit sous `Tests/`).
- **Point d'appel de `onLedgerChange` depuis le chemin acteur du moteur** : vérifier la déclaration
  de `BackupEngine` (acteur ou classe) et l'isolation de `onProgressUpdate` — `rg -n
  "onProgressUpdate|^final class BackupEngine|^actor BackupEngine"
  Sources/Services/BackupEngine.swift` — avant de copier le patron de rappel.
- **Libellés définitifs du catalogue** : la clé `fr` doit suivre le vocabulaire déjà retenu pour «
  sauvegarde » dans `Resources/Localizable.xcstrings` — `rg -n "Back up|backed up"
  Resources/Localizable.xcstrings | head`.
