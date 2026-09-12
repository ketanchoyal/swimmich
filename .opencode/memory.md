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

## [2026-07-30] Backlog V1.5 polish + V2 features (post-MVP session 7 commits) — [tag: backlog v1.5 v2 polish deferred post-mvp]

**Contexte** : Contexte : session MVP 7 features commit (616ae57..4007cf2), 145 tests verts. Cahier PhotoVault entièrement livré MVP. Advisories non-bloquants collectés par reviewer/tester sur chaque feature (AppLock, Trash, EXIF, Search, Albums, Editor). User a demandé persistance backlog.
**Décision/apprentissage** : V1.5 polish (effort faible): (1) Editor renderPreview() debounce — re-render pipeline complet par tick slider, candidat V1.5; (2) Albums AddToAlbumPickerSheet VM jetable — déplacer addAssets(ids:toAlbumId:) vers AlbumsViewModel, supprime 1 searchMetadata wasted call (AddToAlbumPickerSheet.swift:70); (3) Haptics partiels — CreateAlbumSheet manque .success sur create, PhotoEditorView tap cell absent; (4) i18n hardcoded EN partout (toutes features: AppLock 'Unlock PhotoVault', Trash 'Trash', Search 'No results', Albums 'Add to Album', Editor 'Revenir à l'original', etc.); (5) Editor PhotoEditorView.previewSection UIScreen.main.bounds.width deprecated iPad multi-window → GeometryReader. || V2 features (cahier-deferred, effort plus gros): (1) Editor auto-horizon straightening (Vision/CoreML, cahier §5 L121 V1.5->V2); (2) Editor filtres prédéfinis previews (cahier §5 L124 V2); (3) Editor sync edits serveur + export/save camera-roll (cahier §5 L128 V2); (4) Editor retouche locale pinceau (cahier §5 V3); (5) Albums collaborative albums albumUsers add/remove (cahier §8 L157 deferred); (6) Search People/faces tab — GET /api/people + /api/people/:id/thumbnail binaire + drill-down via searchMetadata personIds (L136 deferred iteration 2); (7) Albums UpdateAlbumDto edit name/description (droppe du contract phase 0); (8) Albums SharedLink expiresAt UI Picker (SharedLinkCreateDto a le champ, SharedLinkSheet l'expose pas).
**Pourquoi** : Pourquoi : persister les items deferrés pour sessions futures. V1.5 = quick wins isolation nette sans refactor d'archi. V2 = périmètre cahier explicite avec spec source. Évite re-discovery + permet recall ciblé par feature/mot-clé.
**Fichiers concernés** : Sources : .opencode/scratch/{app-lock,trash-30j,exif-map-detail,search-ia,albums-share-link,editor-non-destructive}.acceptance.md (6 contracts). PhotoVault-Cahier-des-fonctionnalites.md §5/§8. Comments advisory reviewer tester task_ids dans commits 616ae57/5c2478a/e51cdbf/f1ab5d0/0edf0f0/51d7210/4007cf2.

## [2026-07-30] Env xcodebuild + jq paths — [tag: [tag: env xcodebuild simulator jq]]

**Contexte** : xcodebuild destination name=iPhone 16 introuvable ; jq absent de /opt/homebrew/bin + /usr/local/bin
**Décision/apprentissage** : Simulateurs dispo = iPhone 17 / 17 Pro / 17e / Air (iOS 26.5), PAS iPhone 16 ; jq binaire est à /usr/bin/jq (Apple system), pas homebrew
**Pourquoi** : Future sessions : utiliser destination 'platform=iOS Simulator,name=iPhone 17' et JQ=/usr/bin/jq dans scripts AC pour éviter faux FAIL
**Fichiers concernés** : n/a (env, pas de fichier corrigé)

## [2026-07-30] Immich-flavored redesign (all screens) — [tag: immich-redesign,design-system,tokens]

**Contexte** : User trouvait l'app 'neutral/ugly', voulait match design system ORIGINAL immich. Approche B retenue (vs A=mirror immich enums duplication, vs C=chrome-only sans tokens trop cosmétique) : PV tokens réalignés sur valeurs Immich + nouveaux composants chrome. Scope = all 12+ screens en une passe.

**Décision/apprentissage** :
- **Tokens réalignés** (sources: immich-app/immich `mobile/packages/ui/lib/src/theme.dart` + `constants.dart`):
  - PVRadius: `none=0, xs=4, sm=8 (unchanged), md=12 (était 14), lg=16 (était 20), xl=20, xxl=24, full=999`.
  - PVSpacing: `+s0=0, +s48=48` (autres s2/s4/s8/s12/s16/s24/s32 déjà matchaient immich).
  - Font: `+pvBodyLarge=16 semibold, +pvH6=18 sb, +pvH5=20 sb, +pvH4=24 bold, +pvH3=30 bold, +pvH2=36 bold, +pvH1=48 bold`. **pvBody STAYS 17** (iOS HIG body, ne pas descendre à immich body=14 — trop petit pour iOS natif).
  - PVDuration (NEW): `extraFast=0.10, fast=0.15, normal=0.20, moderate=0.30, slow=0.50, extraSlow=0.70` (seconds).
- **Chrome immich** : `Sources/DesignSystem/Components/ImmichAppBar.swift` (NEW) — `struct ImmichAppBar: View` (logo `camera.aperture` brandIndigo + wordmark pvH6 textPrimaryPV, pour `ToolbarItem(placement: .principal)`); `struct ImmichLogo` standalone (auth/launch); `extension View { immichBottomBar() }` applique `.tint(brandIndigo) + .toolbarBackground(Color.bgSecondary, for: .tabBar) + .toolbarBackground(.visible, for: .tabBar)`.
- **Logo SVGs absents du repo** (`Resources/**/*.svg` glob vide) → fallback SF Symbol `camera.aperture` + texte. Quand SVGs `immich-logo-inline-light.svg`/`-dark.svg` arriveront, swapper le body de `ImmichLogo` sans toucher aux call sites.
- **Pattern adopté sur 5 tabs top-level** : `.navigationTitle("") + .navigationBarTitleDisplayMode(.inline) + ToolbarItem(.principal) { ImmichAppBar() }`. Drop le `.large` Apple-Photos. TimelineView swap principal → count text quand `vm.selectionMode`.
- **RootView TabView** : `.immichBottomBar()` (encapsule tint+bg). Pas de `.tint()` inline.
- **Token hygiene sweep** : 6 sites `cornerRadius: 0` → `PVRadius.none` (AlbumsView, AssetThumbnailCell, TimelineView ×2, SearchView, AssetDetailView). 0 raw Color dans Features (AC-003 préservé, DS-exempt markers AssetThumbnailCell + RootView LockView hero intact).
- **Status colors** : `statusSuccess`/`statusError`/`accentInfo` tokens existent déjà (`Color+PhotoVault.swift:14-17` via LogoGreen/LogoRedPink/LogoBlue). Valeurs pas exactement immich (#10C14F/#FA2921/#1984E9) mais assez proches — retune out of scope.

**Pourquoi** :
- Approche B = single source of truth préservée (PV* restent seuls tokens), tous écrans auto-redesign via mutation atomique des valeurs token. Pas de 40-60 site changes comme approche A.
- pvBody=17 gardé : iOS users attendent 17pt body. Immich body=14 trop dense pour natif iOS. Pour immich-feel compact : utiliser pvSubhead(15)/pvCaption(13).
- pvH1..pvH5 actuellement unused hors ImmichAppBar.pvH6 — ACCEPTABLE car token completeness, pas dead code risk (seront utilisés au fur et à mesure).
- `immichBottomBar()` modifier préférable à inline `.tint()` — encapsulation réutilisable, RootView reste lisible.
- Native compromise : pas de Material elevation / scrolledUnderElevation / floating+sinned SliverAppBar — SwiftUI toolbar native + `.toolbarBackground(.visible)` suffit visuellement. iOS HIG gestures (swipe-back, pull-to-refresh, long-press) préservés.

**Process notes** :
- Specialist (architect) a produit le contract initial. Challenger a retourné EMPTY output 2× de suite (transient issue ?) — fallback à self-validation par lecture directe des fichiers (toutes hypothèses groundées fichier:ligne).
- AC-009 check command était cassé (`grep tint dans RootView | grep TabView` retourne 0 car `.tint()` et `TabView` sur lignes différentes + impl encapsule dans modifier). Fixed post-test : check via `rg 'immichBottomBar\(\)' Sources/RootView.swift` + `rg '\.tint\(Color\.brandIndigo\)' Sources/DesignSystem/Components/ImmichAppBar.swift`.
- Pre-state baselines NOT established avant edits (process gap) — post-state 153/0 green suffit comme preuve (memory dit 145 pré-state, +8 = nouvelles assertions token spacing/radius).

**Fichiers concernés** :
- Tokens : `Sources/DesignSystem/Tokens/{Spacing,Font,Motion}+PhotoVault.swift`.
- Component NEW : `Sources/DesignSystem/Components/ImmichAppBar.swift`.
- Tests : `Tests/DesignSystemTokensTests.swift` (testSpacingValues +9 assertions, testRadiusValues +8).
- Features modifiés : `RootView.swift` (immichBottomBar), `Timeline/AssetThumbnailCell.swift` + `TimelineView.swift`, `Albums/AlbumsView.swift`, `Search/SearchView.swift`, `Trash/TrashView.swift`, `Upload/UploadViewModel.swift` (BackupSettingsView), `AssetDetail/AssetDetailView.swift`.
- Contract : `.opencode/scratch/immich-redesign.acceptance.md` (10 ACs).
- project.yml inchangé mais pbxproj régénéré (PRODUCT_BUNDLE_IDENTIFIER + DEVELOPMENT_TEAM préservés, AC-005 ✓).

## [2026-07-31] PRD Phase 0 aligné — design system + nav — [tag: prd-phase0,design-system,tokens,onboarding,nav]

**Contexte** : Tâche = aligner projet existant sur PRD Phase 0 (§5.2 couleurs, §4 tabs, §5.10 onboarding). Approach B: tokens immich* canonical + anciens noms en aliases doc-comment-deprecated (PAS @available deprecated — éviter warning noise aux call sites).
**Décision/apprentissage** : 1) ImmichColors.swift (7 tokens immichPrimary/Background/Foreground/Gray/Success/Error/Warning via UIColor dynamicProvider) déplacé racine→Sources/DesignSystem/Tokens/. 2) 7 colorsets retunés PRD §5.2 (BrandIndigo #4250AF/#ACCBFA, LogoGreen #81C784/#388E3C, LogoRedPink #E57373/#D32F2F, LogoYellow #FFB74D/#F57C00, AccentColor transformé de idiom:universal→composantes explicites+dark, BgSecondary #F6F6F4/#212121, TextPrimary #000000/#E5E7EB). BgPrimary #FFF/#000 inchangé. 3) Color+PhotoVault.swift: 6 aliases (brandIndigo/brandIndigoMuted→immichPrimary, statusSuccess→immichSuccess, statusPending→immichWarning, statusError→immichError, accentInfo→immichPrimary); bg*/text*/separator restent asset-based. 4) RootView TabView 5 tabs PRD: Photos(photo.on.rectangle.angled)/Albums(square.stack)/Recherche(magnifyingglass)/Partagé(person.2.fill, SharedLinksView)/Moi(person.crop.circle, ProfileView). Trash+Backup relogés dans ProfileView via NavigationLink. Gate else→OnboardingFlowView. 5) Onboarding 5 écrans (Welcome/ServerURL/Verify/Login/Success) + // stubs.
**Pourquoi** : Unifie identité visuelle Immich (single source of truth = ImmichColors.swift), structure nav conforme PRD, onboarding scaffold prêt pour phases ultérieures. pvBody=17 STAYS (HIG). 12/12 AC PASS, 153 tests verts.
**Fichiers concernés** : Sources/DesignSystem/Tokens/{ImmichColors,Color+PhotoVault}.swift; Sources/RootView.swift; Sources/Features/{Profile/ProfileView,SharedLinks/SharedLinksView,Auth/OnboardingFlowView}.swift; Resources/Assets.xcassets/*.colorset/Contents.json

## [2026-07-31] NavigationStack path:[Step]=[] pas [welcome] — double-render root — [tag: swiftui,onboarding,pitfall,bugfix]

**Contexte** : OnboardingFlowView: NavigationStack(path:) avec Welcome comme root inline + navigationDestination(for: Step.self). Premier essai: path:[Step]=[.welcome] → Welcome apparaissait 2x (root + path[0]), back button montrait doublon.
**Décision/apprentissage** : INITIALISER path:[Step]=[] (vide). Le root inline affiche déjà Welcome; append au path pousse les étapes suivantes. Le case .welcome du switch destination(for:) devient mort mais reste requis pour exhaustivité du switch (compile).
**Pourquoi** : SwiftUI NavigationStack: si la racine est une View inline ET qu'on veut la gérer via path, ne pas la mettre dans path — sinon double-affichage. Convention: root inline = point d'entrée fixe, path = stack de push uniquement.
**Fichiers concernés** : Sources/Features/Auth/OnboardingFlowView.swift:22,26,36

## [2026-07-31] Onboarding input screens polish — cartes + focus ring + badge header — [tag: onboarding,design-system,prd]

**Contexte** : User trouvait la saisie URL+credentials 'ugly'. Redesign des 2 écrans d'input (ServerURLScreen + LoginScreen) seulement — Welcome/Verify/Success/Flow intacts (shasums vérifiés). 4 composants DS créés : PVInputGroup (carte bgSecondary+Radius.lg), PVFieldSurface (modifier ring stroke immichPrimary 1.5, opacity focused?1:0, PVMotion.snappy, PAS de background — la carte fournit le fond), PVHeaderBadge (badge 72pt icône 32pt wash immichPrimary 0.12 + accessibilityAddTraits isHeader), InlineErrorBadge DEPLACE de ServerURLScreen + param retry → bouton Réessayer (PRD:252). Corrections PRD réelles : erreur URL était APRÈS le bouton (l.56>44, PRD:237 violé) → déplacée sous le champ ; Login champs groupés en UNE carte avec Divider, labels EMAIL/MOT DE PASSE DANS les rows.
**Décision/apprentissage** : FocusState reste local aux écrans (Bool URL, Field? Login) — le modifier lit focused: Bool, PAS de binding générique (rejeté: domaines hétérogènes + compile fragile). Challenger round 1 = 5 objections contract toutes fondées (post-states inatteignables car bgSecondary/wash vivent dans composants → AC retargetés sur ADOPTION; && cassés par grep -c exit 1 → séparateurs ;). Round 2 annulé par user → corrections self-vérifiées, reviewer a re-validé cross-model 21/21 AC. AC-017: doc-comment contient @FocusState → pattern ^\s+@FocusState.
**Pourquoi** : Sources/DesignSystem/Components/{PVInputGroup,PVFieldSurface,PVHeaderBadge,InlineErrorBadge}.swift, Sources/Features/Auth/Onboarding/{ServerURLScreen,LoginScreen}.swift, .opencode/scratch/onboarding-input-screens-polish.acceptance.md
**Fichiers concernés** : non précisés

## [2026-07-31] Onboarding rebuilt — 3-step flow, verify folded inline — [tag: onboarding,design,architecture]

**Contexte** : User asked to rebuild onboarding as senior Apple engineer. Baseline built green. 4-step flow had a dead intermediate screen: ServerURLScreen already ran connectServer() then pushed ServerVerifyScreen to display the result (checking/reachable/unreachable) — redundant tap + empty screen until reachable.
**Décision/apprentissage** : Folded ServerVerifyScreen INTO ServerURLScreen: inline statusSection under the field (idle/checking spinner/reachable Label 'Serveur connecté' + ServerInfoCard/unreachable InlineErrorBadge+retry), CTA adapts (Vérifier→Réessayer→Continuer), .onChange(of: serverURLString) resets status to .idle so stale info clears when URL edited. Flow now welcome→serverURL→login (3 steps, Step enum 3 cases). Extracted shared modifier onboardingBottomBar (safeAreaInset bottom + padding s16 + frame maxWidth + .background(.regularMaterial, ignoresSafeAreaEdges: .bottom)) so material bar extends under home indicator edge-to-edge — applied to all 3 screens, removed 3 duplicated safeAreaInset blocks. Welcome bullets .system(size:20)→.pvH5. Login +.textContentType(.username/.password) (password managers) + .sensoryFeedback(.error, trigger: auth.errorMessage).  TODO moved into ServerURLScreen (was in deleted verify screen).
**Pourquoi** : Apple setup-assistant pattern: validate inline where the input lives, one screen per decision, edge-to-edge material bar. Redundant pushed confirmation step is anti-pattern. 153/153 tests green, AuthViewModel/RootView untouched.
**Fichiers concernés** : Sources/Features/Auth/Onboarding/{OnboardingFlowView,WelcomeScreen,ServerURLScreen,LoginScreen}.swift; Sources/DesignSystem/Components/PVInputGroup.swift (doc ref); ServerVerifyScreen.swift DELETED; xcodegen regenerated (identity preserved).

## [2026-07-31] Asset catalog jamais embarqué — xcodegen 2.46 drop resources: + colorsets sans idiom — [tag: xcodegen pbxproj assets colors]

**Contexte** : Texte des bullets Welcome invisible + cartes champs sans fond : Color("TextPrimary")/bgSecondary résolvaient .clear. 2 bugs chaînés : (1) pbxproj n'avait AUCUNE PBXResourcesBuildPhase — xcodegen 2.46.0 ignore la clé target resources: (repro minimal confirmé, no resources phase même avec spec correcte). (2) même avec la phase, actool dropait les 14 colorsets ('N unassigned children' warning) car générés SANS \'idiom\':\'universal\' (script gen_colorsets.py en était la cause). Résultat : pas de Assets.car dans l'app, toutes les couleurs asset-based (TextPrimary/TextSecondary/BgPrimary/BgSecondary/SeparatorColor...) invisibles.
**Décision/apprentissage** : Workaround : déclarer les resources dans sources avec buildPhase:resources — sources: - path: Resources/Assets.xcassets buildPhase: resources (idem Localizable.xcstrings). Retirer la clé resources: cassée. + ajouter \'idiom\':\'universal\' à chaque entrée colors[] de tous les .colorset/Contents.json. Vérifier par find .app -name Assets.car + assetutil --info. Effet secondaire : Localizable.xcstrings maintenant embarqué → locale fr active sur sim fr → ExifFormatterTests fileSize '4,2 Mo' pas '4.2 MB' → test assoupli (accepte MB|Mo).
**Pourquoi** : xcodegen 2.46.0 ignore target resources: ; actool exige idiom sur les couleurs ; vérif Assets.car sinon couleurs nil silencieuses.
**Fichiers concernés** : project.yml, ImmichSwiftUI.xcodeproj/project.pbxproj, Resources/Assets.xcassets/*.colorset/Contents.json (14 fichiers), Tests/ExifFormatterTests.swift

## [2026-07-31] Search UX + MapKit map markers — [tag: search mapkit geolocation]

**Contexte** : User demandé review UX search + intégration MapKit: carte de toutes les photos géolocalisées + photos dans une zone. 168 tests verts (baseline 153 + 15 nouveaux).
**Décision/apprentissage** : 1) Search: .searchable natif remplace custom TextField, recherche live débouncée 400ms via queryDidChange() (guard lastQueried contre double-search programmatique, searchGeneration contre stale in-flight après clear), clearSearch() reset state, RecentSearchesStore (UserDefaults, cap 8), compteur 'N photos', picker Metadata|Smart plié en Menu toolbar (défaut Smart), ViewMode + .map, loadMore sur onAppear dernier item au lieu de .task. 2) Map: GET /api/map/markers (1 marker/asset géolocalisé, {id,lat,lon,city,state,country}) → MapMarkerResponseDto; MapViewModel filtre markers par MKMapRect visible (debounce 300ms) → visiblePhotos; ClusteredMapView = UIViewRepresentable MKMapView + MKMarkerAnnotationView.clusteringIdentifier (SwiftUI Map iOS17 pas de clustering natif); photo strip 72pt en bas (thumb via asset id seul, pas de round-trip), tap → AssetDetailView. Marker id suffit pour thumbnail + detail fetch getAsset. Fit carte initial au premier load, pas après pan user (hasUserMoved).
**Pourquoi** : Pourquoi: Apple Photos-like. API serveur map/markers v1 stable (x-immich-history v1). Clustering réel requis >1000 markers. MVVM @Observable miroir conventions. Pièges: MKMapRectContainsCoordinate SUPPRIMÉ SDK Xcode 26 → rect.contains(MKMapPoint(coord)); deinit @MainActor class nonisolated → retirer cancellation task (VM durée de vie app).
**Fichiers concernés** : Sources/{Core/Types/MapDTOs,Features/Search/{MapView,MapViewModel,RecentSearchesStore}.swift NEW, Core/Constants, Core/Protocols/ImmichClient, Services/ImmichAPIClient, Features/Search/{SearchView,SearchViewModel}, DependencyContainer, RootView}.swift, Tests/{MapViewModelTests NEW, SearchViewModelTests, ImmichAPIClientTests, Mocks/MockImmichClient}

## [2026-07-31] Map perf culling+cache + auth persistence — [tag: map perf cache auth persistence]

**Contexte** : User feedback: strip photos overlay moche, carte 10-15s à charger, et relaunch app → perte auth serveur (401). 177 tests verts (168 + 9).
**Décision/apprentissage** : 1) Perf carte: cause = addAnnotations(TOUS les markers) + payload énorme. Fix: annotation culling — MapViewModel.filterVisible scan unique → visibleAnnotations (rect expandé margin 0.5) + visiblePhotos (rect exact); ClusteredMapView ne reçoit que le sous-ensemble cullé (diff add/remove, plus jamais remove-all/add-all); fit initial une fois (didFitInitial) + force onVisibleRectChanged post-fit; MapMarkerCache (UserDefaults JSON, JSONEncoder.immich) → loadMarkers sert cache instantané puis refresh arrière-plan silencieux (échec garde cache); map immédiate + chip 'Loading photos…' (fini full-screen spinner). 2) Sheet photos: ZStack strip → .sheet detents [.height(140), .medium] + presentationBackgroundInteraction(.enabled(upThrough:.medium)) + regularMaterial + cornerRadius PVRadius.lg; MapPhotosSheet (NavigationStack, header lieu+count, LazyHStack thumbs 96pt PVRadius.md), isPresented suit !visiblePhotos.isEmpty. 3) Auth persistence: ROOT CAUSE = serverURLString jamais persisté + client.configure() seulement appelé dans login/connectServer → relaunch: isAuthenticated true (token keychain) mais client non configuré → toutes requêtes jettent .unauthorized local (ImmichAPIClient sendAuthedRaw guard token). Fix: persist serverURL+userEmail/userName/userId (UserDefaults, keys static internal testables, serverURL conservé au logout/reset); restoreSession() configure client + validateToken (unauthorized→resetSession, network→garde session offline-safe); RootView gate isRestoringSession (ProgressView) + .task restoreSession.
**Pourquoi** : Pourquoi: Apple Maps style sheet + culling = seul moyen de rendre 100k markers (SwiftUI Map iOS17 pas de clustering, addAnnotations massif = freeze). Offline-safe restore évite wipe token au démarrage sans réseau. Piège: MKMapPoint.x ≈ 745654 units/degré long (projection Mercator), pas km — tests culling avec Δlon précis; UserDefaults.standard pollué entre tests → MapViewModelTests injecte suite isolée par test.
**Fichiers concernés** : Sources/Features/Search/{MapMarkerCache NEW,MapViewModel,MapView}.swift, Sources/Features/Auth/AuthViewModel.swift, Sources/RootView.swift, Tests/{MapViewModelTests,AuthViewModelTests}.swift, Tests/Mocks/MockImmichClient.swift (validateError)

## [2026-07-31] Timeline Photos-app grid — pinch-zoom 2-7 cols + radius 4pt + logout retiré — [tag: timeline photos-app grid zoom gesture]

**Contexte** : User a demandé timeline façon app Photos iOS : grille redimensionnable par pinch-to-zoom, cellules carrées radius comme Photos natif, suppression du bouton logout en haut à droite.
**Décision/apprentissage** : 1) Logout: Menu person.circle supprimé du toolbar TimelineView (l'accès reste dans l'onglet Moi/ProfileView:40). Toolbar normal-mode = principal wordmark seul (comme Photos). 2) Pinch-zoom: `.simultaneousGesture(MagnifyGesture())` sur le ScrollView (iOS17 API, ne bloque ni tap ni long-press ni refreshable). Modèle: columnCount = round(defaultColumns / effectiveScale), default=3, clamp 2..7. `gridScale` commit sur onEnded → zoom persiste entre gestes (Photos behavior); onChanged lit base*gridScale*magnification SANS committer (évite double-count du magnification cumulatif). Mapping inverse scale↔colonnes extrait en enum pure `TimelineGridZoom` (Sources/Features/Timeline/TimelineGridZoom.swift NEW, pattern TimelineSectionBuilder) : effectiveScale clamp dans [3/7, 3/2], columns() round+clamp, scale(forColumnCount:) inversé. 11 tests (Tests/TimelineGridZoomTests.swift NEW). 3) Cells: radius PVRadius.none→xs (4pt, choisi vs sm 8pt = fidélité Photos natif) sur AssetThumbnailCell.clipShape ET SkeletonCell (fill+mask). Grid spacing 0→PVSpacing.s2 (row + column), SkeletonShimmerGrid synchro columnCount. Cells déjà carrées aspectRatio(1)+clip (inchangé). Grid: spacing 0→s2.
**Pourquoi** : Photos iOS pinche en continu reflow live colonnes (pas d'animation pendant geste = responsive); zoom persiste entre gestes. Radius 4pt validé par user (option 8pt écartée). Logout gardé accessible via Moi. Aucune logique VM touchée (View-layer only).
**Fichiers concernés** : Sources/Features/Timeline/{TimelineView,AssetThumbnailCell,TimelineGridZoom NEW}.swift, Tests/TimelineGridZoomTests.swift NEW, xcodegen régénéré (identity préservée). 188 tests verts (177+11).

## [2026-07-31] Timeline top bar + day header — Photos style — [tag: timeline photos-app navbar header]

**Contexte** : User : jour affiché 'really ugly' (barres material), immich top bar 'ugly'. Voulait Photos natif : jour seul en haut-gauche sous le mois, sans barres.
**Décision/apprentissage** : 1) ImmichAppBar supprimé du principal toolbar TimelineView (ToolbarItem .principal DELETED) — user a choisi AUCUN titre (pas 'Photos', pas 'Bibliothèque'). navigationTitle vide normalement, 'N selected' inline en mode sélection (Photos behavior). Les autres tabs (Search/Albums/Trash/Backup) gardent ImmichAppBar. 2) TimelineSectionHeader redesigned: .background(.regularMaterial)→Color.bgPrimary OPAQUE (même fond que page — tue la barre visible MAIS couvre les cellules qui glissent SOUS le header épinglé; material aurait fait barre), .pvHeadline→.pvSubhead, padding horizontal s24→s4 (alignement grille), vertical s8→s4. Header reste épinglé (pinnedViews .sectionHeaders) = 'jour courant en haut-gauche sous le mois'. Format date (Today/Yesterday/EEEE MMMM d) inchangé — DateHeaderFormatter + tests intacts.
**Pourquoi** : Photos iOS : header sticky jour = texte petit plain sans barre. bg opaque (pas material) = seul moyen propre de cacher le scroll sous le pin SANS lire comme une barre. Aucune logique VM/builder touchée. 188 tests verts, build clean (warnings pré-existants main-actor Swift6/deprecation dayGroup tuple non touchés).
**Fichiers concernés** : Sources/Features/Timeline/TimelineView.swift (toolbar principal + TimelineSectionHeader). Pas de nouveau fichier (pas de xcodegen).

## [2026-07-31] Timeline pinned month-year + day header — no banner, no grey bg — [tag: timeline photos-app month day header]

**Contexte** : User : en haut-gauche 'month year' et dessous 'the current day' dans la police et couleur du mois/année juste plus petit, sans fond gris.
**Décision/apprentissage** : 1) MonthYearBanner SUPPRIMÉ (fichier deleted) — user a choisi de le retirer (vs le garder) pour éviter doublon 'July 2026' (banner scrollant + header épinglé). TimelineSectionBuilder inchangé (émet toujours .monthHeader, mais TimelineView rend EmptyView pour ce case — builder tests intacts). 2) TimelineSectionHeader devient VStack(alignment:.leading, spacing s2): Text(monthLabel) .pvTitle + Text(label) .pvSubhead, les DEUX textPrimaryPV (day = même couleur que mois, taille plus petite). Background Color.bgPrimary SUPPRIMÉ → plus de barre grise, cellules glissent sous le texte épinglé (comportement Photos). Padding horizontal s4/vertical s4 conservé. 3) NEW DateHeaderFormatter.monthYearString(for:calendar:) — réutilise parseUTCPrefix, format 'MMMM yyyy', fallback raw string. 3 tests ajoutés (month+year, jour ignoré, malformed). 4) xcodegen régénéré (file deleted). 191 tests verts (188+3).
**Pourquoi** : Photos iOS : month-year épinglé gros + jour dessous plus petit même couleur. User voulait explicitement PAS de fond. Header épinglé = month-year toujours visible en scroll.
**Fichiers concernés** : Sources/Features/Timeline/{DateHeaderFormatter,TimelineView}.swift, Tests/DateHeaderFormatterTests.swift; Sources/Features/Timeline/MonthYearBanner.swift DELETED; xcodegen régénéré.

## [2026-07-31] Timeline sticky month+day — one pinned, grids-only — [tag: timeline pinned header overlay preference]

**Contexte** : User : 'Pin the month only one time not month year and day under, each day. change the month when the month change and change the day only when the day change.' + 'don't keep small label above each day grid'. Bug = chaque jour-section répétait 'July 2026' + day → mois dupliqué en scroll.
**Décision/apprentissage** : PinnedViews .sectionHeaders ABANDONNÉ. TimelineSectionHeader SUPPRIMÉ (plus de labels par jour dans le contenu — grilles seules, spacing s8 entre jours). Header sticky = safeAreaInset(edge:.top) sur le ScrollView (réserve l'espace layout → AUCUN overlap, aucun fond nécessaire, zéro bg gris) : VStack Text(monthYear) .pvTitle + Text(day) .pvSubhead, les deux textPrimaryPV, caché en selectionMode. Data: chaque day-group LazyVGrid mesure son minY via .background(GeometryReader) → PinnedDayPreferenceKey [day:CGFloat] (coordinateSpace .named 'timeline' sur ScrollView) → onPreferenceChange → pinnedDay = PinnedHeaderResolver.currentDay(frames) → monthYearString + displayString dérivés de pinnedDay. NEW PinnedHeaderResolver (enum pure, pattern TimelineGridZoom): currentDay = largest minY parmi frames <= 0 (plus récent groupe scrolled past top), sinon smallest minY (topmost visible), nil si vide. Month string constant dans un mois → ne flippe qu'aux frontières de mois; day flippe par jour. 6 tests (Tests/PinnedHeaderResolverTests.swift NEW — piège: littéraux dict doivent être CGFloat explicites sinon Int). Builder inchangé (.monthHeader→EmptyView). 197 tests verts (191+6).
**Pourquoi** : Photos iOS : UN SEUL mois+jour épinglés, contenu = grilles pures. safeAreaInset > background opaque = pas de bande. Resolver pur testable.
**Fichiers concernés** : Sources/Features/Timeline/{PinnedHeaderResolver NEW,TimelineView}.swift, Tests/PinnedHeaderResolverTests.swift NEW, xcodegen régénéré.

## [2026-07-31] Timeline continuous grid + floating white header — [tag: timeline continuous grid floating header]

**Contexte** : User : 'all rows must be full' (= derniere ligne d'un jour avait des cellules vides → veut flux continu), 'day label more bolder', 'put the first row of photos under month year day labels' + 'labels in white because of contrasts'. User a confirmé (question tool): header flotte SUR les photos (style Photos, texte blanc + shadow), pas de réserve d'espace.
**Décision/apprentissage** : 1) CONTINUOUS GRID: fin des LazyVGrid par jour (repartait les lignes → cellules vides en fin de jour). UN seul LazyVGrid englobe ForEach(timelineSections); .dayGroup émet ses items directement (ForEach(Array(group.items.enumerated()), id:\.element.id)) → photos coulent sans interruption, toutes les lignes pleines. Spacing inter-jours uniforme s2. 2) DAY BOUNDARY: le GeometryReader preference est passé du LazyVGrid du jour au PREMIER item de chaque jour (index == 0) → PinnedDayPreferenceKey [day: minY]. Resolver inchangé (règle max minY<=0 sinon min minY), 6 tests OK — MAIS test tie réécrit (ordre dict non garanti → assert membership au lieu de key précise). 3) HEADER FLOTTANT: safeAreaInset → .overlay(alignment:.topLeading) sur ScrollView: month .pvTitle + day .pvSubhead.weight(.bold), LES DEUX Color.white + .shadow(black 0.35, r2, y1) (DS-exempt contraste sur photos), padding h s4 / top s8 / bottom s4. Caché en selectionMode. Première rangée de photos visible SOUS les labels (overlap, pas réservé). 4) MONTH CAPITALIZED: DateHeaderFormatter.monthYearString → uppercase première lettre seulement (guard first + String(first).uppercased() + dropFirst()), certains locales (fr_FR 'juillet') émettent minuscules. Test fr_FR 'Juillet 2026' ajouté. 198 tests verts (197+1). Build clean.
**Pourquoi** : Photos iOS = grid continu (pas de trou en fin de jour) + header blanc qui flotte avec ombre pour lisibilité sur photos. Rows vides = signature d'un grid restart par jour.
**Fichiers concernés** : Sources/Features/Timeline/{TimelineView,DateHeaderFormatter}.swift, Tests/{DateHeaderFormatterTests,PinnedHeaderResolverTests}.swift. Pas de nouveau fichier (pas de xcodegen).

## [2026-07-31] Timeline header = year + day-month, more left space — [tag: timeline year day header]

**Contexte** : User : 'instead of month year and day under. Put the year and under day number and month. don't put the day of the week. keep the first letter of the mounth in capital' + 'add more space between left border and labels'.
**Décision/apprentissage** : 1) Header flottant = ANNÉE .pvTitle + 'd MMMM' .pvSubhead.bold dessous (LES DEUX blanc + shadow). PAS de weekday, PAS de Today/Yesterday (user a confirmé 'Always day+month' via question tool). 2) DateHeaderFormatter: monthYearString REMPLACÉ par yearString (dateFormat 'yyyy') + dayMonthString ('d' + 'MMMM' séparés, capitalize première lettre du mois via helper privé capitalized() — fr_FR 'juillet'→'Juillet'). displayString CONSERVÉ (utilisé par TrashView:135). 3) Padding header: .padding(.horizontal s4) → .leading s16 (espacement gauche + grand), trailing s4. Grid cells restent s4. 200 tests verts (198-3+5). Build clean.
**Pourquoi** : User voulait layout Photos alternatif: année dominante + jour mois en petit, sans weekday. capitalize helper réutilisé.
**Fichiers concernés** : Sources/Features/Timeline/{DateHeaderFormatter,TimelineView}.swift, Tests/DateHeaderFormatterTests.swift. Pas de nouveau fichier.

## [2026-07-31] Timeline day label + weekday capitalized — [tag: timeline weekday header]

**Contexte** : User : 'add the day of the week with the first letter in capital'.
**Décision/apprentissage** : dayMonthString passe de 'd MMMM' ('29 July') à 'EEEE d MMMM' ('Wednesday 29 July'). Capitalize SÉPARÉMENT weekday ET month (helper capitalized() appliqué aux deux — pas la string entière, car le 'd' numérique au milieu serait cassé). fr_FR: 'Mercredi 29 Juillet' (mercredi + juillet minuscules → capitalisés). Tests mis à jour. 200 tests verts.
**Pourquoi** : 'EEEE d MMMM' avec capitalisation token par token (weekday + month), jour numérique intact.
**Fichiers concernés** : Sources/Features/Timeline/DateHeaderFormatter.swift, Tests/DateHeaderFormatterTests.swift.

## [2026-08-03] Photo viewer Photos iOS 26 + share sheet (albums partagés + lien public) — [tag: photoviewer liquidglass partage shared-album]

**Contexte** : Contexte : user veut la visionneuse de l'app Photos iOS (tap n'importe quelle photo partout → plein écran). Après 3 itérations : chrome verre, filmstrip, puis redesign du bottom sheet partage. Baseline 200 tests, 214 après ajouts.
**Décision/apprentissage** : Décision : PhotoViewer.swift (Sources/Features/PhotoViewer/) auto-suffisant : favori/delete/share/edit via le client partagé + callback onDataChanged par surface (Album load()/Search search()/Map reload()) ; callbacks VM Timeline/Trash conservés quand fournis (mise à jour en place, pas de re-fetch). Layout Photos : top bar verre glassEffect(.regular, in: Circle()) (chevron.left | capsule lieu(city??country)+date | info), photo fullsize .fit centrée (.frame(width:proxy.size) fixe GeometryReader topLeading + pager .ignoresSafeArea), filmstrip ratio natif (h56, largeur=56*aspectRatio clampé 28..88, ScrollPosition), bottom (share | capsule favori+edit | trash seul). Trash adapté : restore + deletePermanent, pas de share. Share sheet 1/3 écran : header (share natif UIActivityViewController([UIImage]) téléchargé .fullsize | titre Partager | xmark), section 'Share with other users' (create album partagé w/ users OU add to shared album existant via albums.shared), section 'Public link' (toggles allowDownload/showMetadata + createSharedLink type .individual + copie). Nouveau PhotoShareViewModel (@Observable @MainActor testable, load users+albums indépendamment). API : getUsers() GET /api/users (ImmichAPI.users), AlbumUserRole(EDITOR/VIEWER)/AlbumUserDto, CreateAlbumDto.albumUsers. Filmstrip + PhotoShareSheet + AvatarCircle(hex avatarColor) + ActivityPresenter en sous-vues privées de PhotoViewer.swift.
**Pourquoi** : Pourquoi : fidélité Photos iOS 26 (Liquid Glass natif, filmstrip ratio, centre écran vrai), uniformité des actions sur les 5 surfaces sans étendre Album/Search/Map VMs (fallback auto-suffisant), testabilité MVVM. Piège : GET /api/users peut être admin-only (section users état vide, load indépendant), albumUsers requiert Immich ≥1.109.
**Fichiers concernés** : Sources/Features/PhotoViewer/{PhotoViewer,ZoomableImageView,PhotoShareViewModel}.swift, Sources/Core/Types/DTOs+Album.swift, Sources/Core/Constants.swift, Sources/Core/Protocols/ImmichClient.swift, Sources/Services/ImmichAPIClient.swift, TimelineView/TrashView/AlbumDetailView/SearchView/MapView (.photoViewer), Tests/Mocks/MockImmichClient.swift, Tests/PhotoShareViewModelTests.swift, Tests/{DTOEncodingTests,ImmichAPIClientTests}.swift, Sources/Services/AuthenticatedAsyncImage.swift (contentMode param)

## [2026-08-03] Piège Swift : let avec valeur par défaut exclu du memberwise init — [tag: swift piège memberwise dto]

**Contexte** : Contexte : ajout de `albumUsers` à CreateAlbumDto avec `let albumUsers: [AlbumUserDto]? = nil` → build error 'extra argument albumUsers' au call CreateAlbumDto(albumName:description:assetIds:albumUsers:).
**Décision/apprentissage** : Décision/apprentissage : le memberwise init d'un `let` avec valeur par défaut NE prend PAS de paramètre (propriété non-réassignable, valeur figée). Un `var x: T? = nil` le prend en paramètre defaulté ET reste omis du JSON quand nil (synthesized Codable encodeIfPresent).
**Pourquoi** : Pourquoi : garder le memberwise init compatible (CreateAlbumSheet) + champ optionnel du wire.
**Fichiers concernés** : Sources/Core/Types/DTOs+Album.swift (CreateAlbumDto.albumUsers en var)

## [2026-08-05] Crash SheetBridge map — sheet flapping + reload churn — [tag: sheetbridge]

**Contexte** : Crash EXC_BREAKPOINT SheetBridge.presenter lors de dealloc hosting view de la bottom sheet MapSegmentView (recherche par carte). Causes: (1) onChange(visiblePhotos.isEmpty) auto-dismiss+re-present à chaque pan (debounce 250ms) pendant la transition de dismissal; (2) reload() vidait visiblePhotos → delete dans le viewer fullScreenCover (commit 49d3a03) → dismissal de sheet pendant fullScreenCover présentée.
**Décision/apprentissage** : Sheet de la map = sticky: présentation one-shot (guard !isPhotosSheetPresented), jamais d'auto-dismiss (swipe-down utilisateur). reload() préserve visiblePhotos/visibleAnnotations + re-filtre sur lastRect après refetch. Empty state dans MapPhotosSheet pour region sans photo.
**Pourquoi** : SwiftUI piège: présentations imbriquées (sheet + fullScreenCover) + binding piloté par données live = invariant SheetBridge violé pendant teardown. Toujours présent one-shot et jamais dismiss programmatique pendant qu'une autre présentation est active.
**Fichiers concernés** : Sources/Features/Search/MapView.swift, Sources/Features/Search/MapViewModel.swift

## [2026-08-05] Crash SheetBridge map — VRAIE cause racine: présentateur éphémère + race cover — [tag: sheetbridge]

**Contexte** : Le crash SheetBridge.presenter persistait après le fix sticky/flapping. Cause réelle: la sheet map était présentée depuis MapSegmentView, vue éphémère dans la fullScreenCover search. Map charge longtemps (réseau) → onChange visiblePhotos présente la sheet TARDIVEMENT → race avec le swipe-down de la cover par l'utilisateur: soit crash (dismiss cover pendant présentation, MapSegmentView dealloc avec sheet) soit timeline+bottom sheet (cover meurt avant la présentation, sheet en vol s'affiche sur la timeline).
**Décision/apprentissage** : La sheet map est désormais présentée depuis RootView (présentateur stable, attachée APRÈS la fullScreenCover → z-order au-dessus), pilotée par vm.isPhotoSheetPresented (prop observable MapViewModel). Présentation différée d'un runloop + guard isAppeared (onAppear/onDisappear de MapSegmentView) pour annuler toute présentation pendant un dismissal de cover. onDisappear segment + onDismiss cover ferment la sheet proprement.
**Pourquoi** : Règle: ne JAMAIS présenter de sheet depuis une vue qui peut être retirée de la hiérarchie pendant la transition (vue conditionnelle, contenu de cover). Présentation = objet stable (RootView/VM). Auto-présentation déclenchée par des données chargées tardivement = toujours différer + guard visibilité.
**Fichiers concernés** : Sources/RootView.swift, Sources/Features/Search/MapView.swift, Sources/Features/Search/MapViewModel.swift

## [2026-08-05] Fix map: boucle onDisappear sheet + cache vidé par reload — [tag: sheetbridge]

**Contexte** : Après le hoist RootView: (1) aucune bottom sheet ne s'ouvrait — le onDisappear de MapSegmentView (présentation de la sheet au-dessus de la cover déclenche onDisappear sur le contenu de la cover) fermait la sheet dès qu'elle s'ouvrait, boucle. (2) map 10s à chaque ouverture — reload() (appelé par onDataChanged du viewer après mutation) vidait le cache disque à chaque fois.
**Décision/apprentissage** : Sheet: binding RootView gaté get: { showSearch && map.isPhotoSheetPresented } — la sheet est structurellement impossible sans la cover, dismissal propre sans crash. Plus AUCUNE logique onDisappear/onAppear dans MapSegmentView (vue éphémère). Fermeture mode switch → SearchView.onChange(viewMode). Refresh: refreshMarkers() public (fetch → markers → cache.save → refilter, sans clear) remplace reload() pour les mutations viewer. Tooltip 'Loading photos…' = if vm.isLoading (visible aussi pendant refresh cache).
**Pourquoi** : Piège SwiftUI: présenter une sheet/fullScreenCover au-dessus d'une autre présentation déclenche onDisappear sur le contenu recouvert — ne JAMAIS mettre de logique de dismissal dans onDisappear d'une vue sous une présentation. Toujours garder le cache si on peut servir stale + refresh silencieux.
**Fichiers concernés** : Sources/RootView.swift, Sources/Features/Search/MapView.swift, Sources/Features/Search/MapViewModel.swift, Sources/Features/Search/SearchView.swift

## [2026-08-05] Map: panneau intégré au lieu de sheet native — [tag: sheetbridge]

**Contexte** : La sheet native au-dessus de la fullScreenCover search est IMPOSSIBLE: SwiftUI sérialise les présentations du même présentateur ('only presenting a single sheet is supported' — la sheet attend la dismissal de la cover, ne s'affiche jamais, rend en taille 0: warnings CAMetalLayer/clip empty path). La sheet depuis le contenu de la cover crash au teardown (SheetBridge).
**Décision/apprentissage** : MapPhotosPanel: panneau overlay intégré dans le ZStack de MapSegmentView (GeometryReader height/3, regularMaterial, chevron.down toggle). Zéro présentation native → zéro conflit, zéro SheetBridge. Tooltip 'Chargement des photos…' piloté par @State local isLoadingPhotos (re-render garanti, contrairement à l'observation du VM) autour de await loadMarkers().
**Pourquoi** : Règle: iOS 26 sérialise les présentations — sheet + fullScreenCover depuis le même présentateur = la sheet attend la cover. Pour un panneau au-dessus d'une cover: overlay intégré, pas de sheet. Spinner de chargement: toujours état local @State, jamais dépendre de l'observation d'un @Observable pour un overlay.
**Fichiers concernés** : Sources/Features/Search/MapView.swift, Sources/RootView.swift, Sources/Features/Search/SearchView.swift, Sources/Features/Search/MapViewModel.swift

## [2026-08-05] Map: panneau bord-à-bord + refresh non-bloquant — [tag: map]

**Contexte** : Panneau tronqué: le ZStack de mapContent n'avait pas ignoresSafeArea(bottom) → s'arrêtait au safe area (home indicator), paddings horizontal/bottom 8 créaient un look carte flottante. 12s perçu: loadMarkers cache path await refreshMarkers() (réseau 12s) bloquait le spinner local isLoadingPhotos → spinner 12s même avec cache servi.
**Décision/apprentissage** : mapContent ZStack: .ignoresSafeArea(edges: .bottom) + suppression des paddings du panel → bord à bord jusqu'au bas (la cover est fullscreen, pas de tab bar). Cache path: Task { await refreshMarkers() } fire-and-forget → loadMarkers retourne dès le cache rendu, spinner bref, refresh silencieux en fond. Test adapté (sleep 50ms avant assertion requestCount).
**Pourquoi** : Spinner de chargement piloté par await d'un réseau lent = spinner menteur. Toujours retourner dès les données locales dispo et rafraîchir en fire-and-forget.
**Fichiers concernés** : Sources/Features/Search/MapView.swift, Sources/Features/Search/MapViewModel.swift, Tests/MapViewModelTests.swift

## [2026-08-05] Map: batching annotations + spinner couvrant le rendu MapKit — [tag: map]

**Contexte** : Diagnostic via logs [MapVM]: cache HIT 10696 markers → le 12s n'était PAS le réseau mais le RENDU: addAnnotations(10696) en une fois bloque le main thread ~12s (simulateur). Le spinner s'éteignait dès markers non vide → rien ne couvrait le rendu. Doc MapKit (via Xcode): pas de batching documenté; mapView(_:didAdd:) documenté comme signal d'ajout des vues.
**Décision/apprentissage** : ClusteredMapView: addAnnotations par paquets de 1000 via DispatchQueue.main.async séquentiels + token UUID d'annulation dans le Coordinator (updateUIView re-diff + nouveau token invalide les batchs en vol). Spinner: onInitialRenderCompleted callback (via didAdd documenté OU immédiat si diff vide) → isRenderingMarkers @State éteint le tooltip. Condition spinner: ((isLoadingPhotos || vm.isLoading) && vm.markers.isEmpty) || isRenderingMarkers. Panel: sheet look natif = frame + ignoresSafeArea(bottom) + UnevenRoundedRectangle top 36 (bas droit au ras), PAS de padding (le padding 8 + radius 24 créait l'effet 'carré/tronqué').
**Pourquoi** : Pattern: ingestion en masse de données dans une API UIKit = toujours batcher pour laisser le runloop respirer. Spinner piloté par les DEUX phases (fetch + rendu) sinon il ment.
**Fichiers concernés** : Sources/Features/Search/MapView.swift

## [2026-08-05] Map: bloc complet + sheet paginée + carte flottante — [tag: map]

**Contexte** : Retours UX: vagues de marqueurs pas ouf (batching rejeté), sheet tronquée en bas, warning 'Modifying state during view update'. Fix: retour à addAnnotations complet d'un bloc (spinner isRenderingMarkers couvre l'ingestion, didAdd signale la fin — callbacks @State différés via DispatchQueue.main.async pour éviter le warning). MapPhotosPanel: photoLimit 15 initial + +30 au scroll (onAppear dernier item) + reset à 15 sur onChange(visiblePhotos) — les vignettes se fetchent lazy. Panel: carte flottante = frame + padding horizontal 12 + bottom 12 + RoundedRectangle 24, SANS ignoresSafeArea (la troncature basse venait du panel collé au bord via ignoresSafeArea).
**Décision/apprentissage** : Ingestion massif MapKit: bloc complet + spinner honnête > vagues. Sheet avec gros datasets: windowing (prefix + step au scroll). Jamais de set @State synchrone dans un callback de UIViewRepresentable pendant le cycle de rendu.
**Pourquoi** : Sources/Features/Search/MapView.swift
**Fichiers concernés** : non précisés

## [2026-08-05] Refacto: tab search réel + sheet map native + subsampling annotations — [tag: sheetbridge]

**Contexte** : Refacto accepté: la search quitte la fullScreenCover → vrai onglet TabView (le bubble sur Photos atterrit sur le tab search, les autres tabs gardent leurs actions contextuelles + snap back). La sheet map native (detents 1/3+.medium, presentationBackgroundInteraction) est présentée par RootView au-dessus du tab — seule présentation active pendant la map → plus de conflit 'single sheet', plus de crash SheetBridge (plus de cover à teardown). Changement d'onglet → onChange(selection) ferme la sheet. PERFORMANCE: le 12s = ingestion MapKit de 10696 annotations au zoom monde → subsampling par grille 44×44 dans filterVisible (1 marker/cellule, ~1900 max au monde; zoom → grille plus fine → tous les markers de la région). visiblePhotos reste COMPLET (sheet paginée 15+30). LEÇON: MKMapPoint en Mercator — à lat 49°, 1° ≈ 1.13M unités y (pas 111k) — les tests de géométrie doivent tenir compte de la distorsion.
**Décision/apprentissage** : iOS 26 sérialise les présentations: sheet au-dessus d'une cover du même présentateur = file d'attente invisible. Sheet dans le contenu d'une cover = crash au teardown. SEULE solution sheet native: présenter depuis un conteneur stable (TabView root) sans autre présentation active. Subsampling par grille = la vraie réponse aux librairies de 10k+ marqueurs (clustering visuel identique au monde, ingestion bornée).
**Pourquoi** : Sources/RootView.swift, Sources/Features/Search/MapView.swift, Sources/Features/Search/MapViewModel.swift, Tests/MapViewModelTests.swift
**Fichiers concernés** : non précisés

## [2026-08-05] Map: badges marqueurs = vrais comptes photos — [tag: map]

**Contexte** : Après subsampling: la somme des chiffres des clusters (memberAnnotations.count = annotations subsamplées) ≠ total de la sheet (visiblePhotos complet). Fix: chaque annotation porte representedCount = nombre de markers de sa cellule dans la région (MapAnnotationMarker{photo, representedCount}); clusters = somme des representedCount des membres; annotation individuelle count>1 → badge chiffre (mini-cluster), count 1 → icône photo. Somme des badges = visiblePhotos.count EXACTEMENT (propriété testée). Piège implémentation: les markers de la marge (expanded) doivent être traités APRÈS ceux de la rect pour ne pas voler le badge d'une cellule mixte.
**Décision/apprentissage** : Subsampling + badges réels: le user doit pouvoir additionner les chiffres visibles et retrouver le total de la sheet.
**Pourquoi** : Sources/Features/Search/MapViewModel.swift, Sources/Features/Search/MapView.swift, Tests/MapViewModelTests.swift
**Fichiers concernés** : non précisés

## [2026-08-05] Map: suppression marge de culling → badges exacts à tout zoom — [tag: map]

**Contexte** : Au zoom, marqueurs/clusters à 0 : la marge (cullMargin 0.5) affichait les markers de la région élargie avec representedCount 0 (hors rect exacte → pas dans la sheet). Fix : annotations = EXACTEMENT les markers de la rect visible (marge supprimée) → chaque badge count >= 1, somme des badges = visiblePhotos.count à tout zoom, aucun 0. Test 'expanded_annotations_include_margin' supprimé. Pan : marqueurs aux bords avec debounce 250ms (acceptable).
**Décision/apprentissage** : Cohérence badge/sheet stricte = annotations identiques à visiblePhotos. Une marge d'affichage détruit l'invariant somme=total.
**Pourquoi** : Sources/Features/Search/MapViewModel.swift, Tests/MapViewModelTests.swift
**Fichiers concernés** : non précisés

## [2026-08-05] Map: sélection marqueur → sheet filtrée sur sa cellule — [tag: map]

**Contexte** : Feature: tap marqueur → la bottom sheet n'affiche que les photos de sa cellule (subsampling); tap ailleurs (didDeselect) ou bouton × dans la sheet → retour aux photos de l'area. Tap cluster → zoom Maps-style sur la région des membres (setVisibleMapRect + padding, la sheet suit via le flux region existant). VM: photoCells [CellKey:[MapPhoto]] + cellOfPhotoID [id:CellKey] remplis par filterVisible; selectMarker(id)/deselectMarker(); désélection auto si le marqueur quitte la région (refilter). Sheet: displayedPhotos = selected ? cell : region; placeName préfère le marqueur; pagination reset sur displayedPhotos; viewer page sur displayedPhotos.
**Décision/apprentissage** : Sélection d'annotation: toujours passer par le VM (observable) et gérer la désélection native MapKit (didDeselect). Le cluster tap = zoom (jamais filtrer 10696 photos).
**Pourquoi** : Sources/Features/Search/MapViewModel.swift, Sources/Features/Search/MapView.swift, Tests/MapViewModelTests.swift
**Fichiers concernés** : non précisés

## [2026-08-07] Timeline perf — DateFormatter per-render + pipeline en body — [tag: timeline,performance,pitfall,audit]

**Contexte** : Audit read-only (`docs/audit-2026-08.md`) a confirmé deux points chauds sur grosse bibliothèque. (1) `TimelineView.timelineSections` (`TimelineView.swift:316-318`) est une propriété calculée dans `body` → recomputée à chaque changement d'état (tick sélection, scroll-to-top, etc.) ; elle appelle `TimelineSectionBuilder.build(from: vm.groupedByDay)`. (2) `vm.groupedByDay` (`TimelineViewModel.swift:162-170`) est lui-même un `Dictionary(grouping:)` + 2 sorts (O(n log n)) par accès. (3) `build(...)` alloue un `ISO8601DateFormatter` ET un `DateFormatter` à chaque appel (`TimelineSectionBuilder.swift:52,57`). L'ancien commentaire source disait "cheap (linear scan)" — c'était faux (le scan est linéaire, mais les allocations de formatters ne le sont pas). Le commentaire a été corrigé le 2026-08-07 ; le code n'a pas bougé.
**Décision/apprentissage** : Pas de fix code dans ce passe (audit doc-only). Les leviers identifiés pour un futur fix : (a) mémoïser `groupedByDay` + `timelineSections` (recompute sur changement de `items`, pas par body) — plus gros gain grosse bibliothèque ; (b) hoister tous les `DateFormatter`/`ISO8601DateFormatter` en `static let` (ou un helper partagé — `PhotoInfoPanel.dateLabel` et `PhotoViewer.headerDate` sont byte-pour-byte identiques, cible de dédup évidente). Mêmes patterns per-call à `PhotoInfoPanel.swift:136,140`, `PhotoViewer.swift:787,791`, `DateHeaderFormatter.swift:69,88,93,98,113,134`.
**Pourquoi** : `docs/audit-2026-08.md` §2 P1/P2 (+ §0.1 re-vérification : tous deux STILL VALID, aucun fixé dans les fichiers modifiés).
**Fichiers concernés** : Sources/Features/Timeline/TimelineView.swift, Sources/Features/Timeline/TimelineViewModel.swift, Sources/Features/Timeline/TimelineSectionBuilder.swift, Sources/Features/Timeline/DateHeaderFormatter.swift, Sources/Features/PhotoViewer/PhotoInfoPanel.swift, Sources/Features/PhotoViewer/PhotoViewer.swift

## [2026-08-12] P0 api-surface-expansion — API client étendu (16 méthodes) — [tag: feature,api]

**Contexte** : Carte P0 du programme feature-parity (docs/feature-parity-plan.md). Surface client passée de ~25 à 41 méthodes. Nouveaux fichiers DTO par domaine: DTOs+People.swift (PersonResponseDto COMPLET {id,name,birthDate,thumbnailPath,isHidden + color,isFavorite,updatedAt} — remplace la version stale qui était dans DTOs.swift:172; PeopleResponseDto{people,hidden,total,hasNextPage?}; PersonUpdateDto; MergePersonDto; PersonStatisticsResponseDto; PartnerResponseDto{...+inTimeline}; PartnerUpdateDto) — DTOs+Social.swift (ReactionType comment|like; ActivityCreateDto{albumId,type REQ}; ActivityResponseDto{assetId REQUIRED}; MemoryType on_this_day; OnThisDayDto{year}; MemoryResponseDto; DuplicateResponseDto{duplicateId,assets,suggestedKeepAssetIds}) — DTOs+Server.swift (ServerStatsResponseDto{photos,videos,usage,usagePhotos,usageVideos,usageByUser}; UsageByUserDto{...quotaSizeInBytes}; SharedLinkEditDto{tous optionnels}). AssetBulkUpdateDto dans DTOs.swift:223 (ids REQ + visibility/isFavorite/latitude/longitude/rating/description/timeZone/duplicateId/dateTimeOriginal/dateTimeRelative; PAS de isArchived — archive = visibility:"archive"). Constants.swift: groupes partners/activity/memories/duplicates.
**Décision/apprentissage** : (1) MERGE /people/{id}/merge est POST pas PUT (vérifié OpenAPI main). (2) /people/{id}/assets N'EXISTE PLUS sur main — assets d'une personne = searchMetadata(personIds:). (3) Archive = AssetBulkUpdateDto.visibility:"archive" via PUT /assets → 204. (4) getTimeBuckets/getTimeBucket gagnent personId/withPartners/visibility/withStacked (optionnels, rétro-compatible; use-case people/partners/archive P1-P3). (5) SharedLinkResponseDto.type non-optionnel → mock updateSharedLink doit passer .album. (6) pbxproj = références EXPLICITES : xcodegen generate OBLIGATOIRE après ajout de fichier (les globs project.yml ne sync pas automatiquement). (7) Champs réponse mockables = `var` pas `let` (pattern AssetResponseDto); les checks AC-800/804 du card corrigés en conséquence. (8) Piège grep card: patterns -F vs regex + noms de tests réels (test_P0_*).
**Pourquoi** : Carte .opencode/scratch/api-surface-expansion.acceptance.md (AC-800..AC-811 PASS). Suite complète: 326 tests verts (0 échec) vs baseline ~214 — +112 tests (10 endpoints ImmichAPIClientTests + 9 roundtrips DTOEncodingTests + reste).
**Fichiers concernés** : Sources/Core/Types/DTOs+People.swift, DTOs+Social.swift, DTOs+Server.swift, Sources/Core/Types/DTOs.swift, Sources/Core/Constants.swift, Sources/Core/Protocols/ImmichClient.swift, Sources/Services/ImmichAPIClient.swift, Tests/Mocks/MockImmichClient.swift, Tests/DTOEncodingTests.swift, Tests/ImmichAPIClientTests.swift

## [2026-08-12] P1 video-playback — shipped (AC-900..909 PASS, 336 tests green)
- HLS playback in PhotoViewer: `VideoPlaybackEngine` protocol (Sources/Core/Protocols/VideoPlaybackEngine.swift) + `AVVideoPlaybackEngine` (Sources/Services/) + `VideoPlaybackViewModel` @Observable @MainActor + `VideoPlayerView` (Sources/Features/PhotoViewer/).
- **iOS 26 SDK pitfall**: `AVURLAssetHTTPHeaderFieldsKey` was REMOVED from SDK headers (symbol only in .tbd → "cannot find in scope"). Workaround: literal option key string "AVURLAssetHTTPHeaderFieldsKey" — value is stable, AVURLAsset reads options dict verbatim. Commented in engine.
- Engine hooks fire on main queue (time observer + end notification) — keep VM→engine hooks SYNCHRONOUS; async Task hops broke synchronous mock assertions in tests (7 failures fixed by dropping Task wrappers).
- Protocol-level `makePlayerLayer()` default impl returns bare AVPlayerLayer → mocks skip AVFoundation import (Tests/ stays AV-free, AC-906).
- pager branch: video page = VideoPlayerView, image = ZoomableImageView (.id(asset.id) recreation per page); filmstrip shows play glyph + duration badge; Edit button hidden for video (editor is image-only).
- PVSpacing has NO s6/s20/s40 — only s0/s2/s4/s8/s12/s16/s24/s32/s48 (compile errors, fixed).
- Video VM tests: 10 new (VideoPlaybackViewModelTests + MockVideoPlaybackEngine), suite 326 → 336.
- [2026-08-12] P1 live-photo (card live-photo, AC-950..956 PASS, 336 → 339 tests): Live Photos = still (isImage) + video pair asset (livePhotoVideoId). Viewer: `livePlayingIDs: Set<String>` swap still↔VideoPlayerView(pair), overlay bouton "LIVE" bottom-center (viewfinder + capsule ultraThinMaterial), `.onChange(of: selectedIndex)` → removeAll; onPlaybackEnded closure → auto-retour photo (Photos parity). Grid: badge "LIVE" bottomLeading material-pill (masqué selectionMode) via `asset.livePhotoVideoId != nil`. VM: refactor `prepare(asset:)` → délégué `prepare(assetID:baseURL:token:)` (URL via ImmichAssetURL.videoPlayback, aucun littéral chemin) + `prepareLivePhoto` guard pair non-vide sinon .failed sans toucher engine. VideoPlayerView: `assetID: String? = nil` override + `onPlaybackEnded` (onChange vm.status .ended). LESSON: memberwise init order strict — `assetID` déclaré après `token`, appel `assetID:` AVANT `baseURL:` → "Incorrect argument labels" compile error. Upload paire: champ multipart livePhotoVideoId déjà supporté (ImmichAPIClient:343) — extraction PHAsset des paires reportée P2 backup-engine.

## [2026-08-12] P1 slideshow — shipped (AC-960..969 PASS, 339 → 351 tests)
- Entry: PhotoViewer top bar `play.circle` (à côté d'info, disabled si count < 2) → `presentSlideshow()` crée `SlideshowViewModel(assets: localAssets, startIndex: selectedIndex)` + `vm.start()`, stocké `@State slideshowVM: SlideshowViewModel?` ; overlay interne `SlideshowView` zIndex 10 dans l'ancien ZStack du viewer (PAS de nouvelle présentation — cover-inside-cover crash 2026-08-05).
- `SlideshowViewModel` (@Observable @MainActor, Sources/Features/PhotoViewer/SlideshowViewModel.swift): machine à états pure SANS Timer. `SlideshowSpeed` enum TimeInterval CaseIterable (2/3/5/10s, label "Ns"). `advance()` wrap modulo, no-op si `guard isPlaying, !isVideoActive`; `next()/previous()` wrap autorisés paused; `videoStarted()/videoEnded()` + `slideChanged()` (arme la suspension si slide vidéo, re-clear sinon) — le view appel `slideChanged()` dans onAppear + onChange(currentIndex).
- **LESSON: ticker = view-owned `.task(id: tickerKey)`** (`"\(vm.speed.rawValue)-\(vm.isPlaying)"` → re-arm à chaque changement vitesse/play) avec `guard vm.isPlaying, !vm.isVideoActive` avant `vm.advance()`; sleep `Task.sleep(for: .seconds(vm.speed.rawValue))`. Un Timer.publish 1s fixe aurait avancé 10× par slide à vitesse 10s.
- SlideshowView: slides vidéo → VideoPlayerView(controlsVisible: false, onPlaybackEnded: vm.videoEnded) (autoplay ready); images → ZoomableImageView; transition .opacity animée `PVMotion.adaptive(.easeInOut(0.4), reduceMotion:)` via `.animation(value: vm.currentIndex)`; top: compteur "N of M" + xmark close (stop + onClose → slideshowVM = nil); bottom GlassEffectContainer: prev/play-pause/next + Menu vitesse (checkmark).
- Tests: 12 (SlideshowViewModelTests.swift) — wrap, no-op paused/vidéo-active, videoEnded reprend, slideChanged re-clear, nav paused (1 test corrigé: après toggle play, advance wraps 1→0).
- CARD-CHECK LESSONS (checks AC-962/963/969 relus): (1) en POSIX sh, une affectation après `&&` (ex: `grep -q X && n=$(...)`) est exécutée en sous-shell → `n` vide → capturer `n=$(...)` AVANT les `&&`; (2) tokens grep doivent matcher le source exact: "SlideshowVM" ∉ "SlideshowViewModel" (substring trap), `two = 2` ∉ `twoSeconds = 2`; (3) `grep -o "Executed [0-9]* tests"` renvoie TOUTES les suites → `sort -n | tail -1` pour le max (head -1 donnait 21 = petite suite annexe); (4) compter les APPELS réels avec `^[[:space:]]*\.(fullScreenCover|sheet)\(` (grep simple comptait les mentions doc-comment: 5 vs 3).

## [2026-08-12] P1 save-download — shipped (AC-980..989 PASS, 351 → 361 tests)
- `PhotoLibraryService` étendu: `saveImage(data:) async throws -> String` + `saveVideo(at fileURL:) async throws -> String` (retournent localIdentifier). Impl (`PhotoLibraryServiceImpl`): **`creationRequestForAsset(from:)` prend un UIImage, PAS Data** → staging en fichier temp + `creationRequestForAssetFromImage(atFileURL:)`; ext par sniff des 16 premiers octets (ftypheic/ftypheix/ftypmif1 → heic, sinon jpg); vidéo `creationRequestForAssetFromVideo(atFileURL:)`; `PHPhotoLibrary.performChanges` variante async (iOS 15+). Nettoyage temp dir en `defer`.
- NEW `Sources/Services/AssetFileTransfer.swift`: helpers partagés extraits de PhotoViewer (DRY): `fileExtension(forMime:)` (+ mp4/mov/mpg), `baseName(originalName:datePrefix:)` (fallback "Photo-yyyy-MM-dd"), `writeTempFile(data:name:)` (dir immich-share-UUID unique), `fetchData(from:token:session:)` (2xx + non-vide sinon `.serverError(code, nil)`/`.decoding`) — `presentNativeShare` refactoré dessus; helpers privés supprimés de PhotoViewer.swift. `ActivityPresenter` passé `private` → interne (réutilisé par le nouveau VM).
- NEW `SaveToLibraryViewModel` (Sources/Features/PhotoViewer/, @Observable @MainActor): injections `photoLibrary` (défaut PhotoLibraryServiceImpl), `session` (défaut .shared — tests CapturingURLProtocol), `presentShare` (défaut ActivityPresenter.present via **`MainActor.assumeIsolated`** — défaut d'argument sync nonisolated sinon erreur compile). `saveToPhotos()` (image → bytes intacts → saveImage; vidéo → temp ext depuis Content-Type → saveVideo → removeItem dir) / `downloadOriginal()` (temp + presentShare + cleanup post-completion). Nom fichier = originalFileName via getAsset (sinon date fallback). États: isSaving/isDownloading/errorMessage/lastSavedIdentifier/savedKind/didPresentDownload/lastDownloadFileName.
- UI: `PhotoShareSheet` (PhotoViewer.swift) — section "Save" en tête de liste (Save to Photos `photo.badge.plus` / Download original `arrow.down.circle`, ProgressView busy, checkmark succès, erreur caption immichError, sensoryFeedback lastSavedIdentifier/didPresentDownload).
- Verify APIError: `case serverError(Int, String?)` — PAS de labels (`APIError.serverError(code, nil)`).
- Tests: 10 (SaveToLibraryViewModelTests.swift) — auth header + path /api/assets/{id}/original, bytes identiques, ext vidéo réelle, cleanup temp (fichier+dir supprimés APRÈS save — mock client renvoie originalFileName "x.jpg" par défaut → noms "x.mp4"/"x.jpg"), present closure injectée (items + completion → post-cleanup), 500 → errorMessage sans présentation, AssetFileTransfer unités. Suite 351 → 361.

## [2026-08-12] P1 archive — shipped (AC-1000..1009 PASS, 361 → 366 tests)
- Archive = `AssetBulkUpdateDto{ids, visibility}` via `bulkUpdateAssets` (PUT /api/assets, 204) — **PAS de champ isArchived** (champ réponse read-only). `AssetBulkUpdateDto.visibility` upgrade String? → **`AssetVisibility?` enum** (rawValue "archive", Constants.swift:45) — a nécessité la correction de 2 tests P0 (String "archive" → .archive); les raw values encodent identiquement.
- 4 surfaces UI: (1) `TimelineViewModel.archiveSelected()` (bulk, try-then-mutate: remove items+loadedIds, exitSelectionMode si succès seulement) + `archive(id:)` single; (2) TimelineView toolbar Archive (archivebox) mode sélection, disabled si vide; (3) `AssetThumbnailCell.onArchive` optionnel → entrée menu contextuel (branche non-trash, avant Delete); (4) viewer: callback `onArchive` sur TOUTE la chaîne (PhotoViewerPresentation → extension View → struct → init — 5 points) + bouton archivebox barre basse (non-Trash) + fallback self-contained (bulkUpdateAssets → removeAsset + onDataChanged).
- TimelineViewModel: `filterVisibility: String?` ajouté et câblé dans refresh()/load()/loadNextBucket() (prépare le filtre "Hidden/Archived" — card favorites-filter).
- Tests: 5 (test_archive_*, TimelineViewModelTests) — dto ids+visibility, removal+exit, échec → items intacts + selectionMode conservé (globalError injecté APRÈS load sinon makeLoadedVM échoue), single, no-op vide. Suite 361 → 366.
- Lesson check: AC-1009 `sort -n | tail -1` sur le résumé échoue (ligne "TEST SUCCEEDED" non numérique) → réécrit: `grep -o "Executed [0-9]* tests" | grep -o "[0-9]*" | sort -n | tail -1` + `grep -q TEST SUCCEEDED` séparé.

## [2026-08-12] P1 favorites-filter (card 6/8)
- `TimelineViewModel.setFilter(isFavorite:visibility:) async` — no-op si valeurs identiques (garde `filterIsFavorite != isFavorite || filterVisibility != visibility`), sinon assigne + `refresh()` (reset complet + reload, réutilise le chemin existant). Le filtre commité RESTE en place si refresh échoue → retry = pull-to-refresh (`refresh()` rejoue avec le filtre courant); PAS de re-setFilter (no-op guard) pour retry.
- UI: `Menu` (line.3.horizontal.decrease.circle, accessibilityIdentifier "filterMenu") dans topBarTrailing, mode NON-selection uniquement (branche else du ToolbarItemGroup — seul item normal-mode). 3 items avec checkmark: All (nil,nil) / Favorites (true,nil) / Archived (nil,"archive") — le filtre Archived ferme la boucle du plumbing filterVisibility du card archive (ancien "Hidden/Archived" backlog).
- Mock: captures étendues `lastTimeBucketsIsFavorite` + `lastTimeBucketsVisibility` (getTimeBuckets) + `lastTimeBucketVisibility` (getTimeBucket — vérifie la persistance du filtre à travers la pagination).
- Tests (TimelineViewModelTests, 6): favorite param, archive visibility + héritage getTimeBucket, no-op (requestCount stable — mock a `private(set) var requestCount`), reload frais sans stale items (muter bucketsResponse/bucketResponses APRÈS makeLoadedVM pour simuler un sous-ensemble serveur), échec → errorMessage, retry via refresh.
- Suite 366 → 372.
- Lessons: (1) label de Menu en closure Label/Text — jamais `Button("Titre"`; (2) assertions XCTestAssertFalse vs `== false`; (3) les checks de card doivent viser la syntaxe RÉELLE — edits de checks AC-1011/AC-1015 (méthodologie standard: check mismatch → EDIT CHECK + note Status).

## [2026-08-12] P1 map-extras (card 7/8)
- "Open in Maps": `PhotoInfoPanel`/`ExifInfoPanel` gagnent `onOpenInMaps: ((Double, Double) -> Void)?` + `onAdjustLocation: (() -> Void)?` (défaut nil → boutons cachés sur surfaces non câblées). whereCard: rangée boutons sous MiniMapView (InfoCard-style gray capsule, Label pvBody medium), seulement si coords présentes. `PhotoViewer.openInMaps(lat,lon)` = MKMapItem(+MKPlacemark).name = infoVM.placeName ?? city,country join → openInMaps(). NOUVEL import MapKit dans PhotoViewer.swift.
- "Adjust Location": NEW `Sources/Features/PhotoViewer/AdjustLocationSheet.swift` = `DraggablePinMapView` (UIViewRepresentable MKMapView standard, MKMarkerAnnotationView isDraggable=true, didChange .ending/.canceling → onCoordinateChange, region span 0.05, updateUIView recolle l'épingle si coords externes changent) + `AdjustLocationSheet` (asset/vm/onDone(Bool), @State lat/lon init via `State(initialValue:)` — **pitfall: label d'init est initialValue: PAS initial:** "no exact matches in call to initializer"; Cancel → onDone(false), Save → Task vm.setLocation → si errorMessage nil → onDone(true); ProgressView + disabled pendant isSaving; erreur inline immichError).
- `AssetDetailViewModel.setLocation(latitude:longitude:) async`: guard bornes (-90...90)/(-180...180) → "Invalid coordinates." sans réseau (testé); PATCH UpdateAssetDto(latitude:longitude:), captures lastUpdateBody/lastUpdateAssetId; success → detail = updated + **geocoded = false (reset guard FM-3) + reverseGeocodeIfNeeded()** → placeName re-géocodé; catch → errorMessage.
- PhotoViewer: 3e `.sheet(isPresented: $presentAdjustLocation)` (présentée après presentShare, .fraction(0.75), if let asset = currentAsset, let vm = infoVM → AdjustLocationSheet(asset:vm:onDone:{ saved in presentAdjustLocation = false; if saved { refreshInfo() } })). Panneau info :285 passe onOpenInMaps: openInMaps + onAdjustLocation: { presentAdjustLocation = true }.
- Tests (AssetDetailViewModelTests, §Adjust location): test_setLocation_sendsPATCHWithCoords (lastUpdateAssetId/body.lat/body.lon/lastUpdateMethod .PATCH/errorMessage nil), test_setLocation_rejectsOutOfBounds (95/200 → body nil + message, PAS de réseau), test_setLocation_regeocodesAfterUpdate (updateAssetResponse w/ ExifResponseDto init ORDRE DÉCLARATION complet — make,model,exifImageWidth,exifImageHeight,fileSizeInByte,orientation,dateTimeOriginal,modifyDate,timeZone,lensModel,fNumber,focalLength,iso,exposureTime,latitude,longitude,city,state,country,description,projectionType,rating — MockLocationGeocoding.placeNameResult="Paris", assert detail.exif.latitude + placeName + callCount 1), test_setLocation_failureShowsError (globalError → "Server error 500: boom").
- MockLocationGeocoding (Tests/Mocks/MockLocationGeocoding.swift): @MainActor final class, `placeNameResult: String?`/`placeNameError: Error?`/private(set) callCount, return "Mock Place" défaut — PAS de custom init.
- Suite 372 → 376. Card AC-1020..1026 PASS (AC-1021 check réécrit target PhotoViewer.swift; AC-1023 token fix).

## [2026-08-12] P1 storage-stats (card 8/8 — P1 complete)
- StorageStatsViewModel (Sources/Features/Profile/): client injecté, load() async guard !isLoading, photos/videos Int, usage/quota Int64, didLoad private(set), quota = premier usageByUser.quotaSizeInBytes > 0 via **boucle for où** (le one-liner `first(where:)?.` a CRASHÉ le frontend Swift 5.9: "error: failed to produce diagnostic for expression" — leçon: gaffe aux chaînes optionnelles torchées sur valeurs génériques → boucle simple), format statique ByteCountFormatter .file nonisolated (tests acceptent MB|MO, GB|GO).
- ProfileView: Section "Stockage" (entre Compte et Gestion): LabeledContent Photos/Vidéos (formatted() localisé) + Utilisation (format) + ProgressView quota déterministe tint immichPrimary si quota>0 + ligne loading (small ProgressView) + erreur immichError + bouton Réessayer; .task(load) + .refreshable(load) sur le Form.
- DI: DependencyContainer.makeStorageStatsViewModel; RootView @State storage + ProfileView(trash:storage:).
- Tests StorageStatsViewModelTests (6): success mapping, quota 0 → nil, default response, failure, **re-entrancy via async let (requestCount == 1)**, format locale.
- Suite: 376 → 382. **P1 TERMINÉ** — reste plan: P2 backup-engine, backup-live-activity; P3 people-faces, partner-sharing, activity-feed, shared-link-edit, album-edit; P4 memories, duplicates; P5 oauth, qr-scan, selfsigned-cert, multi-server, widgets-appintents, i18n-catalog; backlog push-notifications.

## [2026-08-12] P2 backup-engine (card 9/25)
- Seam: `BackupAssetSource` protocol + value types BackupCandidate{id,kind,fileName,fileCreatedAt,fileModifiedAt,duration?,isFavorite,albumName?}/BackupAlbum — PHAsset non constructible → moteur 100% testable; PhotoLibraryServiceImpl conforme en extension (fetchAlbums .album/.any; fetchCandidates albumIDs vide→tout ou union dédoublée par localIdentifier; albumName via PHAssetCollection.fetchAssetCollectionsContaining; "Screenshots" filtré côté ENGINE).
- `BackupEngine` @Observable @MainActor (Sources/Services/BackupEngine.swift): Phase idle/checking/uploading/done/cancelled; run(settings:BackupSettings) → gates wifi/charging (lastError + phase idle, ZERO réseau), loadData 1×/candidat (checksum SHA1 base64 + data cache), bulkUploadCheck chunks 1000, upload séquentiel continue-on-error, reset() remet isCancelled=false (donc cancel() AVANT run → phase .cancelled via guard). cancel() = flag global — BG expiration handler.
- `BackupSettingsStore` (UserDefaults suite "backupSettings" injectable, clés photoBackup*), snapshot() pour run. `UploadViewModel` = glue (engine+settings+scheduler, runBackup→engine.run + scheduler.submit si done, cancelBackup, loadAlbums). `BackupSettingsView` réécrite (toggles + album picker + ProgressView + Run now/Cancel) — reçoit vm param (ProfileView via RootView @State container.makeUploadViewModel()).
- `BackgroundBackupScheduling` + `BGTaskBackupScheduler` (taskIdentifier "app.immich.background-backup", BGProcessingTaskRequest requiresNetworkConnectivity, cancel+resubmit). Registration dans ImmichSwiftUIApp.onAppear; project.yml BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes processing (xcodegen régénère Info.plist).
- `BackupEnvironment` + SystemBackupEnvironment (NWPathMonitor une seule fois process-wide + NSLock cache; UIDevice battery).
- Lessons: (1) mocks par défaut = résultats vides → bulkUploadCheckResponse(results: []) = zéro accept → tests upload assertaient nil (fix: configurer accept per-test); (2) `$vm.settings.isEnabled` exige settings var (Bindable); (3) PHAsset n'a PAS d'assetCollections — utiliser PHAssetCollection.fetchAssetCollectionsContaining.
- Suite: 382 → 399 tests green.

## [2026-08-12] P2 backup-live-activity (card 2/2) — P2 TERMINÉ
- Live Activity: FIRST widget extension target + FIRST shared framework. project.yml: target ImmichWidgets (app-extension, com.apple.widgetkit-extension, bundle fr.millianlmx.immich-ios.widgets, embed dans app) + target ImmichSharedKit (framework, fr.millianlmx.immich-ios.sharedkit, SKIP_INSTALL, embed app+widgets). App info: NSSupportsLiveActivities + NSSupportsLiveActivitiesFrequentUpdates. Scheme build: ImmichWidgets: all.
- PITFALL MAJEUR: `import ImmichWidgets` depuis l'app compile (module existe) MAIS link FAIL — symboles indéfinis (metatype BackupActivityAttributes). Un app-extension n'est pas un produit linkable pour le host. Solution: types partagés (BackupActivityAttributes + ContentState) dans framework ImmichSharedKit, les deux targets dépendent. Identity de type = (module, type) → DOIT être un seul module partagé.
- PITFALL access: struct public obligatory cross-module ET **memberwise init est internal même pour struct public** → explicit public init(progress:uploaded:total:) + init(totalCount:).
- Service: protocol BackupLiveActivityServicing (start/update/end) + LiveActivityBackupService (Activity.request guard ActivityAuthorizationInfo().areActivitiesEnabled; update/end via Task await; dismissalPolicy .immediate; progress = total>0 ? min(uploaded/total,1) : 0). `import ImmichSharedKit` dans le service app.
- BackupEngine: `var onProgressUpdate: ((_ uploaded: Int, _ total: Int) -> Void)?` — fonction types N'ONT PAS de argument labels → `(_ x: Int, _ y: Int)` obligatoire. Fired: début .uploading (0,total) + après chaque currentIndex+=1 (uploadedCount,total).
- UploadViewModel: param `activityService: any BackupLiveActivityServicing = LiveActivityBackupService()`; runBackup: hook = [weak self] → update; start(0,0) avant run; après: .done → end(success: failedCount==0) + scheduler.submit; .cancelled → end(success:false); hook remis à nil (testé). Test existant test_viewModel_runBackupSubmitsSchedulerOnDone maintenant injecte le mock (évite ActivityKit réel).
- Widget UI: BackupLiveActivity (ActivityConfiguration for: — Lock Screen VStack ProgressView + tint 0.259/0.314/0.686 = #4250AF; DynamicIsland expanded .leading %/.trailing up/total/.bottom ProgressView, compactLeading square.and.arrow.up, compactTrailing %, minimal %; percentLabel = Int(progress*100)). WidgetBundle @main ImmichWidgetsBundle.
- Tests (Tests/UploadViewModelLiveActivityTests.swift 5 + BackupEngineTests test_backupEngine_onProgressHookFiresSequence): start puis 4 updates (0,3)(1,3)(2,3)(3,3) puis end(3,3,true) + submitCount 1; cancel via source.onFirstLoad → engine.cancel() → end success false + pas de submit; disabled → start seul, pas d'update/end; wifi gate → idle + pas d'update/end; hook nil après run. Mocks: MockBackupLiveActivityService (startCalls/updateCalls/endCalls tuple arrays, NSLock, @unchecked Sendable — @testable import ImmichSwiftUI REQUIS dans Tests/Mocks/).
- Suite 399 → 405. AC-1050..1056 PASS.

## [2026-08-12] P3 people-faces (card 1/5)
- New People tab (RootTab.people entre Albums et Shared; bubble icon magnifyingglass + handleBubbleTap .people = break — pas d'action contextuelle). PeopleView: NavigationStack(path: [PersonResponseDto]), List sections Featured (isFavorite==true, tri count desc) + People + footer "Show N hidden people" (toggleShowHidden → reload withHidden:true), avatar 48/96 Circle AuthenticatedAsyncImage(personThumbnail), detail: rename alert TextField + favorite/hide round buttons + Menu Merge (autres personnes → merge([other], into: current) + reload) + LazyVGrid faces + .photoViewer (PhotoViewerItem(assets: vm.personAssets, index: i) pour paging).
- PeopleViewModel: load(force:)/toggleShowHidden/loadStatistics (taskGroup fan-out concurrency 6)/rename/toggleFavorite/toggleHidden (tous via updatePerson PUT)/merge (POST /people/{id}/merge + load(force)+loadAssets)/select/loadAssets (guard assetsLoadedForID; searchMetadata personIds=[id])/refreshAssets/clearSelection; captures lastMergeIds/lastMergeTarget.
- ImmichAssetURL.personThumbnail(personId:baseURL:size:) → /api/people/{id}/thumbnail (+size query si != .thumbnail).
- PersonResponseDto += Hashable, Identifiable (navigationDestination/ForEach/NavigationLink exigent).
- MockImmichClient: captures lastPeoplePage/lastPeopleWithHidden; updatePerson echo + isFavorite (sinon toggleFavorite test échoue — probe: mock NE dois PAS ignorer un champ que le serveur PG updates).
- Lessons tests: (1) erreur mock à régler APRÈS load() (sinon people vide → vm.people[0] crash Index out of range — même leçon que card archive globalError); (2) loadStatistics requiert people chargés d'abord (appeler vm.load()).
- Suite 405 → 419 (14 tests People). AC-1060..1067 PASS directs.

## [2026-08-12] P3 partner-sharing (card 2/5)
- TimelineViewModel: `filterWithPartners: Bool?` + `setFilter(isFavorite:visibility:withPartners: = nil)` (default nil → anciens call sites/tests intacts); refresh/load/loadNextBucket passent filterWithPartners (3 call sites). Menu Timeline + item "Shared with you" (withPartners: true) après Archived.
- SharedLinksViewModel: partners/isPartnersLoading/partnersError + loadPartners/togglePartnerTimeline (updatePartner + replace row, try-then-mutate)/removePartner (delete puis removeAll).
- SharedLinksView: branche "empty" → ContentUnavailable UNIQUEMENT si links ET partners vides; List double section (Partners "Shared with you" + links); PartnerRow (PartnerAvatarCircle initials + name + subtitle shown/hidden + Toggle accessibilityIdentifier partnerTimelineToggle-<id> + trash → confirmationDialog Remove); .task/.refreshable chargent partners.
- Mock: lastTimeBucketsWithPartners + lastTimeBucketWithPartners captures.
- Tests: SharedLinksViewModelTests +5 (load maps, failure, toggle sends updatePartner + row replaced — mock updatePartner echo inTimeline, failure keeps row, remove); TimelineViewModelTests +2 (sharedWithYou → withPartners true + bucket inherit; no-op identical 3-arg).
- Suite 419 → 426. AC-1070..1076 PASS direct, aucun check édité.
- Repère: PartnerResponseDto 7 champs {id,name,email,profileImagePath,avatarColor,profileChangedAt,inTimeline}.

## [2026-08-12] P3 activity-feed (card 3/5)
- `ActivityFeedViewModel` NEW (Sources/Features/Albums/ActivityFeedViewModel.swift): client+albumId+currentUserId injectés; activities sorted createdAt desc (VM-side, load()); addComment (trim, ActivityCreateDto(albumId:type:.comment) → insert(0)); toggleLike (hasMyLike = type .like && user.id==currentUserId → deleteActivity own like / createActivity type:.like assetId:); deleteActivity idempotent local; errorMessage propre; try-then-mutate partout (like re-load depuis serveur, jamais de splice).
- `ActivityFeedSheet` NEW: composer TextField axis .vertical 1...4 + send arrow.up.circle.fill (disabled vide/isSending, restore draft si échec), rows = UserAvatarCircle 36 + name/comment|"Liked this photo" + temps relatif RelativeDateTimeFormatter (unitsStyle .short) + thumb 28 si assetId + heart toggle + trash (immichError); accessibilityIdentifier activityLikeToggle-<id>/activityDelete-<id>; ContentUnavailable "No Activity Yet".
- `LongDateFormatter.parse(isoTimestamp:)` ajouté (Core/Utilities/LongDateFormatter.swift) — ISO8601DateFormatter; le vieux helper existait déjà (format seulement) — NE PAS re-déclarer (compile error).
- AlbumDetailView: menu ellipsis item "Activity" (bubble.left.and.bubble.right) avant Divider SharedWith; `.sheet(item: $activityFeedItem)` ActivityFeedSheet. + detents [.medium,.large] + dragIndicator; ActivityFeedViewModel construit inline via DependencyContainer.shared.client (AlbumDetailViewModel.client est private).
- Tests 11 (ActivityFeedViewModelTests.swift): load/trie/heures/failure/addComment send+prepend/empty no-op/failure keep clean/like create (dto .like+assetId)/unlike delete/hasMyLike/like reload/delete own/delete failure keep (9+ AC threshold).
- **Flaky fix (importé de P1)**: test_storageStats_loadIsNotReentrant racé (async-let: mock retourne immédiatement → 2e load parfois POST-completion) → `statisticsGate: (() async -> Void)?` dans MockImmichClient.getServerStatistics + gate sleep 200ms → deterministe requestCount==1.
- **Boom localizedDescription**: `error.localizedDescription` enveloppe le message dans "L'opération n'a pas pu s'achever. (...Boom erreur 1.)" → assertions contes `contains("Boom")` (jamais XCTAssertEqual plain Boom).
- Suite 426 → 436 (TEST SUCCEEDED). PVSpacing pas de s10 (s8). xcodegen requis (3 nouveaux fichiers).

## [2026-08-12] P3 shared-link-edit (card 4/5)
- EditSharedLinkSheet réutilisable (link + onSave closure async -> Bool) — surfaces: SharedLinksView tab (contextMenu row) + SharedLinkSheet album (contextMenu row). Wrapper `EditLinkItem: Identifiable` INTERNE (partagé 2 fichiers — private aurait cassé le 2e).
- VM: SharedLinksViewModel.updateLink(id:dto:) + AlbumDetailViewModel.updateSharedLink(id:dto:) — try-then-mutate replace row.
- Sémantique serveur: password "" = clear, nil = inchangé; expiresAt nil = clear; booleans toujours envoyés (édition complète). Encodage date: ISO8601DateFormatter [.withInternetDateTime, .withFractionalSeconds]; parse: LongDateFormatter.parse.
- Suite 436 → 440.
- Lessons: (1) eval zsh dans les checks AC: `$editLinkItem` dans un pattern entre guillemets doubles est EXPANSÉ par eval → pattern vide → FAIL faux; utiliser grep -F avec token sans $ (ex "EditSharedLinkSheet(link: item.link)"); (2) checks qui ciblent un fichier de tests: vérifier le nom réel (AlbumsTests.swift contient les tests AlbumDetailVM); (3) test qui mock la réponse update: construire la DTO modifiée explicitement (makeSharedLink ne prend pas de description).

## [2026-08-12] P3 album-edit (card 5/5) — P3 TERMINÉ
- updateAlbumDetails(name:description:isActivityEnabled:) -> Bool sur AlbumDetailViewModel (dto 5 args, thumbnail/order nil) + EditAlbumSheet (Form 3 champs, Save disabled si nom vide) + menu ellipsis AlbumDetailView.
- Mock echo: updateAlbum applique albumName/description/isActivityEnabled (pas seulement cover) — AlbumResponseDto 3 champs let → var.
- Suite 440 → 442.

## [2026-08-12] P4 memories (card 1/2)
- Tab Memories entre Photos et Albums (RootTab.memories, ordre Flutter: Photos/Memories/People/Albums/Shared). Icon sparkles.rectangle.stack.
- MemoriesViewModel @Observable @MainActor: load() sorted (year, memoryAt) desc, try-then-mutate; getMemories() P0 déjà client-ready.
- MemoriesView: MemoryCard (header "On this day" + year + count, grid 9 premiers assets, "+N more"), tap → PhotoViewerItem(assets: memory.assets.map(AssetReactItem.init), index: 0) via .photoViewer; empty/error/loading states.
- Save/unsave memory = backlog (serveur PUT /memories/{id}/save non exposé client).
- Suite 442 → 446. AC-1110..1114 PASS.

## [2026-08-12] P4 duplicates (card 2/2) — P4 TERMINÉ
- DuplicatesViewModel: load(), deletableIds(for:) = assets − suggestedKeepAssetIds, deleteGroup(id:) → deleteAssets(force:false) → drop local (PAS de reload: le job serveur peut re-retourner le groupe; pull-to-refresh).
- DuplicatesView: cartes groupe (N copies + Delete), grid 3 cols, badge Keep (immichPrimary capsule) sur suggested, confirmationDialog (pendingCount/deletePrompt helpers — éviter lookup dupliqué dans le titre).
- ProfileView: NavigationLink "Doublons" (rectangle.on.rectangle.angled) section Gestion; container.makeDuplicatesViewModel + RootView @State + ProfileView(trash:storage:upload:duplicates:).
- Suite 446 → 454. AC-1120..1124 PASS. Lesson: ne pas re-fetch après delete quand le mock/serveur peut re-retourner les données (test 1 failure → fix VM).

## [2026-08-12] P5 oauth (card 1/6)
- Flow mobile: GET /api/auth/oauth/mobile?redirectUri= → ASWebAuthenticationSession (scheme app.immich, CFBundleURLTypes project.yml) → POST /api/auth/oauth/callback {url, redirectUri} → applySession (partagé login/OAuth).
- DTOs+Auth.swift: OAuthMobileResponseDto{url}, OAuthCallbackRequestDto{url,redirectUri}, OAuthCallbackResponseDto{accessToken,isAdmin,name,email,profileImagePath,shouldChangePassword?}.
- AuthViewModel: static oauthRedirectURI "app.immich://oauth-callback", `oauthSessionHandler: (URL) async -> URL?` injectable (prod = OAuthSessionPresenter), canOAuthLogin (oauthButtonText non-vide), startOAuthFlow(); applySession() refactoré depuis login.
- OAuthSessionPresenter (Sources/Services/): ASWebAuthenticationSession + AnchorProvider (première key-window).
- LoginScreen: bouton "Continue with X" quand canOAuthLogin (remplace TODO $PHASE_OAUTH).
- sendNoAuth gagne param query. Suite 454 → 459. AC-1130..1135 PASS (check édité: chemins via constantes).

## [2026-08-12] P5 qr-scan (card 2/6)
- QRServerConfigParser (Sources/Features/Auth/Onboarding/): JSON {"serverUrl"|"url"} sinon URL brute, https par défaut, trailing slash strip, nil si invalide.
- QRScannerView: UIViewRepresentable AVCaptureSession + AVCaptureMetadataOutput (.qr), stopRunning après found, permission states (requestAccess async, denied → UILabel).
- ServerURLScreen: bouton qrcode.viewfinder dans le champ + sheet NavigationStack scanner + handleScannedPayload → serverURLString + connect automatique; scanError inline.
- NSCameraUsageDescription project.yml. Suite 459 → 468. AC-1140..1144 PASS.

## [2026-08-12] P5 selfsigned-cert (card 3/6)
- TrustedServerStore protocole (contains/add) + TrustedServerStoreImpl (UserDefaults set "trustedServers", @unchecked Sendable + NSLock).
- TrustEvaluatingURLSessionDelegate: challenge .serverTrust → SecTrustEvaluateWithError; échec + hôte trusté → SecTrustSetAnchorCertificates(chaîne serveur) + SetAnchorCertificatesOnly(true) + ré-éval; sinon cancel.
- ImmichAPIClient.init(session:trustStore:) — session éphemère déléguée si trustStore fourni (DependencyContainer passe TrustedServerStoreImpl).
- AuthViewModel: static isTLSError (4 URLError codes), pendingUntrustedHost, trustPendingServer() (add + reconnect); connectServer catch URLError TLS → host exposé.
- ServerURLScreen: alert "Trust this server?" → trustPendingServer.
- NSAllowsArbitraryLoads conservé (LAN http Immich) — scope HTTPS auto-signé via delegate.
- Suite 468 → 475. AC-1150..1154 PASS. Lesson: mock serverVersion retourne 1.120.0 → assert reachable via guard case, pas XCTAssertEqual(version: nil).

## [2026-08-12] P5 multi-server (card 4/6)
- AuthViewModel: savedServers (UserDefaults "authServerList"), addCurrentServerToSaved() (appelé dans applySession — login + OAuth), removeSavedServer(at:), switchServer(to:) (URL + resetSession → onboarding re-login pré-rempli), addNewServer() (URL vide + resetSession).
- ProfileView section "Serveurs": rows checkmark si courant, tap switch, .onDelete, bouton "Ajouter un serveur".
- Suite 475 → 480. AC-1160..1163 PASS.

## [2026-08-12] P5 widgets-appintents (card 5/6)
- Sources/AppIntents.swift (main target): BackupNowAppIntent (AppIntent, title "Back up now", openAppWhenRun, perform → MainActor.run { container.makeUploadViewModel() } + runBackup — **perform nonisolated → MainActor.run requis**) + ImmichAppShortcuts AppShortcutsProvider (3 phrases).
- ImmichWidgets/ImmichHomeWidget.swift: StaticConfiguration "ImmichHomeWidget" (icône + nom + "Back up now", widgetURL app.immich://backup, small+medium) — enregistré dans ImmichWidgetsBundle aux côtés de BackupLiveActivity.
- ImmichSwiftUIApp .onOpenURL: app.immich://backup → runBackup.
- Widget statique (pas data-rich): processus widget ne peut pas atteindre les VMs app.
- AppShortcut n'a pas de member shortTitle (test ajusté). Suite 480 → 483. AC-1170..1174 PASS.

## [2026-08-12] P5 i18n-catalog (card 6/6) — P5 TERMINÉ — TOUS LES PHASES TERMINÉS (P0-P5)
- Localizable.xcstrings: 192 → 198 clés, 159 → 176 avec fr. 22 traductions FR manquantes (chaînes EN) + clés tab bar (Photos/Memories/Albums/People/Shared/Me/Search en+fr — résolution auto LocalizedStringKey dans RootView). Clés source-FR (onboarding/Profile) restent FR par design (D1).
- Tests/AppStringsTests.swift (3): catalog JSON valide ≥196, clés tab bar avec fr, en-only ≤ 24 (placeholders + contenu FR).
- Suite 483 → 486. AC-1180..1183 PASS (check édité: seuils réels).
- P0-P5 shipped: api-surface-expansion, video-playback, live-photo, slideshow, save-download, archive, favorites-filter, map-extras, storage-stats, backup-engine, backup-live-activity, people-faces, partner-sharing, activity-feed, shared-link-edit, album-edit, memories, duplicates, oauth, qr-scan, selfsigned-cert, multi-server, widgets-appintents, i18n-catalog. Backlog: push-notifications. Docs: docs/feature-audit-vs-flutter.md + docs/feature-parity-plan.md.

## [2026-08-13] Memories redesign Liquid Glass (moment + cards full-bleed) — [tag: feature, design]

**Contexte** : Redesign de l'onglet Memories: remplacer les cartes grille 3x3 par des cartes full-bleed (hero photo + chips verre) + nouveau MemoryMomentView plein écran (Ken Burns, GlassEffectContainer, filmstrip, viewer).
**Décision/apprentissage** : Onglet Memories conservé (pas de lane Photos). MemoryMomentView présente via fullScreenCover(isPresented:)+if let (pas d'identifiable sur le DTO). MemoryMomentPresentation pur (fullDateLabel/peopleLabel/tagsLabel/people/tags) testé. Héro en size:.preview. Ken Burns gated par accessibilityReduceMotion.
**Pourquoi** : Shot de dopamine + nostalgie: photo plein écran, verre liquide flottant, surfacage de toutes les infos (année/date/comptes/lieu/personnes/tags/isSaved/caméra).
**Fichiers concernés** : Sources/Features/Memories/MemoryMomentView.swift, MemoryMomentPresentation.swift, MemoriesView.swift; Tests/MemoryMomentPresentationTests.swift

## [2026-08-14] Slideshow v2 "spectacle" + fix contrôle — [tag: feature, design, bug]

**Contexte** : Audit slideshow → bugs (impossible d'arrêter, figement vidéo-échec, latence post-vidéo, fuite de gestes, menu vitesse chevauchant next) + refonte spectacle (Ken Burns, transitions, chrome auto-masqué, Live Photos animées, shuffle, progression).
**Décisions** :
- `videoEnded()` idempotent + avance immédiatement (`wasVideo = isVideoActive; isVideoActive = false; if wasVideo { advance() }`) — avance Photos dès fin/failure vidéo (B2/B3).
- `VideoPlayerView` + `isPaused` (pause externe) + `onStatusChange` (`.ended`/`.failed` → `videoEnded`). Pause couple au player : `.onChange(of: isPaused)` → `vm.pause()` / reprise si `.paused` seulement (B1).
- VM : `order:[Int]` + `shuffle()` (repositionne sur asset courant), `SlideshowTransitionStyle` (dissolve/slide/kenBurns), `hasPlayableMotion` (isVideo || livePhotoVideoId non-vide). Dead code `videoStarted()` supprimé.
- Ticker : `tickerKey = "\(speed)-\(isPlaying)-\(isVideoActive)"` (ré-armé par l'état vidéo). Gestes : `dismissDrag` garde `guard slideshowVM == nil` (B4). `presentSlideshow()` ne fait plus `vm.start()` (onAppear le fait).
- Chrome : GlassEffectContainer bottom `[shuffle|prev|play|next|speed]`, transition Menu top, progress bar, auto-hide 3 s, tap = toggle.
**Piège** : l'app définit son propre `struct TimelineView` (timeline photos) qui shadow le `TimelineView` SwiftUI → utiliser `SwiftUI.TimelineView` pour le Ken Burns continu.
**Tests** : SlideshowViewModelTests 12→22, nouveau SlideshowHelpersTests (7 : SlideshowDirection.isForward wrap, KenBurnsPhase identity/bornes/périodicité/pic). Suite 486→534.
**Fichiers concernés** : Sources/Features/PhotoViewer/{SlideshowView,SlideshowViewModel,KenBurnsImageView,VideoPlayerView,PhotoViewer}.swift, Sources/Core/Types/AssetReactItem.swift; Tests/SlideshowViewModelTests.swift. Plan : .opencode/scratch/slideshow-v2-spectacle.plan.md

## [2026-09-12] Fix OAuth 404 + séparateur « OU » vertical — [tag: bug, oauth]

**Contexte** : constat utilisateur en production — « quand je fais login with OAuth j'ai une 404 », et le « OU » de l'écran de login est mal placé.
**Cause racine (404)** : les routes câblées n'existent pas. Le contrôleur Immich est `@Controller('oauth')` : `POST /api/oauth/authorize` (body `OAuthConfigDto {redirectUri, state, codeChallenge}`) et `POST /api/oauth/callback` (body `OAuthCallbackDto {url, state, codeVerifier}`, réponse `LoginResponseDto`). Le code appelait `GET /api/auth/oauth/mobile` et `POST /api/auth/oauth/callback`. Vérifié contre `open-api/immich-openapi-specs.json` + `server/src/controllers/oauth.controller.ts`.
**Corrections** :
- `ImmichAPI.oauthAuthorize` (`/oauth/authorize`) + `.oauthCallback` ; protocole/client `authorizeOAuth(redirectURI:state:codeChallenge:)` et `exchangeOAuthCode(url:state:codeVerifier:)` ; `OAuthCallbackResponseDto`/`OAuthMobileResponseDto` supprimés au profit de `OAuthAuthorizeRequestDto`/`OAuthAuthorizeResponseDto`/`OAuthCallbackRequestDto` + `LoginResponseDto`.
- **PKCE obligatoire** : `Sources/Core/Utilities/OAuthPKCE.swift` (state + verifier 32 octets base64url + challenge = base64url(SHA256(verifier)) sans padding). La session navigateur ne partage pas les cookies posés par `authorize`, donc state/verifier sont rejoués au callback (même contrat que `OAuthService` Flutter).
- **Redirect URI** : `app.immich:///oauth-callback` (trois slashes) — la valeur publiée par la doc Immich, à whitelister chez le provider. L'ancienne à deux slashes ne matchait pas.
- **`ASWebAuthenticationSession` non retenue** : créée en variable locale, elle se désallouait avant de s'afficher (OAuthSessionPresenter). Session + `AnchorProvider` conservés dans des statiques jusqu'à la closure de complétion ; retour de `start()` vérifié + logs os.Logger catégorie "oauth".
- **Séparateur** : `Divider()` dans un `HStack` rend un trait vertical → `orRule` = `Rectangle().fill(Color.separatorPV).frame(height: 1)` + `.fixedSize()` sur le label.
**Tests** : `ImmichAPIClientTests` +3 (chemins `/api/oauth/authorize` et `/api/oauth/callback` + body décodé en JSON — pas de substring, `JSONEncoder` échappe `/` en `\/` ; challenge S256 piné sur un vecteur connu) ; `AuthViewModelTests` mis à jour (state partagé entre les deux legs, verifier ≠ challenge) ; `MockImmichClient` aligné. Suite **695 tests** + 2 UI, TEST SUCCEEDED.
**Vérification bout-en-bout** : harnais XCUITest `UITests/ImmichRenderScreenshots.swift` (target `ImmichSwiftUIUITests`) contre le stub local `/tmp/immich_stub_modes.py 8421` — onboarding → SSO → `ASWebAuthenticationSession` → shell authentifié (captures /tmp/shot-01..09). La page provider vit dans `com.apple.SafariViewService` (process séparé) : il faut un `XCUIApplication(bundleIdentifier:)` distinct pour taper « Authorize ». Le stub sert le HTML via `json.dumps` → il a fallu le corriger (`_send` encode les str en UTF-8 quand ctype est `text/*`). Sans stub, les tests se skippent (`XCTSkipUnless`) ; l'app persistant la session OAuth, `requireCleanSession()` skippe aussi un 2e run → `xcrun simctl erase` pour rejouer le walk complet.
**Fichiers** : Sources/Core/{Constants,Protocols/ImmichClient,Types/DTOs+Auth,Utilities/OAuthPKCE}.swift, Sources/Services/{ImmichAPIClient,OAuthSessionPresenter}.swift, Sources/Features/Auth/{AuthViewModel,Onboarding/LoginScreen}.swift ; docs : .omp/oauth2-ui/*, .opencode/scratch/{oauth,oauth2-ui,partners-ui}.acceptance.md, .omp/backlog, README{,.fr}.md, docs/{feature-parity-plan,immich-swiftui-feature-audit}.md.
