---
name: memory-recall
description: Consulte la mémoire du projet courant (.opencode/memory.md) de façon ciblée par mot-clé, au lieu de la charger en entier. Utilise-la avant toute décision d'architecture ou investigation de bug, pour ne pas re-proposer une décision déjà rejetée ou retomber sur un piège déjà documenté.
---

# Memory Recall — contexte du projet courant

La mémoire projet (`.opencode/memory.md` à la racine du projet) accumule :

- **décisions d'architecture** prises sur ce projet, avec rationale ;
- **conventions** de nommage/erreurs/tests propres au projet ;
- **leçons** : causes racines documentées par `debugger` après résolution ;
- **pièges d'environnement** : configs piégeuses, versions locales, chemins absolus.

Elle grossit au fil des sessions — ne pas la dumper en entier dans le contexte.
Recall ciblé à la place :

```bash
./.opencode/bin/recall.sh "mot-clé-technique-ou-métier"
```

## Quand l'invoquer

- **Phase 0 (build, avant plan)** : avec les mots-clés du domaine de la tâche
  (nom du module, type d'objet métier, API visée). Évite de re-proposer un
  choix déjà invalidé.
- **Phase 1 (scout)** : avant exploration, pour respecter conventions locales.
- **Phase 3 (tester/reviewer)** : si un échec ressemble à un symptôme familier,
  recall avant de conclure — la cause racine est peut-être déjà documentée.

## Si recall ne renvoie rien

Essaie un synonyme technique avant de conclure à l'absence d'antécédent
(recherche par sous-chaîne insensible à la casse, pas sémantique).

## Complément : mémoire globale cross-projets

Pour les galères réutilisables au-delà de ce projet (comportement de lib,
framework, config d'outil), consulte aussi la mémoire globale :

```bash
~/.config/opencode/bin/recall-global.sh "mot-clé"
```

Voir la skill `global-memory-recall` pour le détail.
