# Mémoire du projet — opencode-config

> Mémoire persistante **spécifique à ce projet**. Lue par `scout` à chaque
> Phase 1 (recall ciblé par mot-clé via `.opencode/bin/recall.sh`) et alimentée
> par `debugger` (causes racines) + opportunistiquement par `build` (décisions,
> conventions découvertes).
>
> Pour une galère réutilisable **au-delà de ce projet** (comportement surprenant
> d'une lib, bug connu d'un framework), écrire dans la mémoire globale
> cross-projets via la skill `global-memory-writer` à la place — cette mémoire-ci
> est pour le contexte métier/architecture propre au projet courant.

## Format d'une entrée

```
## [YYYY-MM-DD] Titre court — [tag: mot-clé]

**Contexte** : ...
**Décision/apprentissage** : ...
**Pourquoi** : ...
**Fichiers concernés** : ...
```

Ajout via :
```bash
./.opencode/bin/append-memory.sh "Titre" "tag" "contexte" "décision" "pourquoi" "fichiers"
```

---

## Décisions d'architecture

<!-- Décisions structurantes prises sur ce projet, avec rationale. -->

## Conventions découvertes

<!-- Conventions de nommage, gestion d'erreurs, structure des tests,
     spécifiques à ce projet et non évidentes depuis le code seul. -->

## Leçons (causes racines documentées par debugger)

<!-- Une entrée par bug non-trivial résolu : symptôme, cause racine réelle,
     fichier corrigé. Évite de retomber sur le même piège entre sessions. -->

## Pièges d'environnement

<!-- Particularités de config, dépendances system, versions piégeuses,
     chemins absolus locaux, etc. -->

## [2026-07-27] Bug recall template scaffolding matché — [tag: recall-bug]

**Contexte** : recall.sh matchait préambule fichier et headers de section du template, au lieu de matcher uniquement les vraies entrées datées.
**Décision/apprentissage** : Restreindre démarrage bloc à `^## \[` (date entre crochets = format canonique append-memory.sh), skip code fences markdown ```, et ne rien accumuler tant que block vide.
**Pourquoi** : Empêcher faux positifs quand mot-clé apparaît dans préambule/scaffolding plutôt que dans une vraie entrée datée.
**Fichiers concernés** : .opencode/bin/recall.sh lignes 31-42

## [2026-07-28] Shells on-demand (specialist + contractor) — Phase 1.5 — [tag: ondemand, architecture]

**Contexte** : Besoin initial de l'utilisateur : tous les agents pipeline (sauf plan) doivent pouvoir DEPLOYER des subagents CUSTOM à la volée, sans prompt pré-construit par domaine. Première itération (4 specialists pré-câblés db/security/perf/docs) REJETÉE par l'utilisateur — il voulait du runtime-defined, pas du pre-built. Refonte en 2 shells génériques.
**Décision/apprentissage** : Deux shells on-demand dans opencode.json : `specialist` (advisory, edit:deny, bash read-only, task:deny) et `contractor` (action-capable, edit:allow, bash:allow avec deny-list minimale rm/sudo/mkfs/git push+commit+reset+tag, task:deny). Aucune expertise pré-câblée — l'agent caller décrit rôle+tâche dans le prompt de l'invocation `task`. opencode ne permet PAS d'enregistrer un nouvel agent à l'exécution, mais le `prompt` du `task` parameterize entièrement le shell → c'est le mécanisme on-the-fly. Les deux sont leaf nodes (task:deny) donc consomment 1 niveau de subagent_depth sans récursion. Allow-list explicite {specialist, contractor} dans la permission task des 6 agents pipeline (sauf plan verrouillé). Discovery via .opencode/bin/list-ondemand.sh (parse opencode.json, filtre l'ensemble fixe {specialist, contractor}). Règle d'escalade inchangée : finding invalidant une hypothèse du plan = re-challenge (compte plafond 3 boucles) ; finding purement amélioratoire = amendement mineur. Trade-off assumé : contractor action-capable ⇒ un agent read-only (scout/reviewer/challenger) peut indirectement muter du code via délégation — encadré par le prompt d'invocation (caller décrit le scope), leaf node (pas de récursion), et diff repassé par reviewer.
**Pourquoi** : "deploy custom sub agents on the fly, not defined by any pre built prompt" — l'expertise émerge de l'invocation, pas d'un fichier statique. Split advisory/action pour couvrir "conseil" ET "accomplir des tâches" (l'utilisateur a explicitement choisi cette option). Leaf node + allow-list explicite préservent les garde-fous de la pipeline core (scout ne peut pas invoquer debugger).
**Fichiers concernés** : .opencode/opencode.json (agents specialist+contractor, task perms 6 agents pipeline), .opencode/prompts/ondemand/{specialist,contractor}.txt (shells chameleon), .opencode/bin/list-ondemand.sh, .opencode/AGENTS.pipeline.md (Phase 1.5), .opencode/prompts/{build,challenger,scout,reviewer,tester,debugger}.txt (triggers on-the-fly), opencode.example.json

## [2026-07-28] Migration Graphify → codebase-memory-mcp — [tag: mcp, architecture]

**Contexte** : Remplacement du moteur d'exploration codebase de scout : Graphify (CLI Python pipx graphifyy) était lent et limité. User a demandé son remplacement par codebase-memory-mcp (binaire C DeusData) annoncé plus rapide et performant.
**Décision/apprentissage** : Migration complète : suppression de toutes les refs Graphify (AGENTS.md, AGENTS.pipeline.md, opencode.json, opencode.example.json, prompts/scout.txt, dcp.jsonc, install.sh, README.md, .gitignore), suppression du dossier graphify-out/, ajout entrée MCP codebase-memory-mcp dans opencode.json avec timeout 60000ms, install.sh étape 2 migrée vers curl|bash officiel DeusData. 14 MCP tools natifs (search_graph, trace_path, get_architecture, get_graph_schema, detect_changes, search_code, get_code_snippet, etc.) remplacent les 3 CLI graphify query/path/explain. Index SQLite persistant dans ~/.cache/codebase-memory-mcp/ (hors-projet, auto-sync activé).
**Pourquoi** : Performance annoncée : 120x moins de tokens, sub-ms queries, 159 langues, single static binary zero-dep, SLSA niveau 3 + VirusTotal scanned. Bénéfice direct sur la consommation de contexte de scout (Phase 1 pipeline). Timeout 60000 inclus car premier connect peut durer >5s sur première indexation (reco fork stevenke1981).
**Fichiers concernés** : AGENTS.md (section codebase-memory-mcp), .opencode/opencode.json (entrée mcp.codebase-memory-mcp + description scout), .opencode/AGENTS.pipeline.md (lignes 24, 111), .opencode/prompts/scout.txt (7 MCP tools), .opencode/dcp.jsonc (protectedFilePatterns sans graphify-out/**), opencode.example.json (bloc mcp + description scout), install.sh (étape 2, menu, uninstall, header, résumé, variables), README.md (10 refs + tableau + Important + validation), .gitignore (lignes 4-5), suppression graphify-out/

## [2026-07-29] Phase 0 brainstorm + acceptance contract — auto-feedback loop — [tag: acceptance-contract, brainstorm, architecture]

**Contexte** : User a demandé une étape de brainstorm produisant un auto-feedback loop avant impl, pour que la pipeline puisse self-tester si l'implémentation est correcte. Critique interne avait identifié : les critères de succès étaient de la PROSE (build.txt:6, reviewer.txt:9 les mappaient diff↔critères mais flous), pas de machine-check, 'done' = opinion LLM pas fait vérifiable. 3 boucles challenger (plafond atteint) ont levé 2 objections bloquantes puis 2 + 1 bloquantes, toutes adressées : ordonnancement (contract généré AVANT challenger, pas après), porte 'must FAIL' trop stricte (introduit types new/regression), format AC cassé pour '0 tests ran' (reframe autour de vérité d'assertion), handoff chemin contract (build passe chemin absolu dans chaque task()), etc.
**Décision/apprentissage** : Phase 0 restructurée en 0a-0d. 0a: recall mémoire. 0b: build déploie specialist rôle 'architect' (prompt inclut template AC-NNN copié textuellement — specialist n'a pas de mémoire entre invocations) qui génère acceptance contract: critères AC-NNN exécutables taggués new (red→green) ou regression (green→green), assertion naturelle + check exécutable + transitions attendues + top 3 failure modes. Specialist NE fait pas self-red-team (même modèle = angle mort partagé, c'est challenger cross-model qui valide). 0c: build persiste plan+contract dans .opencode/scratch/<task-slug>.acceptance.md (artifact de handoff persistant, stoppe dégradation contexte entre agents). 0d: challenger valide plan+contract comme UNITÉ (3-loop cap couvre les deux ensemble). Phase 1: scout lit contract en premier, confirme chaque hypothèse du contract (fichiers/APIs/conventions) existe réellement cite fichier:ligne, signale invalidations. Phase 2: build materialise les AC-test (tester a edit:deny), re-valide challenger si scout invalide hypothèse. Phase 3: DEUX baselines — A (suite existante, détecte régressions) + B (acceptance contract, prouve validité AC). Auto-feedback = transitions vérifiées post-impl: AC new doit passer (était rouge), AC regression doit rester vert. Code se juge lui-même, pas de jugement LLM sur 'done'. Recovery rules pour pré-states inattendus (regression cassé pré-existant = documenter pas corriger ; new déjà satisfait = no-op ou AC trop faible à re-concevoir). Phase 4: rapporte AC pass/fail + bugs pré-existants + vérifs manuelles restantes.
**Pourquoi** : One-shot accuracy. Critères prose → 'done' opinion. Critères exécutables → 'done' fait vérifiable. Auto-feedback loop (red→green / green→green) supprime le besoin de jugement humain/LLM sur le succès — le contrat est auto-évalué. Template AC-NNN standardise le format pour parsing fiable par tester. Artifact scratch stoppe le telephone-game entre agents (chacun part d'un context frais sinon).
**Fichiers concernés** : .opencode/AGENTS.pipeline.md (intro l3, Phase 0 restructurée + template AC-NNN inline l7-73, Phase 1 l75-83, Phase 2 l114-122, Phase 3 restructurée l124-152 baseline A+B + recovery, Phase 4 l157-161, routage l174), .opencode/prompts/build.txt (Phase 0 0a-0d + handoff contract + Phase 2 materialise AC + Phase 3 deux baselines + recovery), .opencode/prompts/challenger.txt (valide plan+contract unité, AC testable/nécessaire/suffisant/type/failure-modes), .opencode/prompts/scout.txt (lit contract premier, confirme hypothèses), .opencode/prompts/tester.txt (baselines A+B distinctes, post-impl transitions par type), .opencode/prompts/reviewer.txt (diff↔AC mapping), .opencode/scratch/.gitkeep (créé), .gitignore (l11-14 règle scratch/* + !.gitkeep). LIMITATIONS DOCUMENTÉES: (1) temp specialist 0.2 → divergence structurée pas créative, valeur réelle = AC exécutables + validation challenger cross-model pas exotisme approches ; (2) assertions non automatisables (layout visuel, UX flow, accessibilité) EXCLUES du contract, vont en section 'Vérifications manuelles' hors auto-feedback loop ; (3) parsing markdown AC par tester fragilité résiduelle mitigée par format fenced strict.

## [2026-07-29] Immich SwiftUI architecture + API surface — [tag: architecture,immich-api,mvvm]

**Contexte** : Greenfield SwiftUI clone of Immich (Flutter original). Foundation scope: auth + server discovery + timeline grid (bucket pagination) + asset detail + upload scaffold. iOS 17+ required (@Observable macro). All 14 ACs in acceptance contract proven by 19 XCTest methods, 0 failures. Project generated via xcodegen from project.yml.
**Décision/apprentissage** : Single-Module Monolith + MVVM + @Observable. Layers L0 Core/Types (DTOs, AssetReactItem, APIError, Constants) -> L1 Core/Protocols (ImmichClient, KeychainStore, PhotoLibraryService) -> L2 Services (ImmichAPIClient/URLSession async, KeychainStoreImpl/Security, PhotoLibraryServiceImpl) -> L3 Features/*/ViewModel (@Observable, constructor-injected, @MainActor) -> L4 Features/*/Views (stateless) -> L5 ImmichAppApp + DependencyContainer (@MainActor) + RootView (auth-gated router). No TCA, no SPM multi-module, no Combine.
**Pourquoi** : Fastest-to-ship greenfield pattern. Protocols make future SPM extraction trivial. AuthViewModel implements AuthSessionDelegate so global 401 -> resetSession (no circular dep with ImmichAPIClient).
**Fichiers concernés** : Sources/Core/{Constants.swift,Types/*,Protocols/*}, Sources/Services/* (ImmichAPIClient, MultipartBody, JSONCoding, KeychainStoreImpl, PhotoLibraryServiceImpl, AuthenticatedAsyncImage, ImmichAssetURL), Sources/Features/{Auth,Timeline,AssetDetail,Upload}/*, Sources/{ImmichSwiftUIApp.swift,RootView.swift,DependencyContainer.swift}, Tests/* + Tests/Mocks/*

## [2026-07-29] Immich server API gotchas (OpenAPI + Dart verified) — [tag: immich-api,pitfalls]

**Contexte** : Server endpoints deviate from common REST conventions in several non-obvious ways. All verified against OpenAPI spec + server Zod + Dart SDK in Phase 0d/1.
**Décision/apprentissage** : 1) GET /api/server/ping returns JSON application/json ServerPingResponse{res:'pong'} — NOT text/plain 'pong'. 2) POST /api/auth/logout returns 200 + LogoutResponseDto{successful,redirectUri} — NOT 204. 3) Asset update uses PATCH /api/assets/:id (PR #28859); PUT is deprecated, v4 drops it. 4) GET /api/timeline/buckets has NO size param — server picks granularity. 5) GET /api/timeline/bucket returns COLUMNAR TimeBucketAssetResponseDto (14 required parallel arrays + 5 optional), must zip by index. NO in-bucket pagination — loadMore = next bucket. 6) Upload multipart: isFavorite sent as STRING 'true'/'false' (server stringToBool), NOT Bool. Only 10 fields accepted (assetData, fileCreatedAt, fileModifiedAt, duration, filename, isFavorite, visibility, livePhotoVideoId, metadata, sidecarData). x-immich-checksum is HEADER (base64 SHA1), not form field. 7) Dates: ISO8601 yyyy-MM-dd'T'HH:mm:ss.SSSZ everywhere EXCEPT timeBucket (plain YYYY-MM-DD). 8) Thumbnail cache-bust ?c={thumbhash} is CLIENT convention (server ignores unknown params).
**Pourquoi** : Each one was a Phase 0d challenger OBJECTION. Building on assumed-but-wrong contract = silent breakage on real server.
**Fichiers concernés** : Sources/Services/ImmichAPIClient.swift, Sources/Services/MultipartBody.swift, Sources/Core/Types/DTOs.swift, Sources/Core/Types/AssetReactItem.swift, Sources/Services/JSONCoding.swift

## [2026-07-29] Swift/xcodebuild pitfalls hit during impl — [tag: swift,xcodebuild,pitfalls]

**Contexte** : Greenfield SwiftUI iOS 17 project. Xcode 26.6, iPhone 17 Pro sim (NO iPhone 16 in this install).
**Décision/apprentissage** : 1) URLProtocol body capture: URLSession converts URLRequest.httpBody to httpBodyStream for non-trivial bodies. Must read stream bytes in URLProtocol.startLoading, httpBody alone returns nil. 2) Multipart body contains binary 0xAB etc -> String(data:as:UTF8.self) returns nil. Use String(decoding:as:UTF8.self) for lossy ASCII-survivable search. 3) @Observable + protocol Sendable conformance forces @MainActor on the class (AuthViewModel). Then any non-MainActor caller of its init breaks build -> mark DependencyContainer @MainActor too. 4) PHImageManager.requestImageDataAndOrientation may invoke handler >1x (progressive delivery) -> wrap continuation in OSAllocatedUnfairLock<Bool> one-shot gate or crash on double-resume. 5) xcodegen manages project.pbxproj — DO NOT hand-edit. Edit project.yml then 'xcodegen generate'.
**Pourquoi** : Each cost >1 build/test cycle. Documented for next session.
**Fichiers concernés** : Tests/ImmichAPIClientTests.swift (CapturingURLProtocol), Sources/Services/PhotoLibraryServiceImpl.swift, Sources/Features/Auth/AuthViewModel.swift, Sources/DependencyContainer.swift, project.yml

## [2026-07-29] xcodegen écrase les overrides manuels du pbxproj — [tag: xcodegen pbxproj build-config signing]

**Contexte** : project.yml source de vérité pour Xcode Gen. pbxproj checked-in portait DEVELOPMENT_TEAM=2MJF39L8VY + PRODUCT_BUNDLE_IDENTIFIER=fr.millianlmx.immich-ios SANS ces champs dans project.yml. xcodegen generate (requis pour enregistrer nouveaux fichiers source) a clobberé ces overrides -> build local cassait le signing et changeait le bundle ID.
**Décision/apprentissage** : Toujours mettre l'identité (PRODUCT_BUNDLE_IDENTIFIER + DEVELOPMENT_TEAM) dans project.yml avant tout xcodegen generate. Le pbxproj est régénéré, jamais source de vérité.
**Pourquoi** : Reviewer a flagué D1+D2 HIGH sur le diff pbxproj. Une régénération xcodegen sans project.yml à jour dérive l'identité silencieusement. Coût : 1 cycle de fix.
**Fichiers concernés** : project.yml, ImmichSwiftUI.xcodeproj/project.pbxproj

## [2026-07-30] Timeline redesign elegant professional — [tag: timeline-redesign,architecture]

**Contexte** : User trouvait l'UI timeline 'ugly'. Redesign via approche A (Apple Photos Refinement) : spacing grille 2→4pt, cornerRadius cell 3→8pt continuous, header jour headline.medium/.secondary/.regularMaterial padding 20/10, bannière mois-année title.bold 32pt top, toolbar logout bouton direct→Menu person.circle, scroll-to-top caché en mode sélection, tints sélection blue 0.18→0.15 / black 0.08→0.06, badge padding 6→4.
**Décision/apprentissage** : Redesign purement View-layer : VM @Observable inchangé (vérifié via snapshot shasum baseline). Extraction logique intercalage mois dans TimelineSectionBuilder (pure func testable, 6 tests). typealias TimelineSection = TimelineSectionBuilder.Section dans la View évite dup enum. LazyVStack spacing 0 (les bannières portent l'espacement vertical via leur propre top padding 32pt).
**Pourquoi** : Approche A retenue (vs B grille Pinterest hauteur variable = trop risqué badges/gaps, vs C cards&shadows = over-designed coûteux sur >100 cellules). Fidélité HIG iOS 17+, risque régression minimal, élégance par typographie+espacement (secret Apple Photos). Amendement mineur accepté sans re-challenge : projectionBadge unifié au pattern .frame(...).padding(4) des autres badges (favorite/video) pour cohérence — purement amélioratoire n'invalidate aucune hypothèse.
**Fichiers concernés** : Sources/Features/Timeline/{TimelineView.swift,AssetThumbnailCell.swift,TimelineSectionBuilder.swift (NEW),MonthYearBanner.swift (NEW)}, Tests/TimelineSectionBuilderTests.swift (NEW, 6 tests). project.yml inchangé mais pbxproj régénéré via xcodegen (PRODUCT_BUNDLE_IDENTIFIER + DEVELOPMENT_TEAM préservés).
