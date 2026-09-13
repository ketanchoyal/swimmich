# Task: shared-links-enriched — UI Brief

**Statut** : brief **réécrit le 2026-09-13**. La version d'origine décrivait une refonte « Liquid Glass » qui n'a jamais été construite (cartes `glassEffect` dans une `List`, `ExternalLinkPreviewSheet` en `WKWebView`, `MoreActionsButton`) et qui ne correspond ni au design system du dépôt ni à la surface livrée. Ce brief-ci décrit ce qui est réellement à l'écran.

## Design Philosophy

Un lien partagé est une **ligne de gestion**, pas une fenêtre vitrée. L'onglet Shared est une `List` `.plain` sur fond système, où chaque lien est une **carte** (`Color.bgSecondary`, `PVRadius.lg`) portant : type + verrou, titre, URL publique, et deux actions inline — copier et partager. Le langage visuel est celui des autres listes du dépôt (Trash, Stacks, Partners) : tokens `PVSpacing` / `PVRadius` / `Color.*PV`, pas de verre.

Ce qui change ici ne change pas la mise en page : un **champ slug**, un **sélecteur d'expiration**, un **écran « lien prêt »** après création, et un **bouton Partager** à côté du copier.

## Surfaces livrées

### 1. `SharedLinkRow` — la carte de lien (partagée onglet Shared + feuille album)

```
┌────────────────────────────────────────────────────────────┐
│ [rectangle.stack] Titre du lien                        (…)  │   ← type + verrou éventuel
│                                                            │
│ https://photos.example.com/s/trip-2026   [doc] [square↑]   │   ← URL du builder, copier, partager
└────────────────────────────────────────────────────────────┘
```

- L'URL vient du **builder unique** (`SharedLinkURL`) : `externalDomain` si configuré, sinon l'URL du serveur ; `/s/<slug>` si le lien a un slug, sinon `/share/<key>`. Monospaced, `lineLimit(1)`, `truncationMode(.middle)`.
- **Copier** : `doc.on.doc` → `checkmark` + un `Text("Copied")` temporaire (identifiant `sharedLinkCopyFeedback`) pendant 2 s. Identifiant du bouton : `sharedLinkCopy-<id>`.
- **Partager** : `ShareLink(item: url)` (identifiant `sharedLinkShare-<id>`), icône `square.and.arrow.up`, ouvert sur le même lien que le copier.
- **Pièges respectés** : pas de `.buttonStyle(.plain)` sur un bouton dans une `List` (il avale le tap) — style par défaut + `.contentShape(Rectangle())` + `foregroundStyle` explicite ; `.accessibilityLabel` jamais posé sur un conteneur (il fusionnerait ses enfants) ; identifiants sur les feuilles, jamais sur les libellés (les CTA sont localisés).
- Swipe-to-revoke et menu contextuel (Edit / Revoke) inchangés.

### 2. `CreateSharedLinkSheet` — création + écran « lien prêt »

Deux états dans la même feuille, comme Flutter (`newShareLink.value.isEmpty ? form : ready`) :

**État 1 — formulaire** (`Form`, `navigationTitle("New Shared Link")`)

| Section | Contenu |
|---|---|
| Album | `Picker` sur les albums de l'utilisateur (CTA désarmé sans album choisi) |
| Options | Description · « Password protect » + `SecureField` |
| Options | **Custom URL** : `TextField`, préfixe `/s/` **affiché seulement quand le champ est non vide** (le slug stocké ne porte pas le préfixe) |
| Options | **Expiration** : `SharedLinkExpiryPicker` |

**État 2 — « lien prêt »** (après un create réussi)

```
        ✓
    Link ready
https://photos.example.com/s/trip-2026
   [ Copier ]      [ Partager ]
```

- Le lien est **copié automatiquement** à l'arrivée (parité Flutter), et le feedback « Copié » est visible sans tap.
- Identifiants : `sharedLinkReadyScreen`, `sharedLinkReadyCopy`, `sharedLinkReadyShare`, `sharedLinkReadyDone`.
- Le bouton Done ferme ; la ligne est déjà dans la liste (le VM a ajouté le DTO renvoyé par le serveur).

### 3. `SharedLinkExpiryPicker` — presets + date/heure

Une seule rangée, réutilisée par la création **et** l'édition (une surface à maintenir au lieu de deux qui divergent) :

- `Toggle("Expires", isOn: $hasExpiry)`.
- 9 presets alignés sur Flutter, en `Picker` (menu) : **Never · 30 minutes · 1 hour · 6 hours · 1 day · 7 days · 30 days · 90 days · 1 year**. Choisir un preset écrit `now + durée` ; **Never** désarme `hasExpiry`.
- Quand `hasExpiry` est vrai : `DatePicker(displayedComponents: [.date, .hourAndMinute], in: Date()...)` — l'édition manuelle de la date reste la source de vérité (un preset est un raccourci d'écriture, pas un état parallèle).
- Identifiant de la rangée : `sharedLinkExpiryPicker`.

### 4. `EditSharedLinkSheet` — édition

Ajouts au formulaire existant (Description, Password, Permissions) :

- **Custom URL** : `TextField` avec le préfixe `/s/`, initialisé avec `link.slug ?? ""`. Le DTO renvoie **toujours** le slug courant : le serveur écrit `slug: dto.slug || null`, donc un slug omis efface le slug existant.
- **Expiration** : `SharedLinkExpiryPicker` remplace le `Toggle` + `DatePicker` nus.

### 5. `SharedLinkSheet` — liens d'un album

La section « New Link » gagne le champ slug et les presets d'expiration (mêmes composants), et la liste des liens existants passe au builder d'URL. Le retour post-création y reste la ligne ajoutée : cette feuille est un contexte secondaire, l'écran « lien prêt » vit dans l'onglet Shared.

## Ce qui n'est pas construit (et pourquoi)

- **Viewer public** (`WKWebView`, saisie de mot de passe, upload invité) : carte + issue **#22**. Aucune parité Flutter, et pas de plomberie d'auth pour porter une clé de partage dans le client HTTP.
- **`ExternalLinkPreviewSheet` / `MoreActionsButton` / cartes `glassEffect`** : jamais construits, écartés par la conception. Ne pas les « rétablir ».
- Les routes `public/:slug`, `:slug/assets`, `:slug/check-password` de la version d'origine n'existent pas côté serveur ; aucune UI ne doit les supposer.
