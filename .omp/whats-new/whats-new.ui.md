# Task: whats-new — UI Brief

> Compagnon de `.omp/whats-new/whats-new.specs.md` (écrit le 2026-09-15, écart G23). Ne pas dupliquer la spec : ce
> document ne décrit que la **surface** — placement, hiérarchie de vues, gestes, états, tokens. Quatre surfaces : la
> **feuille** « What's New » automatique, la **même** vue rouverte depuis About, l'écran **Licenses**, la ligne
> **About** du hub « Me ».

## Design Philosophy

Un écran de nouveautés est une **annonce**, pas un réglage : il se lit une fois, en trente secondes, et ne revient
jamais. La surface est donc volontairement pauvre — une carte par nouveauté, empilées, sans grille, sans badge, sans
action secondaire — et **sans aucun contrôle de préférence** : rien ici ne décide *si* l'écran s'affiche, la release
de contenu l'ayant tranché en amont. La seule action est la sortie (« Done »), parce qu'un écran qui s'auto-présente
doit offrir sa sortie de façon évidente.

Deuxième principe : **une seule vue, deux points d'entrée**. La feuille automatique et l'ouverture à la demande
partagent la même hiérarchie de cartes ; seule la barre d'outils diffère, le bouton « Done » n'existant qu'en feuille.

Troisième principe : **rien ne vient du réseau**. Le catalogue est embarqué dans l'app et la seule chose persistée
est la release vue : hors-ligne, l'écran est complet. Un `ProgressView` ici signalerait une dérive vers l'approche
serveur rejetée par la spec.

## Placement dans la navigation

- **Feuille automatique** : présentée par `AuthenticatedRoot` (`Sources/RootView.swift`), seul présentateur stable du
  dépôt — le patron déjà suivi par `.sheet(isPresented: $showProfile)` (`:233-235`), qui enveloppe la vue dans son
  propre `NavigationStack` comme il le fait pour `ProfileView`. Déclencheur : `.task(id: auth.userId)`, après le
  premier affichage authentifié ; changer de compte refait l'évaluation, ce qui est voulu — la release vue est un
  état de compte, pas de processus.
- **À la demande** : `ProfileView` (hub « Me ») → ligne **About** (section About, insérée **après** Administration et
  **avant** Security : le bloc regarde l'app, pas le compte) → **AboutView** → ligne **What's New** →
  `WhatsNewView` **poussée**, donc sans bouton « Done » et avec le retour natif.
- **Licenses** : `AboutView` → ligne **Licenses** → `LicensesView` poussée.
- Les trois vues **ne déclarent aucun `NavigationStack`** : poussées, `ProfileView` en porte un ; en feuille,
  l'enveloppe vient du présentateur. Un stack déclaré ici produirait deux barres de navigation — piège relevé à la
  livraison de `LanguageSettingsView` (mémoire `3bfec9fe-f46d-4395-83de-d4ad3fecdedd`).

## Layout

```
AuthenticatedRoot                                     (Sources/RootView.swift)
└── .sheet(isPresented: $showWhatsNew, onDismiss: { whatsNew.markSeen() })
    └── NavigationStack                               ← fourni par le présentateur, pas par la vue
        └── WhatsNewView(vm:, onDone:)
            ├── ToolbarItem(.confirmationAction)  Button « Done »        (feuille seulement)
            └── ScrollView
                └── LazyVStack(spacing: PVSpacing.s24)
                    ├── card(for: FeatureHighlight)    ← une par nouveauté, dans l'ordre du catalogue
                    │   ├── Tile  .frame(height: 256)
                    │   │        ├── Image(highlight.imageName)      si l'asset existe
                    │   │        └── sinon Image(systemName: highlight.systemImage)
                    │   │                  .font(.system(size: 44))   sur Color.bgSecondary
                    │   │        .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(bordure 0,5)
                    │   ├── Text(highlight.title)      .font(.pvHeadline)  Color.textPrimaryPV
                    │   └── Text(highlight.body)       .font(.pvSubhead)   Color.textSecondaryPV
                    └── (catalogue vide) ContentUnavailableView  ← voir « rien de neuf »

ProfileView                                           (hub « Me », Sources/Features/Profile/ProfileView.swift)
└── Form   … Account, Servers, Server, storage, General, Management, Administration …
    ├── Section header: Text("About")
    │   └── NavigationLink → AboutView(whatsNew:)          id « aboutRow »
    │       Label("About", systemImage: "info.circle")
    └── … Security, Log Out …

AboutView / LicensesView                              (toutes deux poussées, sans NavigationStack)
└── List
    ├── LabeledContent("Version", value: "0.1.0 (12)")      id « aboutVersionValue »
    ├── NavigationLink → WhatsNewView(vm:)                  id « aboutWhatsNewRow »
    │   Label("What's New", systemImage: "sparkles")
    └── NavigationLink → LicensesView()                     id « aboutLicensesRow »
        │       Label("Licenses", systemImage: "doc.text")  ← contenu de la destination
        └── [LicensesView] Section par licence, ordre alphabétique sur `name`
            └── DisclosureGroup(isExpanded: binding(for: license.id))
                ├── label: Text(license.name)                   id « licenseRow_<id> »
                └── content: Text(corps de licence).font(.footnote.monospaced())
                        .textSelection(.enabled)                ← texte long, copie possible
                        └── (échec) Text("License text unavailable")  id « licenseMissingRow »
```

- **Titres** `What's New`, `About`, `Licenses`, tous en `.navigationBarTitleDisplayMode(.inline)`.
- **Fond** `Color.bgPrimary` sur `WhatsNewView` ; la tuile de repli lit `Color.bgSecondary`. Aucun blanc littéral.
- **Ordre des cartes** : celui de `FeatureHighlightCatalog.all`, jamais retrié dans la vue (la feuille et l'ouverture
  à la demande montreraient deux ordres).

## Composants

Réutiliser, ne pas créer — la spec ferme explicitement la porte à un composant de carte neuf :

| Besoin | Composant existant |
|---|---|
| Tuile visuelle de nouveauté (repli) | `Image(systemName:)` sur `Color.bgSecondary` + `RoundedRectangle(cornerRadius: 18)` — aucune vue neuve |
| Titre / corps de carte | `Text` + `Font.pvHeadline` / `Font.pvSubhead` |
| Bordure de tuile | `Color.separatorPV` à 0,5 pt, comme `_HighlightCard` |
| Ligne du hub et de About | `NavigationLink { } label: { Label(…) }` dans un `Form`/`List` — motif de Language et Administration |
| Version de l'app | `LabeledContent("Version", value:)` — aucune cellule maison |
| Corps de licence | `Text` en `.footnote.monospaced()` + `.textSelection(.enabled)` dans un `DisclosureGroup` |
| État « rien de neuf » | `ContentUnavailableView` (déjà utilisé dans le dépôt) |

Aucun token neuf, aucun composant neuf, aucun `glassEffect`. Si une carte portait un jour une capture, c'est
`Image(highlight.imageName)` qui la porterait (le champ existe, nil aujourd'hui) ; le repli par SF Symbol est le
comportement prévu par l'upstream (`FeatureMessagePlaceholder`).

## Interactions

| Geste | Effet |
|---|---|
| Tap « Done » (feuille) | `onDone?()` → `showWhatsNew = false` ; `markSeen()` s'exécute en `onDismiss` |
| Balayage vers le bas (feuille) | Ferme la feuille ; `onDismiss` exécute aussi `markSeen()` — même sortie, deux gestes |
| Tap « What's New » dans About | Pousse `WhatsNewView(vm:)` **sans** `onDone` : pas de bouton, retour natif |
| Tap « Licenses » dans About | Pousse `LicensesView()` |
| Tap sur une ligne de licence | `DisclosureGroup` déplie/replie ; l'état (`Set<String>`) est local, non persisté |
| Sélection de texte dans une licence | `.textSelection(.enabled)` → copie native du texte long |
| Relance après une série vue | Aucune feuille : `shouldPresentAutomatically()` est faux, rien n'est remis à `true` |

## Liquid Glass / matériaux

Pas de `glassEffect` sur ces trois écrans. Précédent du dépôt : le verre est réservé aux surfaces **flottantes**
(barres de recherche, bandeaux, îlot Live Activity) — `StackView`, `OfflineAssetsView` et `SyncStatusView` n'en
utilisent pas, et les écrans poussés du hub « Me » partagent ce choix. Le seul matériau non opaque de la fiche est
celui de la **feuille**, fourni par le système ; la vue n'ajoute rien, les tuiles de repli et les listes se
contentant de `bgSecondary` / `separatorPV`.

## Accessibilité

- **Identifiants** — posés sur les éléments interactifs, jamais sur un conteneur qui en contient (piège mesuré sur
  `languageRelaunchToast`, où l'identifiant du conteneur écrasait celui du bouton) : `aboutRow` (ligne du hub),
  `aboutWhatsNewRow`, `aboutLicensesRow`, `licenseMissingRow` — les quatre que la spec épingle —, plus
  `aboutVersionValue`, `whatsNewDoneButton`, `whatsNewCard_<highlight.id>` (sur la carte, qui n'a **aucun**
  descendant interactif) et `licenseRow_<license.id>` (sur le `DisclosureGroup`, qui est le contrôle).
- **VoiceOver** : chaque carte est un seul élément (`accessibilityElement(children: .combine)`) dont le label
  enchaîne titre puis corps — jamais deux lectures séparées. Le repli iconographique est décoratif
  (`accessibilityHidden(true)`) : la carte se lit par son titre, pas par son SF Symbol.
- **Dynamic Type** : aucune hauteur de texte figée ; les 256 pt sont une hauteur **d'image**, pas de contenu
  textuel, et titre/corps passent à la ligne librement. Les tailles d'accessibilité allongent la carte, jamais ne la
  rognent.
- **Cibles ≥ 44 pt** : lignes de `Form`/`List` (hauteur native) et `DisclosureGroup` en pleine largeur.
- **Reduce Motion** : rien à neutraliser — aucune animation propre ; l'ouverture de la feuille et le dépliage d'une
  licence sont des animations système.
- **Chaînes** : clés anglaises (`What's New`, `About`, `Licenses`, `Done`, `Version`, `License text unavailable`,
  plus les cinq paires titre/corps du catalogue). Aucun littéral français dans une vue.

## Animations

Rien n'est animé par la fiche — choix, pas oubli : un écran d'annonce lu une fois ne gagne rien à bouger ; aucun
`matchedGeometryEffect`, aucun `glassEffectID`, aucun `contentTransition` n'est introduit.

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Présentation / fermeture de la feuille | système (`sheet`) | système |
| Dépliage d'une licence | `DisclosureGroup` (animation système) | système |

## Fichiers touchés

- NEW `Sources/Features/WhatsNew/FeatureHighlight.swift` — `FeatureHighlight`, `FeatureHighlightCatalog` (release de
  contenu `"3.0.0"`, cinq entrées visibles sur iOS), `isNewer(_:than:)` numérique.
- NEW `Sources/Features/WhatsNew/WhatsNewStore.swift` — `seenReleaseKey`, `seenRelease`, `shouldShow`, `markSeen()`.
- NEW `Sources/Features/WhatsNew/WhatsNewViewModel.swift` — `@MainActor @Observable`, aucune copie d'état.
- NEW `Sources/Features/WhatsNew/WhatsNewView.swift` — les cartes, la tuile de repli, `onDone` optionnel.
- NEW `Sources/Features/About/ThirdPartyLicense.swift` — `ThirdPartyLicense`, `licenseText(for:)`.
- NEW `Sources/Features/About/LicensesView.swift` — `List` + `DisclosureGroup`, `.textSelection(.enabled)`.
- NEW `Sources/Features/About/AboutView.swift` — version, deux `NavigationLink`.
- NEW `Resources/Acknowledgements/socket.io-client-swift.txt` (+ chaque dépendance transitive résolue).
- NEW `Tests/WhatsNewViewModelTests.swift`, NEW `Tests/ThirdPartyLicenseTests.swift`.
- EDIT `project.yml` — `- path: Resources/Acknowledgements` dans les ressources de la cible app, puis
  `xcodegen generate` (sans quoi le dossier n'est pas copié et `licenseText(for:)` échoue).
- EDIT `Sources/DependencyContainer.swift` — `whatsNewStore` + `makeWhatsNewViewModel()`.
- EDIT `Sources/RootView.swift` — `@State whatsNew`, `@State showWhatsNew`, la feuille, `.task(id: auth.userId)`, et
  le passage `whatsNew:` à `ProfileView`.
- EDIT `Sources/Features/Profile/ProfileView.swift` — `@State var whatsNew` + section About (`aboutRow`).
- EDIT `Sources/Features/Auth/AuthViewModel.swift` — `applySession` écrit la release vue.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Faire venir les notes du serveur.** `grep -c featureMessage /tmp/immich-openapi-main.json` → `0` : aucun
   endpoint, aucune config téléchargée, et l'upstream tient lui-même la série en `const`. Un écran qui attend une
   réponse réseau afficherait un vide hors-ligne là où la fiche livre un catalogue embarqué.
2. **Indexer la présentation sur `MARKETING_VERSION`.** Deux builds locaux successifs portent la même version
   (`project.yml:15`) et un correctif re-présenterait la feuille à chaque publication — ce que le commentaire
   upstream interdit (« never from the running app version »).
3. **Comparer les releases en lexicographique.** `"3.10.0" < "3.9.0"` en comparaison de chaînes : la dixième mineure
   ne présenterait jamais ses nouveautés. D'où `isNewer` composant par composant.
4. **Oublier `markSeen()` en `onDismiss`.** Un balayage vers le bas est un « vu » ; sans l'appel, la feuille
   reviendrait à chaque lancement. `onDismiss` couvre les deux sorties (Done et balayage).
5. **Déclarer un `NavigationStack` dans une vue poussée.** `ProfileView` en porte un, la feuille est enveloppée par
   `AuthenticatedRoot` ; piège déjà relevé sur `LanguageSettingsView`.
6. **Poser un `accessibilityIdentifier` sur un conteneur.** Mesuré sur `languageRelaunchToast` : l'identifiant d'un
   `GlassEffectContainer` a rendu son bouton introuvable sous son propre identifiant. Ici les identifiants de carte
   vont sur la carte (sans descendant interactif), ceux de licence sur le `DisclosureGroup`.
7. **Recopier le texte d'une licence en Swift.** Le fichier doit être la copie exacte du paquet résolu ; un texte
   retapé dérive à la première mise à jour de dépendance, et une ressource manquante doit **se voir**
   (`licenseMissingRow`), pas disparaître silencieusement de la liste.
8. **Annoncer une nouveauté non livrée.** Une carte décrit une fonction qui existe ; `ocr` n'est livrée que si
   `SpecOcrText` l'est. Retirer l'entrée du catalogue (il tolère d'être plus court) plutôt que la garder « pour plus
   tard » : une carte annonçant un écran absent est un mensonge produit.
9. **Inventer un token ou un composant de carte.** `PVStatusBadge` et les tokens existants suffisent ; aucun
   `Colors`/`PVSpacing`/`PVRadius` neuf n'est introduit, et aucun littéral français ne s'écrit dans la vue (la clé du
   catalogue est la chaîne anglaise).
10. **Oublier la déclaration de ressource dans `project.yml`.** XcodeGen énumère les ressources une par une
    (`:24-34`) : un dossier neuf n'est copié qu'après l'EDIT. C'est la panne silencieuse réelle de cette fiche, et le
    seul test qui l'attrape est le test de packaging.
