# Task: sync-badge — UI Brief

> Compagnon de `.omp/sync-badge/sync-badge.specs.md` (écrit le 2026-09-15). Ne pas dupliquer la spec : ce document ne décrit
> que la **surface** — une bascule dans l'écran Backup, un badge dans `AssetThumbnailCell`, leurs états et leurs tokens.

## Design Philosophy

Le badge répond à une seule question, posée devant une grille de mille tuiles : **« celle-ci est-elle déjà sur le
serveur ? »**. C'est un **constat**, pas une activité : il n'anime rien, il ne tourne pas, il n'apparaît pas pendant un
upload. Deux conséquences gouvernent tout le reste :

1. **L'absence d'information ne se dessine pas.** Si le ledger ne sait rien de cet asset, la tuile est nue — pas de badge
   gris, pas de point d'interrogation, pas de `icloud.slash`. Un badge muet mais faux coûte plus cher qu'un badge absent :
   il ferait douter d'un asset uploadé depuis un autre appareil.
2. **La cellule ne travaille pas.** Aucun appel réseau, aucun formatage, aucun accès disque depuis `AssetThumbnailCell` :
   elle lit un ensemble en mémoire et affiche une icône, parce qu'un écran de timeline rend des centaines de cellules.

L'icône est **seule dans sa capsule**, contrairement aux badges texte voisins (`360°`, `+2`, `mm:ss`) : un mot y serait
illisible et volerait la largeur du badge 360°. Le sens est porté par le glyphe pour l'œil, par `status.localizedLabel`
pour VoiceOver.

## Placement dans la navigation

Deux surfaces, deux placements, aucune navigation nouvelle :

- **La bascule** : `Toggle("Show backup status on thumbnails")` dans `BackupSettingsView`
  (`Sources/Features/Upload/UploadViewModel.swift:549`, la `Section` `header: Text("Auto backup")` qui porte déjà « Auto
  backup », « Wi-Fi only », « Charging only », « Back up new photos automatically »), **en dernier dans la section**, avec
  `accessibilityIdentifier("syncBadgeToggle")`. Le footer existant est conservé tel quel : le badge se règle là où sont
  les autres réglages de sauvegarde.
- **Le badge** : dans `AssetThumbnailCell`, donc dans **toutes** les grilles qui l'instancient (timeline, `AlbumDetailView`,
  `AssetMultiSelectGrid`, recherche, corbeille, viewer de lien partagé). Le comportement dans ces dernières est mécanique
  et hors périmètre (cf. spec) — aucune bascule n'y est ajoutée.
- `BackupSettingsView` est **poussée depuis `ProfileView`** (hub « Me »), qui porte déjà son `NavigationStack` : ni l'écran
  ni la cellule ne déclarent de stack, de feuille ou de rôle d'onglet.

## Layout

```
BackupSettingsView (Form)                              AssetThumbnailCell (Image + overlays)
└── Section "Auto backup"                              └── .overlay(alignment: .topLeading)
    ├── Toggle "Auto backup"                               └── topLeadingBadges: VStack(alignment: .leading, spacing: 4)
    ├── Toggle "Wi-Fi only"                                    ├── if projectionType == "equirectangular"
    │   └── Toggles cellulaires (si Wi-Fi only)                │       └── badge { Text("360°") }
    ├── Toggle "Charging only"                                 ├── if isCachedOffline
    ├── Toggle "Back up new photos automatically"              │       └── offlineBadge     ("arrow.down.circle.fill")
    ├── Toggle "Show backup status on thumbnails"   ← NEW      ├── if cloudStatus?.isEnabled == true, let status ← NEW
    │       .accessibilityIdentifier("syncBadgeToggle")        │       └── cloudBadge       (status.systemImage)   ← NEW
    └── footer (inchangé)                                      └── if asset.isStacked
                                                                       └── badge { square.stack.fill + "+N" }
```

- La pile du coin haut-gauche garde **son ordre** : 360° → offline → cloud → stack. Le badge de pile reste le dernier, il
  ferme la colonne visuellement (il est le plus large).
- Aucune autre modification de la cellule : ni le `Text("+N")`, ni la capsule `badge`, ni `isCachedOffline`, ni le coin
  haut-droit (favori) ne bougent.

## Composants

Réutiliser, ne rien créer côté DesignSystem : l'enveloppe est la capsule privée `badge<Content>(_:)` d'`AssetThumbnailCell`
(`.ultraThinMaterial` + bord blanc 0,25 + ombre micro), l'icône un `Image(systemName:)`, la bascule un `Toggle` de `Form`
comme ses quatre voisines. Le badge suit le patron d'`offlineBadge` (`AssetThumbnailCell.swift:188-195`), glyphe compris :

```swift
@Environment(CloudBackupStatusIndex.self) private var cloudStatus: CloudBackupStatusIndex?

/// Cloud backup pill — top-leading, between the offline pill and the stack
/// badge. Absence of information renders nothing: the ledger answers only for
/// assets it knows, and a false "not backed up" is worse than no badge.
@ViewBuilder
private var cloudBadge: some View {
    if cloudStatus?.isEnabled == true,
       let status = cloudStatus?.status(forServerAssetID: asset.id) {
        badge {
            Image(systemName: status.systemImage)
                .font(.system(size: 10)) // DS-exempt: badge micro-glyph §8.6
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(status == .uploaded ? "cloudBackedUpBadge" : "cloudLocalOnlyBadge")
        .accessibilityLabel(status.localizedLabel)
    }
}

// Sources/Features/Upload/UploadViewModel.swift — section "Auto backup"
Toggle("Show backup status on thumbnails", isOn: $vm.settings.showSyncBadge)
    .onChange(of: vm.settings.showSyncBadge) { _, _ in vm.syncBadgeIndex() }
    .accessibilityIdentifier("syncBadgeToggle")
```

**Icônes — décidé, pas au choix :**

| État | SF Symbol | Pourquoi |
|---|---|---|
| `.uploaded` | `checkmark.icloud` | glyphe rempli, lisible à 10 pt, dit « présent sur le serveur » sans évoquer une action |
| `.localOnly` (galerie locale, hors timeline) | `icloud.slash` | seul cas où « la copie serveur n'est pas la nôtre » est vrai et vérifiable |
| inconnu du ledger sur une tuile de timeline | **rien** | le ledger ne prouve pas l'absence, donc on n'affiche pas l'absence |
| INTERDIT | `icloud.slash` **sur une tuile de timeline** | **faux sémantiquement** : la timeline ne sert que des UUID serveur (`TimelineViewModel.swift:161`), donc un asset uploadé depuis un autre appareil serait marqué « pas sur le serveur » — le mensonge que la spec écarte en renvoyant `nil` |
| INTERDIT | `arrow.clockwise.icloud`, `icloud.and.arrow.up`, `exclamationmark.icloud`, `xmark.icloud`, `wifi.slash` | faux sens : les deux premiers impliquent une **activité** (le badge est un constat au repos, pas un transfert) ; les deux suivants un **échec** (le ledger n'a aucun signal d'échec par asset — absence ≠ erreur) ; le dernier se confond avec `offlineBadge`, qui répond à une autre question (cache disque) |

**Lisibilité à petite taille** — la capsule fait 16–20 pt de haut avec un glyphe de 10 pt ; les règles tenues par les badges
voisins s'appliquent, aucune n'est négociable.

- Glyphe **rempli** uniquement (`checkmark.icloud`, pas `icloud`) : les variantes filaires disparaissent sous 12 pt, et un
  trait de 1 pt sur `.ultraThinMaterial` clair devient gris. D'où `icloud.slash`, qui empile un nuage et une barre,
  réservé aux seuls cas où sa sémantique est vraie.
- Contraste emprunté à `badge(_:)` (`.white` + matériau + bord 0,25) : aucune couleur d'état n'est ajoutée —
  `immichSuccess` / `immichError` sont interdits ici, le badge dit *où* est le fichier, pas si une action a réussi, et une
  pastille verte sur chaque tuile ferait un sapin de Noël.
- Badge **icône seule**, donc plus étroit que `360°` : il ne pousse jamais le badge de pile hors de la tuile, même sur les
  tuiles les plus étroites.

**Cohabitation dans la pile** — cloud n'apparaît que si le réglage est activé, offline que si l'asset est épinglé, 360° que
sur les sphériques, stack que sur un cover : les quatre capsules se superposent rarement. Le `VStack` à `4` pt est déjà
borné par la tuile ; cloud y entre **en troisième**, donc les deux badges larges (360° et `+N`) restent aux extrémités et la
lecture descend sans saut de largeur.

**Coût par tuile** — un badge ne fait rien : une lecture d'environnement (`cloudStatus`, déjà injectée à la racine,
`RootView.swift:173`), un `status(forServerAssetID:)` qui est un `Set<String>.contains` en `O(1)`, et un
`Image(systemName:)` dans la capsule existante. Rien d'autre : aucun appel réseau (la cellule ne connaît pas le client
HTTP), aucun checksum, aucune lecture d'original, aucun accès disque (le ledger est en mémoire), aucune mise en forme de
chaîne ou de date. Les ensembles de l'index ne sont reconstruits que sur `onLedgerChange` (fin de `save()` ou
réconciliation), jamais par tuile.

## Interactions

| Geste | Effet |
|---|---|
| Bascule `syncBadgeToggle` → ON | `settings.showSyncBadge = true`, persisté sous `photoBackupShowSyncBadge` ; l'index passe `isEnabled = true` (via `vm.syncBadgeIndex()`) et les tuiles déjà rendues affichent leur badge |
| Bascule → OFF | `isEnabled = false` ; toutes les réponses deviennent `nil`, **aucun** badge n'est dessiné (feature muette) ; l'index reste alimenté pour ne pas recharger au rallumage |
| Tap / long press sur une tuile portant le badge | Rien de spécifique : le geste appartient à la tuile (ouverture, sélection, menu contextuel Favorite / Delete, inchangé). Le badge n'est pas un bouton, n'intercepte aucun tap |
| Fin de run de backup ou de réconciliation | `onLedgerChange` → `refresh(ledger:)` sur le main actor ; les tuiles se remettent à jour d'elles-mêmes, sans geste |

Le badge est **non interactif** : pas de `contentShape`, pas d'`onTapGesture`, pas de cible tactile à lui garantir.

## Liquid Glass / matériaux

Aucun `glassEffect` n'est ajouté, ni sur la tuile ni dans l'écran Backup. Le badge cloud réutilise **exactement** la
capsule existante `badge(_:)` : elle est déjà le traitement uniforme de tous les badges de la cellule, et le verre iOS 26
est réservé dans ce dépôt aux surfaces **flottantes** (barres, bandeaux, îlot Live Activity), pas aux micro-badges d'une
grille. Un `Glass.regular` ici créerait un deuxième langage visuel dans le même coin de tuile, pour un gain nul à 16 pt.

## Accessibilité

- **Identifiants** (sur l'élément porteur, jamais sur un conteneur) : `syncBadgeToggle` sur le `Toggle` ;
  `cloudBackedUpBadge` et `cloudLocalOnlyBadge` sur **le badge lui-même**, après `.accessibilityElement(children: .ignore)`
  — un identifiant sur le `VStack` `topLeadingBadges` écraserait ceux de `offlineBadge` et `stackBadge` (piège documenté
  l.185-187, mesuré ailleurs sur `languageRelaunchToast`).
- **VoiceOver** : le badge est **un seul élément** (`children: .ignore`) dont le label vient de `status.localizedLabel` —
  « Saved on server » ou « Only on this device ». Jamais deux lectures glyphe + texte, jamais le nom du SF Symbol à la
  place du sens. Réglage éteint ou état inconnu : l'élément **n'existe pas** dans l'arbre, rien n'est annoncé.
- **Cibles ≥ 44 pt** : la bascule est une ligne de `Form` (cible système pleine largeur) ; le badge n'étant pas interactif,
  il n'a pas de cible à atteindre — d'où le refus de le rendre cliquable.
- **Dynamic Type** : le glyphe reste à `10 pt` fixes (micro-glyphe dérogatoire, comme `offlineBadge` et le glyphe de pile) :
  il n'agrandit pas, mais **aucune information n'est perdue**, le sens complet étant porté par `accessibilityLabel`. Aucun
  `frame(height:)` figé n'est ajouté. **Reduce Motion** : rien à neutraliser, le badge n'a aucune animation propre.
- **Chaînes** : clés anglaises dans le catalogue — « Show backup status on thumbnails », « Saved on server », « Only on this
  device » (l'écran Backup code déjà en clés anglaises, `fr` renseigné dans `Resources/Localizable.xcstrings`).

## Animations

**Aucune, et c'est le choix** : le badge apparaît et disparaît quand le ledger change, c'est-à-dire rarement, et il peut le
faire sur des centaines de tuiles à la fois — une animation par tuile serait un coût de rendu pour aucune information.
Bascule du réglage et nouvel état après un run sont donc des ré-renders secs, sans `withAnimation`. Si une transition
devenait exigée, ce serait `.transition(.opacity)` avec `PVMotion.standard`, et rien d'autre (neutralisé par Reduce
Motion). Sont explicitement **écartés** : `.symbolEffect(.bounce)` (réservé à la pastille de sélection, qui répond à un
geste), `.contentTransition(.symbolEffect(.replace))` (le badge ne change pas d'icône sous les yeux de l'utilisateur : il
apparaît ou disparaît), tout `matchedGeometryEffect`, tout `glassEffectID`. Un badge qui pulse attirerait l'œil sur mille
tuiles pour dire une chose statique.

## Fichiers touchés

- NEW `Sources/Core/Types/CloudBackupStatus.swift` — l'énum, `systemImage`, `localizedLabel` ; NEW
  `Sources/Services/CloudBackupStatusIndex.swift` — l'index observable, `O(1)` par tuile.
- EDIT `Sources/Features/Timeline/AssetThumbnailCell.swift` — `@Environment(CloudBackupStatusIndex.self)`, `cloudBadge`,
  insertion dans `topLeadingBadges` entre `offlineBadge` et le badge de pile.
- EDIT `Sources/Features/Upload/UploadViewModel.swift` — `showSyncBadge` dans `BackupSettingsStore`, `syncBadgeIndex()`,
  `Toggle` `syncBadgeToggle` dans la section « Auto backup ».
- EDIT `Sources/Core/Protocols/BackupLedgerStoring.swift` + `Sources/Services/BackupLedger.swift` (`serverAssetId` v3 et
  les deux lectures d'ensemble) + `Sources/Services/BackupEngine.swift` (alimentation du champ, `onLedgerChange`).
- EDIT `Sources/DependencyContainer.swift` + `Sources/RootView.swift` — construction, câblage du rafraîchissement,
  injection d'environnement.
- EDIT `Resources/Localizable.xcstrings` — trois clés, `fr` renseigné ; NEW `Tests/CloudBackupStatusIndexTests.swift` —
  états et cas « inconnu du ledger ».

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Poser l'`accessibilityIdentifier` sur le `VStack` `topLeadingBadges`** : il écrase les identifiants des enfants et
   `stackBadge` / `offlineBadge` disparaissent de l'arbre (documenté l.185-187, mesuré ailleurs sur `languageRelaunchToast`).
2. **Afficher `icloud.slash` sur une tuile de timeline** : la timeline ne sert que des UUID serveur, le badge affirmerait
   « pas sur le serveur » pour un asset uploadé depuis un autre appareil — le mensonge exact que la spec refuse (`nil`).
3. **Faire venir le statut d'ailleurs que de l'index** : appeler `bulkUploadCheck` (ou le client HTTP) depuis la cellule
   est impossible sans checksum — le recalcul exigerait de re-télécharger chaque original, le coût même que le ledger
   existe pour éviter ; et passer l'index en **paramètre de vue** serait oublié à l'une des sept surfaces qui instancient
   la cellule (même raison qu'en l.19-21).
4. **Ajouter une animation ou un `symbolEffect` par tuile**, ou **teinter le badge avec `immichSuccess` / `immichError`** :
   coût de rendu sur des centaines de cellules pour une information statique, et une pastille verte sur chaque tuile
   rendrait la grille illisible.
5. **Écrire un littéral français dans la vue**, saisir l'icône en dur à deux endroits (`systemImage` vit sur
   `CloudBackupStatus`), ou **déclarer un `NavigationStack` dans `BackupSettingsView`** / autour de la grille — l'écran est
   poussé par le hub « Me », qui porte déjà le sien (deux barres).
