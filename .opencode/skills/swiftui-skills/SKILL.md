---
name: swiftui-elegant-design
description: Concevoir des interfaces SwiftUI élégantes, sobres et professionnelles, dans l'esprit des standards Apple (Human Interface Guidelines, Liquid Glass / iOS 18+). À utiliser dès qu'on construit, redesigne ou revoit une vue SwiftUI, un écran d'app iOS/macOS/visionOS, un composant réutilisable, ou qu'on demande des conseils de typographie, couleurs, spacing, animations ou accessibilité pour du SwiftUI. Déclencheurs : "interface SwiftUI", "écran iOS", "design app Apple", "améliore ce composant SwiftUI", "fais-moi une vue élégante", ou tout code .swift utilisant SwiftUI.
---

# Design SwiftUI élégant et professionnel

Ce skill donne les principes, valeurs de référence et patterns de code pour produire des interfaces SwiftUI qui ont l'air pensées par une équipe de design Apple sérieuse — pas des interfaces "template ChatGPT" avec des dégradés violets partout et des coins arrondis au hasard.

Philosophie : **sobriété, hiérarchie claire, matériaux natifs, mouvement discret**. Une bonne interface SwiftUI ne se remarque pas — elle se sent juste "juste".

## 1. Avant de coder : intention

Toujours se demander :
- Quelle est l'action principale de cet écran ? Elle doit être visuellement évidente en < 1 seconde.
- Quelle hiérarchie d'information ? (titre > contenu > actions secondaires > métadonnées)
- Plateforme cible : iOS, iPadOS, macOS, visionOS ? Les conventions diffèrent (voir §8).
- Light + Dark mode dès le départ, jamais en rattrapage.

Ne pas réinventer des composants qui existent déjà nativement (List, Form, NavigationStack, TabView, sheet, etc.). Un composant custom se justifie seulement si Apple n'offre rien d'équivalent.

## 2. Typographie

- Utiliser systématiquement les **Dynamic Type styles** natifs, jamais de tailles de police en dur.

```swift
Text("Titre de section")
    .font(.title2.weight(.semibold))

Text("Corps de texte principal")
    .font(.body)

Text("Métadonnée, légende")
    .font(.footnote)
    .foregroundStyle(.secondary)
```

- Échelle à utiliser : `.largeTitle` (écran d'accueil / hero), `.title`/`.title2`/`.title3` (sections), `.headline` (labels forts, cellules importantes), `.body` (contenu), `.callout`, `.subheadline`, `.footnote`, `.caption`/`.caption2` (métadonnées).
- Poids : ne pas abuser de `.bold`. Un `.medium` ou `.semibold` suffit presque toujours pour créer de la hiérarchie sans alourdir visuellement.
- Toujours laisser `.dynamicTypeSize` s'appliquer (accessibilité) sauf cas très spécifique (jauge, badge fixe).
- Éviter les polices custom sauf si la marque l'exige vraiment — San Francisco est optimisée pour la lisibilité à toutes les tailles et supporte nativement le Dynamic Type.

## 3. Couleur et matériaux

### Couleurs sémantiques, jamais de hex en dur
```swift
// ✅ Bon
.foregroundStyle(.primary)
.foregroundStyle(.secondary)
Color.accentColor
Color(.systemBackground)
Color(.secondarySystemBackground)

// ❌ À éviter
.foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
```

- Une seule couleur d'accent (`accentColor` défini dans Assets), utilisée avec parcimonie : CTA principal, sélection, liens. Le reste de l'interface reste en gris neutres système (`.primary`, `.secondary`, `.tertiary`, `.quaternary`).
- Utiliser les **Asset Colors** avec variantes light/dark définies dans le Asset Catalog plutôt que des `if colorScheme == .dark` disséminés dans le code.

### Matériaux (glass / vibrancy)
Depuis iOS 18/26 (Liquid Glass), privilégier les matériaux natifs pour les surfaces flottantes (barres, panneaux, cartes superposées) :

```swift
.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
.background(.regularMaterial)
```

- `.ultraThinMaterial` : overlays légers, barres flottantes
- `.thinMaterial` / `.regularMaterial` : panneaux, feuilles modales secondaires
- `.thickMaterial` : besoin de fort contraste avec le fond
- Ne jamais simuler un flou avec une couleur semi-transparente fixe — utiliser les vrais matériaux qui s'adaptent au fond et au mode clair/sombre.

### Ombres
Discrètes, jamais dures :
```swift
.shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
```
Une seule ombre douce vaut mieux que plusieurs ombres empilées.

## 4. Espacement et layout

- Grille de base **8pt** (multiples de 4 pour les ajustements fins) : 4, 8, 12, 16, 20, 24, 32, 40.
- Marges d'écran standard : 16pt sur iPhone, 20–24pt sur iPad.
- Ne jamais laisser SwiftUI "improviser" l'espacement par défaut sur des layouts denses — être explicite :

```swift
VStack(alignment: .leading, spacing: 16) {
    Text("Titre")
        .font(.title2.weight(.semibold))
    Text("Description qui explique le contexte de façon concise.")
        .font(.body)
        .foregroundStyle(.secondary)
}
.padding(20)
```

- Alignement cohérent : dans une `VStack`, préférer `.leading` pour du contenu textuel occidental (lecture naturelle), `.center` seulement pour des états vides, hero sections, ou call-to-action isolés.
- Coins arrondis cohérents dans toute l'app : définir 2-3 rayons standards (ex : 12 pour petits éléments, 16-20 pour cartes, `.continuous` toujours) :

```swift
RoundedRectangle(cornerRadius: 16, style: .continuous)
```

- `.continuous` (superellipse) plutôt que `.circular` : c'est la forme des coins iOS natifs, plus douce visuellement.

## 5. Composants natifs à privilégier

| Besoin | Composant |
|---|---|
| Liste de contenu | `List` avec `.listStyle(.insetGrouped)` ou `.plain` selon densité |
| Formulaire | `Form` |
| Navigation hiérarchique | `NavigationStack` + `NavigationLink` |
| Onglets | `TabView` (style `.sidebarAdaptable` sur iPad/macOS si pertinent) |
| Action contextuelle | `.contextMenu`, `swipeActions` |
| Sélection multiple | `.selection` binding sur `List` |
| Feuille modale légère | `.sheet` avec `.presentationDetents([.medium, .large])` |
| Confirmation destructive | `.confirmationDialog` (jamais une alert custom) |
| Recherche | `.searchable` |

Éviter de recréer une TabBar, une NavigationBar ou un sheet à la main avec des ZStack — cela casse les comportements d'accessibilité, de safe area et les animations système gratuites.

## 6. Boutons et actions

- Un seul bouton "fort" par écran (`.buttonStyle(.borderedProminent)`), le reste en `.bordered` ou `.plain` :

```swift
Button("Continuer") { }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)

Button("Annuler") { }
    .buttonStyle(.bordered)
```

- Icônes : **SF Symbols exclusivement**, jamais d'icônes custom pour des actions système standards (partage, suppression, favoris, retour). Utiliser les variantes de rendu adaptées :

```swift
Image(systemName: "heart.fill")
    .symbolRenderingMode(.hierarchical)
```

- Labels d'actions clairs et courts, verbe à l'infinitif ("Enregistrer", pas "Enregistrement").

## 7. Mouvement et animation

Le mouvement doit avoir une fonction (feedback, continuité spatiale), jamais être décoratif seul.

```swift
withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
    isExpanded.toggle()
}

// Transitions de contenu
.contentTransition(.numericText())     // pour des chiffres qui changent
.contentTransition(.symbolEffect(.replace)) // pour un SF Symbol qui change d'état
```

- Préférer `.spring()` à `.easeInOut` : c'est le ressenti natif iOS.
- Durées courtes : 0.2–0.4s pour la plupart des transitions d'UI. Au-delà, ça ralentit l'usage perçu.
- Utiliser `matchedGeometryEffect` pour les transitions d'un élément qui "devient" un autre (carte → détail plein écran) plutôt qu'un simple fade.
- Ne jamais animer plus de 2-3 propriétés à la fois sur une même interaction.

## 8. Adaptation multi-plateforme

- **iOS** : marges 16pt, TabView en bas, safe area respectée par défaut (ne pas ignorer avec `.ignoresSafeArea()` sauf fond plein écran volontaire).
- **iPadOS** : exploiter l'espace avec `NavigationSplitView` plutôt qu'empiler des NavigationStack ; envisager du multi-colonnes.
- **macOS** : marges plus généreuses, `.buttonStyle(.bordered)` par défaut moins "touch", raccourcis clavier (`.keyboardShortcut`) sur les actions principales, menus contextuels riches.
- Ne pas porter un design iPhone tel quel sur iPad/Mac — c'est le signe #1 d'une app qui "sent" l'amateur.

## 9. Accessibilité (non négociable pour du "professionnel")

```swift
Image(systemName: "trash")
    .accessibilityLabel("Supprimer l'élément")

VStack { ... }
    .accessibilityElement(children: .combine)
```

- Contraste suffisant même en couleurs custom (viser AA minimum).
- Toucher cible ≥ 44×44pt pour tout élément interactif.
- Tester avec Dynamic Type en taille XL et VoiceOver activé au moins une fois avant de considérer un écran "fini".

## 10. Anti-patterns à éviter systématiquement

- Dégradés multicolores agressifs sur les fonds d'écran principaux.
- Coins arrondis incohérents (8 ici, 24 là, sans système).
- Polices en taille fixe qui cassent avec Dynamic Type.
- Boutons "prominent" multiples sur un même écran (dilue la hiérarchie).
- Recréer des composants système (nav bar, tab bar, alert) à la main.
- Ombres multiples empilées ou trop marquées (effet "sticker").
- Ignorer le mode sombre jusqu'à la fin du projet.
- Animations décoratives sans lien avec l'action de l'utilisateur.

## 11. Exemple complet — carte de contenu élégante

```swift
struct ArticleCard: View {
    let title: String
    let subtitle: String
    let imageName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
}
```

Ce composant illustre : grille d'espacement 4/12/16, coins `.continuous` cohérents, matériau natif, hiérarchie typographique (`.headline` / `.subheadline` + `.secondary`), ombre douce unique.

## 12. Checklist finale avant de livrer un écran

- [ ] Hiérarchie typographique claire, tailles Dynamic Type natives
- [ ] Une seule couleur d'accent, utilisée avec parcimonie
- [ ] Espacement sur grille 8pt, cohérent avec le reste de l'app
- [ ] Coins arrondis `.continuous` et cohérents
- [ ] Composants natifs privilégiés (pas de réinvention)
- [ ] Un seul CTA fort par écran
- [ ] Dark mode vérifié
- [ ] VoiceOver + Dynamic Type XL testés
- [ ] Animations fonctionnelles, pas décoratives, en `.spring()`
- [ ] Layout adapté à la plateforme cible (iPhone/iPad/Mac)
