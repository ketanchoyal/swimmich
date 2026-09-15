# Task: person-birthday — UI Brief

> Compagnon de `.omp/person-birthday/person-birthday.specs.md` (2026-09-15, écart G15). Ce document ne décrit que la **surface** ; le contrat filaire (deux corps d'écriture, date-seule `YYYY-MM-DD`) appartient à la spec.

## Design Philosophy

La fiche d'une personne est une **carte d'identité**, pas un formulaire : un avatar, deux lignes de texte, quatre pastilles d'action. L'anniversaire y entre par la porte étroite — une **5ᵉ pastille** identique aux autres, une **ligne discrète** dans l'en-tête, rien de plus. Aucune section nouvelle, aucun badge, aucune couleur d'accent : le ton est celui du « N photos » juste au-dessus. La seule surface qui prend de la place est la feuille d'édition, **modale et éphémère** — on y entre par un tap, on en sort par Save ou Cancel, la fiche n'en garde aucune trace visuelle.

Deux principes gouvernent les gestes :

1. **Rien ne s'écrit sans Save.** La feuille ne touche jamais au ViewModel ; elle rend une date au site d'appel, qui appelle `vm.setBirthday`. Cancel ferme et jette le brouillon.
2. **L'absence ne se dessine pas.** Pas de ligne « Birthday: unknown », pas de tiret, pas de placeholder : quand `person.birthDate == nil`, la ligne n'existe pas dans l'arbre de vues.

## Placement dans la navigation

- **Surface** : `PersonDetailView` (`Sources/Features/People/PeopleView.swift:151`, `private struct`), poussée par `PeopleView` (drill-down de « People »).
- **Ancrage** : la rangée d'actions du header (`:182-195`), **après** Hide/Unhide (`:191-193`) et **avant** `mergeMenu` (`:194`). L'ordre des quatre actions existantes (Favorite, Rename, Hide, Merge) ne bouge pas : le cinquième bouton se pose en fin de série de pastilles, le menu de fusion reste le dernier élément — c'est un menu, pas une pastille.
- **Aucun `NavigationStack` ajouté à `PersonDetailView`** : elle hérite de la pile portée par `PeopleView` (`:7-46`). Le seul stack de cette fiche est celui que la **feuille** déclare pour ses boutons de barre — une feuille n'hérite jamais de la pile de la vue poussée.
- **Pas de route, pas d'onglet, pas de ligne d'index** : l'anniversaire ne s'affiche **pas** dans `personRow` (`:117-148`) — la tuile upstream ne le porte pas, et l'index des personnes est un annuaire, pas un agenda.
- La fiche garde son app bar inchangée (`ImmichAppBar`, `.navigationBarTitleDisplayMode(.inline)`).

## Layout

```
PeopleView                                  (porte la NavigationStack)
└── PersonDetailView                        (poussée, private struct)
    └── ScrollView
        └── VStack(spacing: PVSpacing.s16)
            ├── Avatar                          96 × 96, Circle + strokeBorder separatorPV
            ├── VStack(spacing: 2)              ← header d'identité
            │   ├── Text(person.name)          .pvTitle / textPrimaryPV
            │   ├── Text("N photos")           .pvCaption / textSecondaryPV
            │   └── [birthdayLine]             ← NOUVEAU, conditionnel
            │       └── Image + Text(Date)     .pvCaption / textSecondaryPV
            ├── HStack(spacing: PVSpacing.s8)   ← rangée d'actions
            │   ├── star.fill  Favorite      ├── pencil     Rename
            │   ├── eye.slash  Hide/Unhide   ├── calendar   Birthday   ← NOUVEAU (5ᵉ)
            │   └── mergeMenu
            └── (grille d'assets de la personne — inchangée)

BirthdayEditorSheet                         (feuille, .sheet(item: $birthdayPerson))
└── NavigationStack
    └── VStack(spacing: PVSpacing.s16)
        ├── DatePicker("Birthday", $draft, displayedComponents: .date)   style .compact
        ├── Text(futureHint)                    .pvCaption / textSecondaryPV  (si date future)
        └── Button "Clear Birthday"             .bordered, role: .destructive  (si hasExistingBirthday)
    .navigationTitle("Birthday") / .navigationBarTitleDisplayMode(.inline)
    ToolbarItem(.cancellationAction) → "Cancel" (role: .cancel)
    ToolbarItem(.confirmationAction) → "Save"   (désactivé si anniversaire futur)
```

- **La ligne d'anniversaire** reprend exactement la ligne « N photos » (`:178-179`) : `.pvCaption`, `Color.textSecondaryPV`, le `spacing: 2` du `VStack`. Elle est produite par `PersonBirthday.display(person.birthDate)` — **date formatée**, pas un âge calculé : un âge demanderait un recalcul à minuit et une tournure dépendante de la langue, alors que la date formatée suit la locale du `FormatStyle` sans état. `display(_:)` rend `nil` sur `nil` ou sur une chaîne non parseable, donc la ligne est un simple `if let`.
- **Icône** : `Image(systemName: "calendar")` en `.pvCaption`, **`accessibilityHidden(true)`** — VoiceOver doit lire la date, pas le nom du SF Symbol.
- **États** : (a) date présente → la ligne complète ; (b) date absente ou illisible → **rien du tout**, l'en-tête garde sa hauteur d'origine pour les personnes sans date. Aucune chaîne « inconnu », « non renseigné » ou « — ».
- **La pastille** : `actionButton("calendar", .textSecondaryPV, "Birthday")` — glyphe neutre, jamais `.immichPrimary` (réservé à l'état favori actif), cercle 40 × 40 identique aux autres. Budget de largeur vérifié : 5 × 40 pt + 4 × `PVSpacing.s8` = **232 pt** contre 343 pt utiles sur 375 pt (375 − 2 × `PVSpacing.s16`) — la rangée tient, le repli « pictogramme seul » n'est pas nécessaire ; le libellé reste porté par `.accessibilityLabel("Birthday")`.
- **La feuille** : `DatePicker` **`.compact`** (`displayedComponents: .date`), pas `.graphical`. Arbitrage tranché à la mesure : `.graphical` occupe ~320 pt et se fait couper dans un détent `.medium` sur 375 × 667, repoussant « Clear Birthday » hors de l'écran ; `.compact` ouvre le calendrier natif **à la demande**, garde `.presentationDetents([.medium])` et ne déplace rien. Le libellé « Birthday » de la ligne `DatePicker` est le titre de la valeur mise en forme par le système — la vue ne formate rien.
- **Fond** : `Color.bgPrimary` pour la feuille ; ni carte ni `PVFieldSurface` — le picker compact porte son propre relief.

## Composants

Réutiliser, ne pas créer : aucun composant nouveau n'est justifié.

| Besoin | Composant / motif existant |
|---|---|
| Pastille d'action de la fiche | `actionButton(_:_:_:action:)` (`PeopleView.swift:264`), 40 × 40, `.buttonStyle(.plain)` + `.accessibilityLabel` |
| Menu de fusion (voisin) | `mergeMenu` (`:194`), inchangé |
| Feuille modale d'édition | précédent : l'`alert` de renommage (`:243-258`) piloté par `@State`, remplacé ici par un vrai `.sheet(item:)` — un `DatePicker` ne vit pas dans une `alert` |
| Boutons de barre | `ToolbarItem` (.cancellationAction / .confirmationAction) sur le stack de la feuille |
| Erreur non bloquante | `InlineErrorBadge`, via le chemin `vm.errorMessage` déjà branché (`PeopleView:26-29`) |
| Avatar | `AuthenticatedAsyncImage` + `Circle()`, inchangé |

- `BirthdayEditorSheet` vit dans son propre fichier (`Sources/Features/People/BirthdayEditorSheet.swift`) : `PeopleView.swift` fait déjà ~300 lignes et porte trois rôles (index, fiche, marges).
- Signature : `@Binding var draft: Date`, `let hasExistingBirthday: Bool`, `let onSave: (Date?) -> Void`, `@Environment(\.dismiss)`. La feuille ne connaît **ni** `PersonResponseDto` **ni** le format filaire : la conversion `Date → String` se fait au dernier moment, dans le site d'appel (`.map(PersonBirthday.wire(from:))`) — c'est ce qui garde la vue présentationnelle pure.
- **Préremplissage**, sur le patron du bouton Rename (qui pose `renameText = person.name` avant d'ouvrir) : `birthdayDraft = PersonBirthday.date(from: person.birthDate) ?? Date()`. Un `DatePicker` ne sait pas représenter l'absence de date ; le repli est la date du jour, jamais une date sentinelle.

## Interactions

| Geste | Effet |
|---|---|
| Tap « Birthday » | Préremplit `birthdayDraft` depuis `person.birthDate`, pose `birthdayPerson = person` → la feuille s'ouvre |
| Tap sur le champ date | Ouvre le calendrier natif du `DatePicker` compact |
| Tap « Save » | `onSave(draft)` → `vm.setBirthday(person, to: PersonBirthday.wire(from: draft))` — un seul champ sur le fil (`PUT /api/people/{id}`) — puis `dismiss()` |
| Tap « Cancel » | `dismiss()` **seul** : aucune écriture, aucun appel réseau, le brouillon est jeté avec la feuille |
| Tap « Clear Birthday » | `onSave(nil)` → `vm.setBirthday(person, to: nil)` → `clearPersonBirthday(id:)` (corps `{"birthDate": null}`), puis `dismiss()` |
| Date future choisie | « Save » **désactivé** (`.disabled(isFuture)`) et un texte `.pvCaption` explique pourquoi : aucune alerte, aucune erreur serveur |
| Échec réseau | `vm.errorMessage` posé par `apply`, remonté par le chemin existant de `PeopleView` (`:26-29`) — la feuille est déjà fermée, la fiche affiche l'erreur |
| Anniversaire posé ou effacé | `apply` réécrit `people[i]` avec la réponse serveur → la ligne de l'en-tête change **immédiatement**, sans rechargement |

- **Validation « pas de futur »** : `Calendar.current.startOfDay(for:)` comparés, `draft` contre aujourd'hui — jamais une comparaison d'instants, qui rejetterait « aujourd'hui » à cause de l'heure. C'est la seule règle de validation de la fiche ; le bouton désactivé refuse **avant** le réseau (aucun `422`).
- **Pas d'`onSave` partiel** : les deux boutons de la feuille appellent le même `onSave`, avec `draft` ou `nil` — pas de troisième chemin.
- **Pas de confirmation** pour « Clear Birthday » : le geste est réversible en deux taps et vit déjà dans une feuille modale — une `confirmationDialog` empilerait deux surfaces pour rien.
- **Deux feuilles cohabitent** sur la fiche (renommage + anniversaire), via deux `@State` jamais non-nil simultanément. Si SwiftUI présentait la mauvaise, le repli documenté par la spec est un unique `enum PersonEditSheet: Identifiable`.

## Liquid Glass / matériaux

**Pas de `glassEffect` ici.** Le verre du dépôt est réservé aux surfaces **flottantes** (barres de recherche, bandeaux, îlot Live Activity) ; `PersonDetailView` est un écran de contenu poussé, comme `StackView` et `OfflineAssetsView`, qui n'en utilisent pas. La pastille garde son fond `Color.gray.opacity(0.12)` existant (en changer un seul casserait la rangée), l'avatar son `strokeBorder(Color.separatorPV, lineWidth: 1)`, et la feuille le fond système de `.sheet` — aucun matériau ajouté.

## Accessibilité

- **Identifiants** (sur l'élément interactif ou porteur de valeur, **jamais** sur un conteneur) : `personBirthdayAction`, `birthdayPicker`, `birthdaySave`, `birthdayClear`, `personBirthdayValue`.
- **Aucun identifiant pour l'absence** : pas d'anniversaire = pas de vue. Un test d'UI asserte l'**absence** de `personBirthdayValue`, pas la présence d'un « unknown ».
- **Nommage** : aucun `accessibilityIdentifier` n'existe aujourd'hui dans `Sources/Features/People/` (`grep -rn "accessibilityIdentifier" Sources/Features/People/` ne renvoie rien) ; les préfixes `personBirthday*` / `birthday*` sont libres et suivent le style du dépôt (`syncStatus*`, `language*`).
- **VoiceOver** : la pastille lit « Birthday » (label du helper, pas le nom du glyphe) ; la ligne est **un seul élément** (icône masquée) et ne répète pas le mot « Birthday », qui ferait doublon ; « Save » est annoncé désactivé quand la date est future, le texte voisin donnant la raison.
- **Dynamic Type** : aucune hauteur figée — la ligne s'ajoute au `VStack` du header sans écraser le nom. Les libellés d'action n'étant jamais dessinés, la rangée de pastilles 40 pt tient à toutes les tailles.
- **Cibles ≥ 44 pt** : géométrie des pastilles inchangée (la corriger pour un seul bouton décalerait les quatre autres).
- **Chaînes neuves** : `Birthday`, `Save`, `Clear Birthday` — des **clés anglaises**, rien d'écrit à la main dans `Resources/Localizable.xcstrings` (extraction au build, décision i18n du dépôt). Les libellés de date ne sont pas des clés : ils viennent du formateur localisé.

## Animations

| Transition | Implémentation | Reduce Motion |
|---|---|---|
| Ligne qui apparaît (date posée) | `.transition(.opacity)` + `.animation(.default, value: person.birthDate)` | fondu neutralisé |
| Ligne qui disparaît (date effacée) | idem — le même `if let` couvre les deux sens | idem |
| Ouverture / fermeture de la feuille | animation système de `.sheet` | système |
| Sélection d'une date | animation système du `DatePicker` | système |

La ligne d'anniversaire est la **seule** animation introduite : en `opacity` seule, sans `frame` animé ni `matchedGeometryEffect`, pour ne pas faire sauter le header. Aucun `glassEffectID`, aucun morphing — la fiche ne se transforme pas, elle s'enrichit d'une ligne.

## Fichiers touchés

- NEW `Sources/Core/Utilities/PersonBirthday.swift` — `date(from:)`, `wire(from:)`, `display(_:)`.
- NEW `Sources/Features/People/BirthdayEditorSheet.swift` — la feuille décrite ci-dessus.
- EDIT `Sources/Features/People/PeopleView.swift` — 5ᵉ `actionButton` (`:194`), deux `@State` (`birthdayPerson`, `birthdayDraft`, près de `:261-262`), second `.sheet(item:)` (près de `:243-258`), ligne `personBirthdayValue` dans le header (`:173-180`).
- EDIT `Sources/Features/People/PeopleViewModel.swift` — `apply(_:_:)` extrait de `update(_:_:)` (`:114-122`), puis `setBirthday(_:to:)` après `setFeatureFace` (`:110-112`). Les quatre appelants existants gardent leur comportement, **aucune** signature publique ne change.
- EDIT `Sources/Core/Types/DTOs+People.swift` — `PersonBirthdayClearDto` (corps d'effacement, commenté).
- EDIT `Sources/Core/Protocols/ImmichClient.swift` — `clearPersonBirthday(id:)` ; EDIT `Sources/Services/ImmichAPIClient.swift` — l'implémentation HTTP, même chemin `PUT /api/people/{id}`.
- EDIT `Tests/Mocks/MockImmichClient.swift` — `lastClearedPersonBirthdayId` + implémentation : sans elle, le mock ne conforme plus au protocole et **toute la suite cesse de compiler**.
- EDIT `Tests/PeopleViewModelTests.swift`, EDIT `Tests/DTOEncodingTests.swift`, NEW `Tests/PersonBirthdayTests.swift` — étapes 11-13 de la spec.
- `xcodegen generate` — deux sources neuves et un fichier de test : sans régénération, ils ne compilent pas.

## Erreurs à ne pas faire (mesurées dans ce dépôt)

1. **Effacer via `PersonUpdateDto(birthDate: nil)`** : le `encode(to:)` synthétisé encode ses optionnels avec `encodeIfPresent`, donc la clé `birthDate` est **absente** du corps → le serveur ne met rien à jour et l'anniversaire reste en place. L'effacement exige `PersonBirthdayClearDto` (`encodeNil`) : c'est le piège central de la fiche, et la raison d'être du bouton « Clear Birthday ».
2. **Envoyer `""` pour effacer** : `format: date` rejette la chaîne vide ; `null` est la seule valeur d'effacement.
3. **Détourner l'`alert` de renommage en `TextField` de date** : `format: date` transforme la saisie libre en `422` sans validation préalable, et on perd le sélecteur natif — l'apport même de la feature.
4. **Afficher une ligne « inconnu »** : l'en-tête doit garder sa hauteur d'origine ; pas de tiret, pas de placeholder, pas de clé de catalogue pour un vide.
5. **Parser avec `ISO8601DateFormatter`** : il ne parse **pas** `"1990-05-12"`, et le formateur horodaté du dépôt (`JSONCoding.swift:52`) produirait un décalage d'un jour selon le fuseau. `Calendar.current` + `DateComponents` est le seul chemin juste.
6. **Formater la date dans la vue** : une seule mise en forme dans le dépôt pour ce champ (`PersonBirthday.display`), pas de `DateFormatter` local ni de `.formatted` éparpillé dans `PeopleView`.
7. **Ajouter un `NavigationStack` à `PersonDetailView`** : elle est poussée par `PeopleView`, qui en a un ; un second stack produit deux barres de navigation (piège déjà relevé sur `LanguageSettingsView`).
8. **Mettre l'anniversaire dans `personRow`** (`:117-148`) : la tuile de l'index upstream ne le porte pas, et l'ajouter changerait la hauteur de toutes les lignes de l'annuaire.
9. **Écrire un littéral français dans la vue** : la clé du catalogue est la chaîne anglaise.
10. **Poser un `accessibilityIdentifier` sur le `VStack` du header** : il écraserait `personBirthdayValue` (comportement mesuré sur `languageRelaunchToast`, où le bouton devenait introuvable).
11. **Figer `.graphical` ou les détents sans mesurer** : `.graphical` se fait couper dans un détent `.medium` sur 375 × 667 — à revérifier sur iPhone SE avant de figer `.compact` + `.medium`.
12. **Ouvrir la feuille sans préremplir le brouillon** : un `DatePicker` n'a pas d'état « aucune date » ; ne pas lire `person.birthDate` ferait perdre la valeur courante à chaque ouverture, et « Save » la remplacerait silencieusement.
