# Immich for iOS — PRD & Design System
### Réimplémentation native SwiftUI, "Apple-like"

**Version** 0.1 — Draft
**Auteur** Claude (assistant), pour revue produit/design
**Statut** Document de travail

---

## 1. Vision & positionnement

Immich est aujourd'hui une app Flutter cross-platform. L'objectif de ce document est de définir ce que serait une réécriture 100% native SwiftUI : une app qui **ne ressemble pas à un port**, mais qui donne l'impression d'avoir été dessinée par Apple pour Apple — au niveau de Photos.app, mais avec la promesse Immich (self-hosted, contrôle total, pas de cloud propriétaire).

**Principe directeur :** *"Native first, feature parity second."* On préfère une app qui respecte scrupuleusement les conventions iOS (HIG, gestes, typographie, densité d'info) plutôt qu'une app qui réplique pixel pour pixel l'UI actuelle d'Immich.

### Non-objectifs
- Pas de réécriture du backend/serveur Immich (on consomme l'API REST/WebSocket existante).
- Pas de custom design multiplateforme (pas de partage de code UI avec Android).
- Pas d'API design "flat cross-platform" : on assume les composants SwiftUI natifs (NavigationStack, sheets, context menus natifs, etc.).

---

## 2. Personas

| Persona | Besoin principal | Fréquence d'usage |
|---|---|---|
| **Le "libéré du cloud"** | Ex-utilisateur Google Photos/iCloud, veut la même fluidité mais chez lui | Quotidien, backup auto |
| **Le power-user self-host** | Gère plusieurs bibliothèques, plusieurs users, veut du contrôle fin | Hebdomadaire, admin |
| **Le partageur familial** | Albums partagés, souvenirs, ne configure jamais les réglages avancés | Occasionnel, consommation |
| **Le photographe** | RAW, métadonnées EXIF, tri par qualité, export | Ponctuel, sessions longues |

---

## 3. Périmètre fonctionnel (scope)

### 3.1 MVP (Phase 1)
- **Auth & serveurs** : connexion à un serveur Immich (URL + login), gestion multi-comptes, OAuth si configuré côté serveur — onboarding détaillé en §5.10.
- **Timeline principale** : grille photos/vidéos triée par date, sections par mois/année, scrubber de défilement rapide (façon Photos.app).
- **Visionneuse plein écran** : zoom, swipe, vidéo inline, partage système (Share Sheet), infos EXIF.
- **Upload / Backup automatique** : sélection d'albums locaux à synchroniser, upload en arrière-plan (BackgroundTasks), Wi-Fi only en option, indicateur de progression.
- **Albums** : création, ajout/suppression d'assets, albums partagés (lecture).
- **Recherche** : recherche texte (objets, lieux, personnes) via l'API smart search.
- **Favoris / Archive / Corbeille** : actions rapides, swipe actions, undo.
- **Réglages** : gestion serveur, cache local, qualité d'upload, quota.

### 3.2 Phase 2
- **Personnes & visages** : grille de visages détectés, renommage, fusion de personnes.
- **Carte (Map)** : vue carte des photos géolocalisées (MapKit natif, clustering).
- **Souvenirs ("On this day")** : carrousel façon Photos.app "Souvenirs".
- **Partage avancé** : liens publics, albums partagés en écriture, commentaires/réactions.
- **Multi-bibliothèques externes** : montage de librairies en lecture seule côté serveur.

### 3.3 Phase 3 (différenciateurs "Apple-like")
- **Widgets** (WidgetKit) : souvenir du jour, dernier album.
- **Live Activities** : progression d'upload en cours.
- **Partage de focus / Handoff** : reprendre la visionneuse depuis Mac/iPad (Catalyst ou app iPad dédiée).
- **Shortcuts / App Intents** : "Sauvegarder mes photos maintenant", "Ouvrir tel album" via Siri/Raccourcis.
- **iCloud Keychain** pour stocker les credentials serveur.

---

## 4. Architecture de l'information & navigation

On adopte une **TabView à 5 onglets**, cohérente avec Photos.app pour minimiser la charge cognitive :

```
┌─────────────────────────────────────────┐
│                                           │
│              (Contenu)                   │
│                                           │
├─────────┬─────────┬─────────┬─────────┬──┤
│ Photos  │ Albums  │Recherche│ Partagé │Moi│
│ (grid)  │         │         │         │   │
└─────────┴─────────┴─────────┴─────────┴──┘
```

- **Photos** : NavigationStack racine → Timeline → Visionneuse (push, pas de modal pour rester dans les conventions Photos.app).
- **Albums** : liste/grille d'albums → détail album (réutilise le composant Timeline).
- **Recherche** : recherche façon Spotlight, avec suggestions (personnes, lieux, "l'année dernière").
- **Partagé** : albums partagés + activité (nouveaux ajouts, commentaires).
- **Moi (Réglages/Compte)** : profil, serveur, stockage, à propos.

**Navigation pattern** : `NavigationStack` par onglet (pas de `NavigationView` legacy), état de navigation piloté par `NavigationPath` pour permettre le deep-linking (widgets, Shortcuts, notifications push).

---

## 5. Design System

### 5.1 Philosophie

> Le design system n'invente rien : il **réutilise au maximum les composants système** (List, Form, sheets, context menus, SF Symbols) et ne custom que ce qui a une vraie valeur produit (la grille photo, la visionneuse, le scrubber).

### 5.2 Couleurs

**Principe** : on garde les **Semantic Colors** iOS pour tout ce qui est structurel (fonds, textes, séparateurs) afin de garantir Dark Mode et accessibilité gratuitement — mais on **reprend fidèlement les couleurs de marque réelles d'Immich** pour l'accent et les états sémantiques, plutôt que de les réinventer. Ces valeurs sont extraites du thème officiel d'Immich (`--immich-primary`, `--immich-error`, etc., définies dans le design system `@immich/ui` et son thème historique).

#### Couleur de marque (accent)

| Mode | Hex | RGB | Usage |
|---|---|---|---|
| Light | `#4250AF` | 66, 80, 175 | `Color.accentColor` — le bleu-violet caractéristique du logo et des CTA Immich |
| Dark | `#ACCBFA` | 172, 203, 250 | Éclairci pour rester lisible sur fond noir, tout en gardant la même teinte |

#### Fonds et texte (repris tels quels, en plus des semantic colors système)

| Token | Light | Dark | Usage |
|---|---|---|---|
| `immich.background` | `#FFFFFF` | `#000000` | Immich utilise du noir pur en dark (pas de gris système), pour un rendu très contrasté façon "cinema mode" sur les photos |
| `immich.foreground` | `#000000` | `#E5E7EB` | Texte primaire |
| `immich.gray` | `#F6F6F4` | `#212121` | Fond des cards, cellules, zones secondaires |

#### Couleurs sémantiques (états)

| Rôle | Light | Dark | Usage |
|---|---|---|---|
| Succès | `#81C784` | `#388E3C` | Upload réussi, confirmation |
| Erreur | `#E57373` | `#D32F2F` | Échec, suppression, alerte |
| Warning | `#FFB74D` | `#F57C00` | Avertissement, quota bientôt atteint |

**Règle d'implémentation** : ces couleurs sont déclarées comme un `Color` dynamique (light/dark) dans un fichier `ImmichColors.swift` dédié (voir livrable ci-joint), **jamais** en hex codé en dur dans les vues. Pour tout le reste (fonds neutres, séparateurs, texte tertiaire), on continue d'utiliser les semantic colors iOS (`.systemBackground`, `.secondaryLabel`, etc.) — on ne réplique la palette Immich que là où elle porte l'identité de marque.

> Note : le design system web actuel d'Immich (`@immich/ui`) a évolué vers une palette étendue à 11 nuances par couleur (50 à 950, en espace `oklch`) pour plus de finesse dans les états hover/pressed. Les valeurs ci-dessus sont les couleurs de référence (les "500") qui définissent l'identité visuelle ; si besoin de nuances supplémentaires (hover, pressed, disabled), on les dérive de ces teintes de base plutôt que d'en inventer de nouvelles.

### 5.3 Typographie

Utilisation exclusive de **Dynamic Type** avec les styles texte système (`.largeTitle`, `.title`, `.headline`, `.body`, `.footnote`, `.caption`) — pas de tailles fixes en points.

| Contexte | Style | Poids |
|---|---|---|
| Titre de section timeline ("Juillet 2026") | `.title3` | `.semibold` |
| Nom d'album | `.headline` | `.semibold` |
| Métadonnées (date, taille fichier) | `.footnote` | `.regular` |
| Compteur (nb photos) | `.caption` | `.medium`, `.secondary` |

Police système (SF Pro / SF Compact) exclusivement. Support complet de l'accessibilité texte (jusqu'à AX5).

### 5.4 Iconographie

**100% SF Symbols**, avec variantes cohérentes :
- `photo.on.rectangle.angled` → onglet Photos
- `square.stack` → Albums
- `magnifyingglass` → Recherche
- `person.2.fill` → Partagé
- `person.crop.circle` → Profil/Moi
- `heart` / `heart.fill` → Favoris
- `trash` → Corbeille
- `arrow.up.circle.badge.clock` → Upload en cours (avec `.symbolEffect(.variableColor)` en iOS 17+)
- `checkmark.circle.fill` → Sélection multiple

Rendu : `.hierarchical` par défaut, `.multicolor` réservé aux états spéciaux (succès/erreur).

### 5.5 Grille & espacement

Grille basée sur un système de **8pt spacing** :

| Token | Valeur | Usage |
|---|---|---|
| `spacing.xs` | 4pt | Espacement interne icône/texte |
| `spacing.sm` | 8pt | Padding cellule |
| `spacing.md` | 16pt | Marges de contenu standard |
| `spacing.lg` | 24pt | Séparation entre sections |
| `spacing.xl` | 32pt | Header d'écran |

**Grille photo (Timeline)** :
- `LazyVGrid` avec `adaptive(minimum: 100, maximum: 130)`, spacing = 2pt (comme Photos.app, quasi sans marge entre vignettes).
- Support du **pinch-to-zoom** pour changer la densité de la grille (2 → 3 → 5 colonnes), comme Photos.app natif.
- Coins **non arrondis** dans la grille dense (fidèle à Photos.app), arrondis (`cornerRadius: 12`) uniquement dans les vues Albums/cards.

### 5.6 Composants clés

#### a) Timeline avec section headers collants
`LazyVGrid` dans un `ScrollView`, avec `pinnedViews: [.sectionHeaders]` pour les headers de mois collants, + un **scrubber latéral** (indicateur de date au survol, drag vertical rapide) répliquant le comportement Photos.app.

#### b) Visionneuse plein écran
- `TabView(.page)` ou `ScrollView` horizontal paginé pour le swipe entre photos.
- Zoom via `MagnificationGesture` + `DragGesture` combinés (double-tap to zoom).
- Contrôles auto-masqués au tap, `.ultraThinMaterial` en fond des toolbars.
- Transition d'ouverture : `matchedGeometryTransition` (iOS 18+) ou `Namespace` custom pour un zoom fluide depuis la grille — **c'est LE détail qui rend l'app "Apple-like"**.

#### c) Cards Albums
`RoundedRectangle(cornerRadius: 16)`, cover image + `.ultraThinMaterial` overlay pour le titre, ombre légère (`shadow(radius: 4, y: 2)`), grid 2 colonnes.

#### d) Sélection multiple
Mode sélection activé par long-press, checkmarks en overlay (coin haut-droit des vignettes), barre d'actions contextuelle en bas (`.toolbar(.bottom)`) — partage, favoris, suppression, ajout à album.

#### e) Upload / Backup status
Bannière discrète type "Dynamic Island-friendly" en haut de la Timeline (pas de modal bloquant), avec barre de progression fine + Live Activity optionnelle pour suivi en lock screen.

#### f) Formulaires (réglages, connexion serveur)
`Form` natif avec `Section`, style `.insetGrouped` — jamais de formulaire custom.

### 5.7 Gestes & interactions

| Geste | Action |
|---|---|
| Tap sur vignette | Ouvrir visionneuse (transition zoom) |
| Long-press vignette | Activer sélection multiple + Context Menu (aperçu quick look) |
| Pinch sur grille | Changer densité colonnes |
| Swipe horizontal (visionneuse) | Photo suivante/précédente |
| Swipe vertical vers le bas (visionneuse) | Fermer (interactive dismiss, façon Photos.app) |
| Double-tap (visionneuse) | Zoom in/out |
| Pull-to-refresh (timeline) | Sync manuelle |
| Swipe actions (liste albums) | Renommer / Supprimer / Épingler |

### 5.8 Motion

- Toutes les transitions utilisent les courbes système (`.spring(response:dampingFraction:)` par défaut, pas de `.linear`).
- Durées courtes : 0.25–0.35s pour les micro-interactions, 0.4–0.5s pour les transitions d'écran.
- Respect de `accessibilityReduceMotion` : fallback en simple fade/cross-dissolve.

### 5.9 Dark Mode & accessibilité

- Dark Mode natif via semantic colors — pas de thème custom à maintenir.
- Contraste AA minimum sur tous les textes superposés à des images (utiliser `.ultraThinMaterial`/`.regularMaterial` sous le texte plutôt que des dégradés custom).
- VoiceOver : chaque vignette expose un label ("Photo, 12 juillet 2026, avec 2 personnes"), la visionneuse expose les actions via Accessibility Actions plutôt que des boutons cachés.
- Support Voice Control, Switch Control, Dynamic Type XXL, et `accessibilityReduceTransparency`.

### 5.10 Onboarding — ajout d'un serveur

**Principe** : un flow progressif à 5 écrans, un seul focus par écran, dans l'esprit des flows natifs d'ajout de compte (Mail, Calendrier). Pas de formulaire unique avec URL + email + mot de passe d'un coup — chaque étape se valide avant de passer à la suivante, avec feedback immédiat.

#### Écran 1 — Bienvenue
- Icône serveur dans un badge `bg-accent`, titre "Bienvenue dans Immich", sous-titre expliquant l'action à venir.
- Un seul CTA : "Continuer".
- Objectif : poser le contexte avant de demander quoi que ce soit à l'utilisateur.

#### Écran 2 — Adresse du serveur
- Un seul champ : URL du serveur (`TextField`, `.keyboardType(.URL)`, `.textInputAutocapitalization(.never)`, autocorrection désactivée).
- Bouton secondaire "Scanner un QR code" — Immich web expose déjà un QR code de config serveur dans les réglages profil ; le scan (`AVFoundation`/`VisionKit DataScannerViewController`) évite la saisie manuelle d'une URL longue, dans l'esprit du transfert de configuration Watch/AirTag.
- Historique des serveurs récents en suggestions sous le champ (si l'utilisateur en a déjà utilisé plusieurs).
- Validation en direct : format URL, ajout automatique de `https://` si omis.

#### Écran 3 — Vérification du serveur
- Étape automatique, sans action utilisateur : ping de l'endpoint `/api/server-info/ping` puis `/api/server-info/config`.
- Affichage explicite de ce qui a été vérifié : version du serveur détectée, statut de connexion sécurisée, validité du certificat TLS.
- **Cas certificat auto-signé** (fréquent en self-host) : pas de blocage silencieux ni d'erreur générique — un état dédié affiche le détail du certificat (émetteur, empreinte) avec un choix explicite "faire confiance à ce certificat" / "annuler". Jamais de confiance automatique et silencieuse.
- Cas d'échec (serveur injoignable, mauvaise URL) : message inline sous le champ de l'écran précédent, pas d'alert modale — l'utilisateur reste dans son flow et peut corriger directement.

#### Écran 4 — Connexion
- Champs email + mot de passe (`SecureField`), un seul CTA "Se connecter".
- Si le serveur expose une config OAuth (`/api/server-info/config`), un bouton "Continuer avec [fournisseur]" apparaît au-dessus du formulaire classique, ouvert via `ASWebAuthenticationSession`.
- Erreurs d'authentification affichées inline sous le champ concerné (ex: "mot de passe incorrect"), jamais de popup.
- Option "Se souvenir de moi sur cet appareil" liée au stockage Keychain.

#### Écran 5 — Succès et activation
- Confirmation visuelle (badge succès) + message court, sans ton excessif ("vous êtes connectée", pas "connexion réussie avec brio").
- CTA unique et actionnable : "Activer la sauvegarde automatique" — on ne s'arrête pas à la confirmation passive, on convertit directement vers l'usage réel (sélection des albums locaux à synchroniser dans la foulée).
- Option secondaire discrète : "Configurer plus tard" pour ne pas forcer la main.

#### Gestion des erreurs — règles transverses
- Aucune `Alert`/popup bloquante dans tout le flow ; toutes les erreurs s'affichent en contexte (inline, sous le champ concerné), avec une couleur `text-danger` et une icône `exclamationmark.circle`.
- Les erreurs réseau (timeout, DNS) proposent un bouton "Réessayer" directement dans le message d'erreur.
- Le clavier ne se ferme jamais automatiquement après une erreur de saisie — l'utilisateur peut corriger sans retaper.

#### Accessibilité
- Chaque écran expose un titre de section via `accessibilityAddTraits(.isHeader)` pour la navigation VoiceOver rapide.
- Le scan QR code propose une alternative texte permanente (le champ URL reste toujours accessible, jamais de flow scan-only).
- Support Dynamic Type : les CTA passent en pleine largeur et le texte des boutons s'enroule sur deux lignes plutôt que d'être tronqué.

---

## 6. Architecture technique (résumé)

| Sujet | Choix |
|---|---|
| **Langage/UI** | Swift 6, SwiftUI (iOS 17 minimum, cible iOS 18 pour les transitions avancées) |
| **Architecture** | MVVM léger avec `@Observable` (Observation framework), pas de dépendance à un framework tiers type TCA sauf besoin avéré |
| **Concurrence** | Swift Concurrency (`async/await`, `actor` pour le cache disque) |
| **Réseau** | Génération du client API depuis l'OpenAPI spec d'Immich (comme le fait déjà le projet officiel) |
| **Cache local** | `SwiftData` pour les métadonnées (assets, albums), cache disque LRU pour les vignettes |
| **Upload background** | `BackgroundTasks` (`BGProcessingTask`) + `URLSession` background configuration |
| **Images** | Décodage progressif, thumbnails multi-résolution (façon `NSCache` + prefetching sur scroll) |
| **Deep linking** | `NavigationPath` + Universal Links pour les partages d'albums |

---

## 7. Exigences non-fonctionnelles

- **Performance** : scroll de la timeline à 120fps sur ProMotion même avec >50k assets (recyclage de cellules, prefetch anticipé sur direction de scroll).
- **Offline-first partiel** : la grille affiche les vignettes en cache même hors-ligne ; actions (favoris, suppression) mises en file et synchronisées au retour réseau.
- **Sécurité** : credentials serveur en Keychain, support certificats auto-signés (cas fréquent en self-host) avec avertissement clair.
- **Multi-serveur** : possibilité de basculer entre plusieurs instances Immich sans déconnexion complète.

---

## 8. Roadmap indicative

| Phase | Contenu | Durée estimée |
|---|---|---|
| **Phase 0** | Setup projet, client API généré, auth, design system (composants de base) | 3 semaines |
| **Phase 1 (MVP)** | Timeline, visionneuse, upload auto, albums basiques, recherche simple | 6–8 semaines |
| **Phase 2** | Personnes, carte, souvenirs, partage avancé | 6 semaines |
| **Phase 3** | Widgets, Live Activities, Shortcuts, App Intents | 4 semaines |

---

## 9. Métriques de succès

- Temps de premier rendu de la timeline < 300ms (depuis cache).
- Taux de complétion d'upload en arrière-plan sans intervention utilisateur > 95%.
- Score d'accessibilité VoiceOver : 100% des actions atteignables sans souris/tap direct.
- Rétention J7 comparable ou supérieure à l'app Flutter actuelle sur un panel de beta-testeurs.

---

## 10. Points ouverts / à trancher

- Faut-il une app iPad dédiée (layout 3 colonnes type Mail/Photos iPad) dès le MVP, ou en Phase 2 ?
- Faut-il supporter Catalyst pour une version Mac "gratuite", ou est-ce hors scope ?
- Niveau de parité avec les fonctions d'administration serveur (aujourd'hui plutôt web-only sur Immich) ?
- Stratégie de migration des utilisateurs existants de l'app Flutter (cohabitation, ou remplacement direct) ?
