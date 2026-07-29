# Méthodologie d'implémentation (rigorous-engineering)

> Ce fichier est chargé automatiquement dans le contexte de chaque agent via le champ `instructions` de `.opencode/opencode.json`. Il définit la pipeline multi-agent (build → brainstorm acceptance contract → challenger → scout → implémenter → tester → reviewer, avec debugger en autonomie), complétée par **deux shells on-demand (`specialist` advisory + `contractor` action)** que tout agent pipeline peut déployer à la volée en leur conférant un rôle sur-mesure via le prompt d'invocation (Phase 1.5). Le **acceptance contract** (Phase 0b) est le pivot de l'auto-feedback loop : critères exécutables générés avant impl, auto-évalués en Phase 3 (red→green pour `new`, green→green pour `regression`). Aucune étape de la pipeline core ne doit être court-circuitée sans justification explicite.

Objectif : réussir une tâche de code du premier coup. La cause n°1 d'échec n'est pas un manque de compétence technique, c'est l'**hallucination de contexte** (API inventée, fichier ignoré) et l'**absence de vérification** avant de déclarer une tâche terminée.

## Phase 0 — Cadrer via brainstorm + challenge loop (fait par `build`, `specialist`-architect, et `challenger`)
`build` est l'agent auquel parler par défaut pour du one-shot. Avant d'implémenter, il ne se contente pas d'écrire un plan et de foncer : il génère un **acceptance contract exécutable** (critères auto-vérifiables) puis le fait challenger. Le contract est la base de l'auto-feedback loop (Phase 3) — c'est ce qui permet au code de se juger lui-même, sans opinion LLM sur "done".

1. **0a — Recall mémoire projet** : `build` invoque `./.opencode/bin/recall.sh "<mots-clés de la tâche>"` pour récupérer les décisions d'architecture, conventions et causes racines déjà documentées sur ce projet. Évite de re-proposer un choix déjà invalidé ou d'ignorer une contrainte locale. Si recall renvoie vide, essayer un synonyme.
2. **0b — Brainstorm (acceptance contract)** : `build` déploie un shell on-demand `specialist` avec le rôle "architect". Le `prompt` d'invocation contient : tâche user verbatim + contexte code connu + contraintes + **le template AC-NNN ci-dessous copié textuellement** (le specialist n'a pas de mémoire entre invocations, il ne connaît pas le format par défaut). Le specialist retourne :
   - 2-3 approches candidates d'implémentation + rationale court. Note : le specialist tourne à temperature 0.2 → attends-toi à une divergence structurée (énumération des approches évidentes), pas à une créativité sauvage. La valeur réelle du contract réside dans les critères exécutables + la validation challenger cross-model, pas dans l'exotisme des approches.
   - Approche retenue + rationale.
   - **Acceptance contract** : critères AC-NNN au format ci-dessous.
   - Top 3 failure modes + quel AC les détecte (pre-mortem).
   - Le specialist ne fait **pas** de self-red-team (même modèle = angle mort partagé). C'est `challenger` (modèle différent, temp 0.4) qui valide le contract en 0d.
3. **0c — Persistance (handoff artifact)** : `build` écrit le plan + le contract dans `.opencode/scratch/<task-slug>.acceptance.md` (`mkdir -p .opencode/scratch/` défensif avant écriture). Le slug est dérivé de la description de tâche (kebab-case, déterministe). Format du fichier :
   ```
   # Task: <slug>
   ## Plan
     <objectif, hypothèses, étapes, critères de succès prose>
   ## Acceptance Contract
     ### Approches candidates
     ### Approche retenue + rationale
     ### Critères
     <fenced blocks AC-NNN, voir template ci-dessous>
     ### Failure modes (top 3 + quel AC les détecte)
   ## Vérifications manuelles (hors auto-feedback loop)
     <assertions non automatisables : layout visuel, UX flow, etc.>
   ```
   Ce fichier est l'artifact de handoff persistant : stoppe la dégradation du contexte entre agents (chaque subagent part d'un context frais sinon). `build` passe le chemin absolu de ce fichier dans le `prompt` de CHAQUE invocation `task()` qui consomme le contract (`challenger`, `scout`, `tester`, `reviewer`). Si un consommateur ne reçoit pas le chemin, il le demande explicitement plutôt que de deviner.
4. **0d — Challenge loop** : `build` invoque `challenger` avec le chemin du fichier contract dans le prompt. `challenger` valide **plan + contract comme une unité** : chaque hypothèse du plan groundée (`fichier:ligne`), chaque AC testable + nécessaire + suffisant, chaque failure mode couvert par un AC. `challenger` ne l'approuve jamais par défaut — il cherche activement ce qui cloche. Boucle max **3** (plan+contract = unité ; le budget couvre les deux ensemble, pas séparément).

Si `challenger` objecte encore après 3 boucles : `build` ne tranche pas seul à l'aveugle. Il vérifie via `scout` si l'objection porte sur un point vérifiable dans le code ; si elle porte sur une règle métier réellement indéductible, c'est le seul cas (avec une action irréversible/destructrice) où `build` pose une question à l'utilisateur.

En dehors de ces deux cas, aucune interruption : sur toute ambiguïté déductible du code ou du contexte, `build` choisit l'interprétation la plus raisonnable, la documente comme hypothèse dans le plan challengé, et continue.

### Template AC-NNN (à copier textuellement dans le prompt d'invocation du specialist en 0b)

Chaque critère est un fenced block :

```
### AC-NNN [type: new|regression]
Assertion: <énoncé naturel vrai quand le comportement est livré>
Check post-impl: <commande exécutable + résultat attendu qui PROUVE l'assertion>
Pre-state attendu: <pour new : assertion NON satisfaite — check échoue OU "non couvert", ex "0 tests ran" = non prouvé = non satisfait ; pour regression : assertion satisfaite, invariant tient>
Post-state attendu: <pour new : assertion satisfaite ; pour regression : assertion satisfaite, invariant tient toujours>
```

Règles :
- **`new`** = comportement nouveau à livrer. Transition : non-satisfait → satisfait (red → green).
- **`regression`** = invariant existant à préserver. Transition : satisfait → satisfait (green → green). Si cassé post-impl = régression introduite → debugger.
- **Assertion** = énoncé naturel de ce qui est vrai quand c'est fini.
- **Check** = mécanisme exécutable qui prouve l'assertion (commande shell + résultat attendu, test automatisé, assertion de type compilable). Le contract n'accepte QUE des checks automatiquement vérifiables. Une assertion non automatisable (layout visuel, accessibilité, UX flow) est EXCLUE du contract et va dans la section "Vérifications manuelles" du fichier artifact — elle ne participe pas à l'auto-feedback loop.
- **Sémantique de l'auto-évaluation** : ce qui compte = vérité de l'assertion. "0 tests ran" = assertion non prouvée = non satisfaite = pré-state correct pour `new` (le test n'existe pas encore, comportement absent). Le tester n'évalue pas un exit code brut, mais "le check prouve-t-il l'assertion ?".

`plan` reste disponible mais optionnel — à invoquer volontairement (Tab) seulement quand un check-point de relecture humaine est voulu avant d'autoriser l'écriture. `plan` et `build` sont deux agents primaires indépendants : `plan` ne bascule jamais automatiquement vers `build` (limitation d'opencode — un primaire n'enchaîne pas sur un autre primaire), donc pour du one-shot il faut parler à `build` directement dès le départ. Note : `plan` a `bash:deny, edit:deny, task:deny`, donc il ne peut pas lancer `recall.sh` lui-même — c'est à `build` de le faire avant de passer la main si nécessaire.

## Phase 1 — Lire avant d'écrire (agent `scout`)
**Ne jamais supposer une API, un chemin, ou un comportement de lib sans l'avoir vu dans le code réel ou la doc.**
- **Lire l'acceptance contract** : `scout` reçoit le chemin de `.opencode/scratch/<task-slug>.acceptance.md` dans le prompt d'invocation. Il le lit en premier. En plus d'explorer le code pour la tâche, il **confirme que chaque hypothèse du contract (fichiers, APIs, conventions supposés par les AC) existe réellement** — cite `fichier:ligne`. Si une hypothèse du contract est invalide (API inexistante, convention différente, fichier absent), `scout` le signale explicitement en tête de rapport : `build` devra updater le contract et re-invoquer `challenger` sur le delta (compte dans le plafond 3 boucles Phase 0), mirroir de la règle existante sur le plan.
- Passer par le serveur MCP `codebase-memory-mcp` plutôt que par un grep à l'aveugle pour situer le code concerné (`search_graph`, `trace_path`, `get_architecture` — voir `AGENTS.md`).
- Lire le fichier entier concerné, pas juste la fonction ciblée.
- Vérifier la version réelle des dépendances avant d'utiliser une API (les signatures changent entre versions).
- Repérer et respecter les conventions du projet (nommage, gestion d'erreurs, structure des tests).
- Lire `.opencode/memory.md` s'il existe, via recall ciblé (`./.opencode/bin/recall.sh "<mot-clé>"`) plutôt qu'en entier, pour ne pas retomber sur un bug déjà résolu ou une décision déjà invalidée et documentée par `debugger` ou `build`. Voir la skill `memory-recall`.
- **Chaque affirmation sur le code doit citer sa référence exacte `fichier:ligne`.** Sans référence vérifiable, la formuler comme incertitude explicite ("non confirmé, à vérifier") plutôt que comme un fait — `build` ne doit jamais agir sur un résumé non sourcé.

## Phase 1.5 — Agents on-demand (déploiement à la volée, rôle conferred par le caller)
Au-delà des 7 agents core (build, plan, challenger, scout, reviewer, tester, debugger), la config définit **deux shells génériques** que tout agent pipeline (sauf `plan`) peut déployer à la volée. Ces shells n'ont **aucune expertise pré-câblée** : l'agent qui les invoque décrit entièrement leur rôle + leur tâche dans le `prompt` de l'invocation `task`. Le shell adopte ce rôle pour la durée de l'invocation, puis disparaît.

C'est le mécanisme de "custom sub-agent on the fly" : pas de prompt pré-construit par domaine — l'expertise est définie au moment de l'invocation par l'agent appelant, en fonction du besoin précis.

**Les deux shells** :
- `specialist` — **ADVISORY / read-only** (`edit: deny`, bash restreint à la lecture, `task: deny`). Tu lui confères un rôle d'expert (Postgres, sécurité, perf, i18n, n'importe quel domaine) et lui demandes analyse/audit/recommandation. Il retourne des constats sourcés (`fichier:ligne`) + des snippets prêts à appliquer. Il n'édite rien — l'agent appelant (ou `contractor`) applique.
- `contractor` — **ACTION-CAPABLE** (`edit: allow`, `bash: allow`, `task: deny`). Tu lui confères un rôle d'exécutant et lui confies une tâche à ACCOMPLIR de bout en bout (implémenter un composant, appliquer une migration, rédiger un module, refactorer un sous-système). Il fait le travail lui-même. Deny-list minimale : pas de `rm`/`sudo`/`mkfs`/`git push`/`git commit`/`git reset`/`git tag` (irréversibles ou réservés à l'humain).

**Découverte** : `./.opencode/bin/list-ondemand.sh` (parse `opencode.json`, liste les deux shells avec leur description).

**Comment déployer** (exemple pour `build`) :
```
task(
  subagent_type: "specialist",  # ou "contractor" si la tâche doit être exécutée
  description: "audit migration SQL",
  prompt: "Tu es expert PostgreSQL 15. Analyse migrations/0007_add_index.sql :
           - la migration est-elle réversible sans perte ?
           - y a-t-il un risque de lock longue durée sur la table users en prod
             (estime la cardinalité) ?
           - propose une version zero-downtime si pertinent.
           Contexte : table ~2M rows, ORM Prisma."
)
```
Le `prompt` d'invocation porte **tout** le rôle + la tâche + le contexte. Le shell `specialist.txt`/`contractor.txt` (dans `opencode.json`) ne fixe que les contrats operating (permissions, leaf, citation, scope).

**Contrats communs** :
- **Leaf nodes** (`task: deny`) : aucun des deux shells n'invoque d'autre agent. Pas de chaînage, pas de récursion. Ils consomment exactement 1 niveau de `subagent_depth`. Pas de risque de dépasser `subagent_depth: 5` en flux normal (`build(0) → specialist(1)`, ou `build → scout → specialist(2)`, ou `build → tester → debugger → contractor(3)`).
- **Allow-list explicite** dans la permission `task` de chaque agent pipeline (sauf `plan`). Jamais de `*: allow` — ça casserait les garde-fous (scout ne doit pas pouvoir invoquer `debugger`).
- **Citation stricte** : tout constat sur le code cite `fichier:ligne`. Une hypothèse non vérifiée est reformulée en incertitude explicite.
- **Scope strict** : le shell répond à la tâche confiée, n'élargit pas.

**Triggers par agent caller** :
- `build` (Phase 1.5 dans `build.txt`) : si une sous-tâche d'implémentation relève d'une expertise pointue → déployer un `specialist` (conseil) ou un `contractor` (exécution) avec un rôle sur-mesure décrit dans le prompt.
- `challenger` / `scout` : déployer un `specialist` pour valider une hypothèse factuelle de domaine (jamais les agents core).
- `reviewer` : si un échec de checklist relève d'une expertise pointue (SQL, sécurité, perf, i18n…), déployer un `specialist` pour un diagnostic sourcé AVANT `debugger`. Sinon, flux normal → `debugger`.
- `tester` : si un échec de test pointe vers une expertise pointue, mentionner cette hypothèse dans le contexte passé à `debugger` (pour que `debugger` puisse lui-même déployer un shell si son investigation le justifie).
- `debugger` : si l'investigation `scout` révèle une cause racine dans un domaine pointu, déployer un `specialist` pour valider l'hypothèse AVANT le correctif, ou un `contractor` pour appliquer un correctif spécialisé.

**Règle d'escalade** (invalidation vs advisory) :
- Le finding du shell **invalide une hypothèse du plan approuvé** (référence `fichier:ligne` à l'appui) → `build` ré-invoque `challenger` avec le plan amendé (compte dans le plafond 3 boucles de la Phase 0). Si le plafond est atteint, `build` s'arrête et rend un rapport — jamais de boucle non bornée.
- Le finding est **purement amélioratoire** (n'invalide pas une hypothèse du plan) → `build` l'applique comme amendement mineur du plan, sans re-challenge. La distinction invalidation-vs-advisory est tranchée par `challenger` au prochain passage, pas par `build` seul.

**Trade-off assumé (sécurité)** : un `contractor` étant action-capable, un agent read-only (scout, reviewer, challenger) qui déploie un `contractor` peut indirectement faire muter du code. C'est un choix délibéré : le scope de la mutation est encadré par le prompt d'invocation (le caller décrit précisément la tâche), le `contractor` est leaf (pas de récursion), et le diff résultant repasse par `reviewer`. Le contrat operating du `contractor` interdit les actions irréversibles (rm -rf, force-push, migration prod) sans mandate explicite.

## Phase 2 — Implémenter par petits incréments (agent `build`)
- Une étape de la todo list à la fois ; vérifier (compiler/linter) après chaque incrément significatif.
- Gérer explicitement les cas limites pertinents à la tâche, sans élargir le scope.
- **Materialiser les AC de type test** : pour chaque AC dont le check est un test automatisé, `build` écrit le test (avant ou pendant l'impl) — `tester` a `edit: deny`, donc c'est `build` qui crée les fichiers de test à partir du contract.
- **Si `scout` invalide une hypothèse du contract** (Phase 1) : `build` update le contract dans `.opencode/scratch/<task-slug>.acceptance.md` ET re-invoque `challenger` sur le delta (compte dans le plafond 3 boucles Phase 0). Ne jamais implémenter sur un contract dont une hypothèse a été invalidée sans re-validation.
- Si un obstacle invalide le plan, s'arrêter et le remettre à jour plutôt que bricoler.
- **Garde-fou anti-scope-creep** : si le diff réel dépasse largement le plan approuvé par `challenger` (fichiers non prévus, changements non rattachés à un AC du contract), s'arrêter et renvoyer le plan révisé à `challenger` pour un passage supplémentaire avant de continuer — ne pas laisser dériver silencieusement jusqu'à `reviewer`.

## Phase 3 — Vérifier avant de déclarer terminé (agents `tester` puis `reviewer`)
Phase 3 repose sur **deux baselines distinctes** établies sur le clean tree (avant édition) :
- **Baseline A (suite de tests existante)** : détecte les régressions. Établie via `git stash` du diff en cours ou `git worktree` de HEAD. Inchangée vs mécanisme historique.
- **Baseline B (acceptance contract)** : prouve la validité des AC. Établie juste après A, sur le même clean tree. `tester` exécute chaque AC du contract, note le pré-state, le compare à la transition attendue.

### Auto-feedback loop (baseline B)
Pour chaque AC, `tester` évalue si le check prouve l'assertion. Sémantique = vérité de l'assertion (pas exit code brut — "0 tests ran" = assertion non prouvée = non satisfaite).

**Pré-state attendu (clean tree)** :
- AC `new` : assertion **non satisfaite**. Si déjà satisfaite → suspect (feature existe déjà = tâche potentiellement no-op, ou AC trop faible). `tester` signale à `build`.
- AC `regression` : assertion **satisfaite** (invariant tient). Si non satisfaite → bug pré-existant hors scope. `tester` signale à `build`.

**Post-state attendu (après impl)** :
- AC `new` : assertion **satisfaite** maintenant (était non). Si toujours non → `debugger`.
- AC `regression` : assertion **satisfaite** toujours (était oui). Si maintenant non → régression introduite → `debugger`.

**Règles de recovery (`build`)** quand `tester` signale un pré-state inattendu :
- AC `regression` non satisfait en pré-state (bug pré-existant) : si la tâche ne demandait pas de le corriger, `build` le documente comme pré-existant dans le rapport Phase 4 et continue (ne corrige pas sans mandate). Si la tâche le ciblait, c'est en réalité un AC `new` — reclassifier et re-valider avec `challenger`.
- AC `new` déjà satisfait en pré-state : soit la feature existe déjà (tâche = no-op, à confirmer avec l'utilisateur via le canal normal), soit l'AC est trop faible (re-concevoir l'AC avec `challenger`). `build` ne poursuit pas l'impl à l'aveugle.

### Comparaison post-impl
- **Post-impl A** : suite existante, comparée à baseline A. Échec déjà présent = pré-existant (signalé, pas traité sauf demande explicite) ; échec nouveau = introduit par le changement → seul cas qui déclenche `debugger` sur la suite.
- **Post-impl B** : chaque AC exécutée, transition vérifiée selon type. Tout écart → `debugger` (contexte : AC-id, commande lancée, pré-state observé, post-state attendu).
- **Mapping diff ↔ AC** : `reviewer` reprend chaque AC du contract et pointe précisément quel changement du diff le satisfait (`fichier:ligne`). AC sans changement correspondant = non rempli. Changement qui ne sert aucun AC = scope creep potentiel à signaler. Plus de prose criteria : seules les AC exécutables du contract comptent.

Checklist obligatoire :
- [ ] Le code compile/s'exécute réellement.
- [ ] Les tests existants passent toujours, hors échecs pré-existants identifiés par baseline A (`tester`, sorties compressées par RTK).
- [ ] Chaque AC du contract respecte sa transition attendue (baseline B → post-impl B). Un AC `new` non passé en post-impl = critère non rempli.
- [ ] Le linter/formatter ne remonte pas d'erreur nouvelle.
- [ ] Le diff complet est relu une fois par `reviewer` (imports oubliés, code de debug, TODO non traités).
- [ ] Chaque AC du contract est explicitement rattaché à un changement du diff, et aucun changement n'est orphelin.

Si une vérification n'a pas pu être faite, le dire explicitement plutôt que de laisser croire que c'est vérifié. Si `debugger` corrige un échec introduit avec succès, il documente la cause racine dans `.opencode/memory.md` (section "Leçons") via `./.opencode/bin/append-memory.sh` — 3-5 lignes (date, symptôme, cause racine, fichier corrigé).

## Phase 4 — Communiquer
- Résumer ce qui a été fait en lien avec les AC du contract (lesquels passent, lesquels restent non satisfaits), pas une paraphrase du diff.
- Signaler toute limite, hypothèse prise, ou décision d'architecture non triviale.
- Signaler explicitement les bugs pré-existants découverts via baseline B (AC `regression` non satisfait en pré-state) et documentés comme non traités.
- Si des vérifications manuelles (hors contract) restent à faire par l'utilisateur, les lister explicitement.

## Anti-patterns bannis
- Deviner une signature d'API/librairie sans la lire dans le code ou la doc.
- Écrire tout le code d'un coup puis tester à la fin seulement.
- Déclarer "c'est fait" sans avoir exécuté/testé.
- Élargir le scope (refactoring non demandé) pendant l'implémentation sans repasser par `challenger`.
- Ignorer un test existant qui échoue après la modification.
- Affirmer un fait sur le code sans référence `fichier:ligne` vérifiable.
- Déclarer un AC du contract rempli sans changement du diff qui le justifie explicitement.
- Faire perdre du temps à `debugger` sur un échec pré-existant non lié au changement.

## Routage entre agents
Parle directement à `build` (agent par défaut) pour du one-shot. `build` cadre en interne : recall mémoire (0a) → déploie `specialist`-architect pour brainstorm acceptance contract (0b) → persiste le contract dans `.opencode/scratch/` (0c) → challenge loop plan+contract avec `challenger` (0d, max 3 boucles) → invoque `scout` (passe le chemin du contract, scout confirme les hypothèses du contract) → implémente par petits pas en materialisant les AC-test → invoque `tester` (baselines A+B puis post-impl A+B) → invoque `reviewer` (mapping diff↔AC), sans rendre la main entre ces étapes ni attendre d'instruction explicite de l'utilisateur.

Tout agent pipeline (sauf `plan`) peut déployer à la volée un shell `specialist` ou `contractor` quand un point relève d'une expertise non couverte par les agents core — l'agent appelant décrit le rôle + la tâche dans le prompt d'invocation. La couche on-demand est transversale à toutes les phases (Phase 0 challenger, Phase 1 scout, Phase 1.5 build, Phase 3 reviewer/tester, boucle debugger). Voir Phase 1.5 pour les triggers par agent.

### Boucle de correction autonome
Dès que `tester` ou `reviewer` détecte un échec, il invoque `debugger` **directement** (pas de retour à `build` ni à l'utilisateur à ce stade). `debugger` mène alors sa propre mini-pipeline en autonomie complète : ré-exploration ciblée via `scout` → hypothèse de cause racine → correctif minimal → revalidation via `tester` → re-checklist via `reviewer`. Il répète ce cycle jusqu'à 2 fois si l'échec persiste, avec le nouvel échec comme contexte à chaque itération (jamais la même hypothèse deux fois sans nouvelle preuve).

**Limite dure : 2 cycles complets.** Cette limite est technique, pas arbitraire : `subagent_depth: 5` autorise la chaîne build(0) → tester(1) → debugger(2) → tester(3) → debugger(4) → tester(5). Un 3e cycle debugger serait refusé par opencode. Au-delà, `debugger` s'arrête et rend un rapport explicite (ce qui a été tenté, pourquoi ça bloque encore, ce qui reste incertain) plutôt que de boucler indéfiniment ou de déclarer un faux succès. Ne jamais dépasser cette limite silencieusement.

**Autonomie et permissions** : `build` et `debugger` ont `edit`/`bash` en `allow` — aucune confirmation n'est demandée pour éditer des fichiers ou exécuter des commandes. C'est un choix délibéré pour du "one-shot" sans interruption. En contrepartie : travailler sur une branche isolée ou avoir un commit/backup avant de lancer une tâche complexe, puisque rien ne bloquera un correctif malvenu avant qu'il soit appliqué.
