---
name: memory-writer
description: Utilise cette skill quand tu identifies une décision d'architecture, une convention, une cause racine de bug, ou un piège d'environnement SPÉCIFIQUE à ce projet (pas transposable ailleurs). Écrit dans la mémoire du projet courant pour la réutiliser entre sessions.
---

# Memory Writer — mémoire du projet courant

Cette mémoire est **locale au projet** (`.opencode/memory.md` à la racine). Elle
n'est pas injectée en entier dans le contexte de chaque agent — c'est la skill
`memory-recall` qui sert à la consulter de façon ciblée.

## Quand écrire ici (critère strict)

Pose-toi la question : "cette entrée a-t-elle du sens UNIQUEMENT dans le
contexte de ce projet ?" Si oui → ici.
Si l'entrée est réutilisable dans un projet totalement différent
(comportement surprenant d'une lib, bug connu d'un framework) → mémoire globale
via la skill `global-memory-writer` à la place.

Exemples qui vont **ici** (mémoire projet) :
- "Le endpoint `/orders` de notre backend a un bug d'arrondi sur la TVA — contourné via X" (métier).
- "Décision : on utilise Zod pour la validation côté serveur, pas Yup, parce que Y" (architecture locale).
- "Ce projet tourne sur Node 18 spécifiquement, ne pas proposer Node 20+" (environnement).
- Cause racine d'un bug non trivial documentée par `debugger` (3-5 lignes max).

Exemples qui vont dans la **mémoire globale** (skill `global-memory-writer`) :
- "Tel package npm casse le build avec Node 22+ sauf si on passe tel flag".
- "L'API X renvoie une pagination cassée au-delà de 1000 résultats".

## Comment écrire

```bash
./.opencode/bin/append-memory.sh \
  "Titre court" \
  "tag-mot-clé" \
  "Contexte : ce qui se passait / pourquoi on a dû trancher" \
  "Décision ou apprentissage concret" \
  "Pourquoi (rationale, pas juste le quoi)" \
  "Fichiers concernés (chemins)"
```

N'écris qu'une fois le problème réellement résolu et vérifié — pas une
hypothèse de solution non testée. Pour une cause racine documentée par
`debugger`, on reste concis : titre + symptôme en 1 ligne + cause racine réelle
(pas le symptôme) + fichier corrigé.

## Éviter les doublons

Avant d'écrire, fais un recall sur le mot-clé pour vérifier qu'une entrée
équivalente n'existe pas déjà. Si oui, édite-la plutôt que d'en ajouter une
nouvelle.
