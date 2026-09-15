# Task: folder-view

Status: planifié — **aucune AC ouverte** (écart G11 du registre `.omp/backlog/ImmichSwiftUI-backlog.md` §2.17).

## Plan (résumé)

**Objectif** : écran « Folders » atteint depuis la section Management du hub « Me » : un niveau de
dossiers par écran, fil d'Ariane monospace, grille des assets **directement contenus** dans le dossier
courant, ouverture au viewer dans l'ordre affiché, inverseur de tri, rafraîchissement par dossier.

**Approche retenue** : A — deux méthodes neuves sur `ImmichClient` (`getFolderAssets(path:)`,
`getUniqueFolderPaths()`) derrière un `SubPath` `ImmichAPI.view`, un `FolderViewModel` unique qui construit
l'arbre une fois (`buildTree(from:)`, fonction pure) et cache les assets par chemin, une `FolderView`
stateless poussée **par valeur** (`navigationDestination(for: FolderNode.self)`) depuis `ProfileView`.
**B rejetée** : un écran unique dépliant tout l'arbre — des dizaines de milliers de lignes sur une
bibliothèque externe (l'upstream pousse une page par niveau). **C rejetée** : lire les assets d'un dossier
par `POST /api/search/metadata` (`originalPath`) — champ **déprécié** en v3.2.0, sémantique « enfants
directs » (`LIKE '%<p>/%' AND NOT LIKE '%<p>/%/%'`) non exprimable, et pagination payée pour rien
(`/view/folder` ne pagine pas).

**Étapes** : 12 (voir `.omp/folder-view/folder-view.specs.md`) — `ImmichAPI.view`, protocole, client HTTP,
doublons de mock, `FolderViewModel.swift`, `FolderView.swift`, factory, `RootView`, ligne du hub,
`Tests/FolderViewModelTests.swift`, catalogue i18n, `xcodegen` + suite.

**Incertitudes** : appel au niveau supérieur quand des assets sont posés à la racine du disque (`''`) ;
tri des noms de dossiers (A→Z local vs parité littérale) ; volume d'un dossier très peuplé (la route ne
pagine pas).

## Critères

```
### AC-5100 [type: new]
Assertion: le contrat de transport expose les deux routes de dossiers derrière un SubPath `/view` (qui n'existait pas).
Check post-impl: sh -c 'c=Sources/Core/Constants.swift; p=Sources/Core/Protocols/ImmichClient.swift; grep -qE "let view = SubPath\(root: \"/view\"\)" "$c" && grep -qE "func getFolderAssets\(path: String\) async throws -> \[AssetResponseDto\]" "$p" && grep -qE "func getUniqueFolderPaths\(\) async throws -> \[String\]" "$p" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -n "view" Sources/Core/Constants.swift` ne montre aucun SubPath `/view` ; aucune déclaration ne nomme un dossier dans le protocole)
Post-state attendu: PASS
```

```
### AC-5101 [type: new]
Assertion: l'implémentation HTTP appelle réellement `/view/folder` avec le paramètre `path` et `/view/folder/unique-paths` sans paramètre.
Check post-impl: sh -c 'f=Sources/Services/ImmichAPIClient.swift; grep -qE "ImmichAPI.view.path\(\"/folder\"\)" "$f" && grep -qE "URLQueryItem\(name: \"path\", value: path\)" "$f" && grep -qE "ImmichAPI.view.path\(\"/folder/unique-paths\"\)" "$f" && ! grep -qE "/api/folders" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier sans aucune occurrence de `/view`)
Post-state attendu: PASS
Note: `/api/folders` n'existe pas dans l'OpenAPI publié — le check verrouille l'absence de cette route inventée.
```

```
### AC-5102 [type: new]
Assertion: le mock de test enregistre le chemin réellement envoyé et expose une paire réponse/erreur par route (seul moyen de prouver le contrat de fil).
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -qE "requestedFolderPaths" "$f" && grep -qE "folderPathsResponse" "$f" && grep -qE "folderPathsError" "$f" && grep -qE "folderAssetsResponse" "$f" && grep -qE "folderAssetsError" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-5103 [type: new]
Assertion: FolderViewModel construit l'arbre par une fonction PURE et cache les assets par chemin, avec les deux axes de tri.
Check post-impl: sh -c 'f=Sources/Features/Folders/FolderViewModel.swift; test -f "$f" && grep -qE "struct FolderNode" "$f" && grep -qE "enum FolderSortOrder" "$f" && grep -qE "static func buildTree\(from paths: \[String\]\)" "$f" && grep -qE "hasRootLevelAssets" "$f" && grep -qE "assetsByPath" "$f" && grep -qE "func toggleAssetOrder" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/` n'a aucun dossier `Folders`)
Post-state attendu: PASS
```

```
### AC-5104 [type: new]
Assertion: le chargement est paresseux et borné — l'arbre n'est construit qu'une fois, les assets d'un chemin sont mis en cache, et le chemin est envoyé au serveur TEL QUEL (slash initial conservé : le serveur ne normalise que les slashes finaux).
Check post-impl: sh -c 'f=Sources/Features/Folders/FolderViewModel.swift; grep -qE "func loadTree\(\) async" "$f" && grep -qE "func loadAssets\(for path: String, force: Bool = false\) async" "$f" && grep -qE "func retryTree\(\) async" "$f" && ! grep -qE "substring\(1\)|dropFirst" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-5105 [type: new]
Assertion: FolderView est poussée par valeur, ne déclare AUCUN NavigationStack, porte le fil d'Ariane monospace et les identifiants d'accessibilité attendus.
Check post-impl: sh -c 'f=Sources/Features/Folders/FolderView.swift; test -f "$f" && grep -qE "struct FolderView" "$f" && grep -qE "navigationDestination\(for: FolderNode.self\)" "$f" && grep -qE "design: .monospaced" "$f" && grep -qE "folderRow_" "$f" && grep -qE "folderSortButton" "$f" && grep -qE "foldersEmptyState" "$f" && grep -qE "foldersRetryButton" "$f" && ! grep -qE "NavigationStack \{" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION `NavigationStack {` — un grep du seul mot matcherait le doc-comment qui explique l'absence de stack.
```

```
### AC-5106 [type: new]
Assertion: l'écran est construit par le composition root, matérialisé en `@State` par RootView, et atteint par une ligne du hub « Me » (après Offline Storage, dans Management).
Check post-impl: sh -c 'd=Sources/DependencyContainer.swift; r=Sources/RootView.swift; p=Sources/Features/Profile/ProfileView.swift; grep -qE "func makeFolderViewModel\(\) -> FolderViewModel" "$d" && grep -qE "makeFolderViewModel" "$r" && grep -qE "folders: FolderViewModel" "$r" && grep -qE "FolderView\(vm: folders, node: nil\)" "$p" && grep -qE "foldersRow" "$p" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-5107 [type: new]
Assertion: FolderViewModelTests couvre l'arbre, le cache par chemin, le tri en mémoire et la remontée d'erreur, dont un cas qui verrouille le chemin envoyé au serveur.
Check post-impl: sh -c 'f=Tests/FolderViewModelTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 9 && grep -qE "test_buildTree_groupsPathsByLevel" "$f" && grep -qE "test_buildTree_flagsRootLevelAssets" "$f" && grep -qE "test_loadAssets_sendsTheFolderPathAsIs" "$f" && grep -qE "test_loadAssets_cachesPerPath" "$f" && grep -qE "test_toggleAssetOrder_reordersInMemoryWithoutRefetching" "$f" && grep -qE "test_loadTree_surfacesError" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate`)
Post-state attendu: PASS
```

```
### AC-5108 [type: new — l'arbre n'est pas recalculé à chaque niveau]
Assertion: descendre d'un niveau ne relance pas `unique-paths` : `loadTree()` sort immédiatement quand l'arbre est déjà là, et un rafraîchissement ne relance que les assets du dossier courant.
Check post-impl: sh -c 'f=Sources/Features/Folders/FolderViewModel.swift; grep -qE "guard root == nil" "$f" && grep -qE "func refresh\(path: String\) async" "$f" && grep -qE "force: true" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-5109 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_folderview_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_folderview_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
