# Task: whats-new

Status: planifié — **aucune AC ouverte** (écart G23 du registre `.omp/backlog/ImmichSwiftUI-backlog.md` §2.17,
item 41 du plan des écarts, bande AC-5230–AC-5239).

## Plan (résumé)

**Objectif** : au premier lancement qui suit la publication d'une nouvelle série de nouveautés, présenter une feuille
« What's New » alimentée par un **catalogue embarqué**, ne plus y revenir une fois la série vue, et donner depuis le
hub « Me » une section About (version, réouverture de What's New, licences des dépendances réellement embarquées).

**Approche retenue** : A — catalogue **embarqué** (`FeatureHighlightCatalog` + release de contenu `"3.0.0"`), un
`WhatsNewStore` au-dessus d'`UserDefaults` qui ne persiste que la release vue, un `WhatsNewViewModel` mince sans état
propre, une vue de cartes unique servant la feuille automatique **et** l'ouverture à la demande depuis About, et un
écran de licences qui **charge les fichiers d'attribution présents dans le bundle** au lieu d'en recopier le texte.
L'upstream fait exactement le même choix : `featureMessageRelease` est une constante de contenu
(`mobile/lib/domain/models/feature_message.model.dart:39`, « Content-defined: bump it only when publishing a new batch,
never from the running app version ») et `grep -c featureMessage /tmp/immich-openapi-main.json` → `0`.

**Étapes** : (1) NEW `Sources/Features/WhatsNew/FeatureHighlight.swift` (`FeatureHighlight`, `FeatureHighlightCatalog.release`,
`static let all` — les cinq cas visibles sur iOS, `openInImmich` étant Android-only — et `isNewer(_:than:)` **numérique**) ;
(2) NEW `WhatsNewStore.swift` (clé `whatsNewSeenRelease`, défaut `"0.0.0"`, `shouldShow`, `markSeen()`) ; (3) NEW
`WhatsNewViewModel.swift` (`@MainActor @Observable`, délègue tout au store) ; (4) NEW `WhatsNewView.swift` (cartes, tuile
256 pt, repli SF Symbol, `onDone` → `Button("Done")` en `confirmationAction`, **aucun `NavigationStack`**) ; (5) EDIT
`Sources/DependencyContainer.swift` (store unique + `makeWhatsNewViewModel()`) ; (6) EDIT `Sources/RootView.swift`
(`@State whatsNew`, feuille automatique, `markSeen()` en `onDismiss`, `.task(id:)`) ; (7) EDIT
`Sources/Features/Auth/AuthViewModel.swift` (`applySession` marque la release : un compte neuf ne reçoit pas la série) ;
(8) NEW `Sources/Features/About/ThirdPartyLicense.swift` + `Resources/Acknowledgements/socket.io-client-swift.txt` +
EDIT `project.yml` (énumération de ressources explicite) ; (9) NEW `Sources/Features/About/LicensesView.swift` et
`AboutView.swift` ; (10) EDIT `Sources/Features/Profile/ProfileView.swift` (ligne `aboutRow` **avant** Security) ;
(11) NEW `Tests/WhatsNewViewModelTests.swift` (8 cas) et `Tests/ThirdPartyLicenseTests.swift` (2 cas) ;
(12) `xcodegen generate` + suite complète `-only-testing:ImmichSwiftUITests`.

**Incertitudes** : dépendances transitives à attribuer (`Starscream` traîne dans le `Package.swift` de
`socket.io-client-swift` — la liste est celle des checkouts résolus) ; chemin de copie de `Resources/Acknowledgements`
dans le bundle (groupe de ressources ou dossier-référence selon XcodeGen), tranché par le test de packaging ;
contenu des cinq cartes (une nouveauté non livrée — `ocr` relève de `.omp/ocr-text/` — doit sortir du catalogue, un
catalogue vide désactivant la feuille via `shouldShow`) ; release de contenu à publier ; comportement de `.task(id:)`
quand `AuthViewModel.userId` est `nil` ; choix de l'icône de la ligne About (`info.circle`, pour rester distinct de
`globe` et `gearshape.2`).

## Critères

```
### AC-5230 [type: new]
Assertion: les notes de version viennent d'un catalogue EMBARQUÉ — `Sources/Features/WhatsNew/FeatureHighlight.swift` avec `FeatureHighlight` et `FeatureHighlightCatalog.release` = "3.0.0" (constante de contenu, pas la version de l'app) comparaison numérique `isNewer` — et aucun transport réseau n'entre dans la feature, donc l'écran s'ouvre hors ligne.
Check post-impl: sh -c 'd=Sources/Features/WhatsNew; a=Sources/Features/About; f=$d/FeatureHighlight.swift; test -f "$f" && grep -qE "struct FeatureHighlight:" "$f" && grep -qE "enum FeatureHighlightCatalog" "$f" && grep -qE "static let release" "$f" && grep -qE "3[.]0[.]0" "$f" && grep -qE "static let all" "$f" && grep -qE "static func isNewer" "$f" && grep -qE "components\(separatedBy" "$f" && grep -qE "shareQuality" "$f" && grep -qE "uploadToAlbum" "$f" && ! grep -qE "openInImmich" "$f" && test -d "$a" && ! grep -rqE "URLRequest|URLSession|ImmichClient|ImmichAPIClient|featureMessage|FeatureMessageDto" "$d" "$a" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/WhatsNew/` et `Sources/Features/About/` n'existent pas ; `grep -rn "WhatsNew\|whatsNew\|FeatureHighlight" Sources/` → 0 ligne, et `grep -c featureMessage` sur l'OpenAPI publié → 0, donc aucun endpoint de rechange n'existe)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION (`struct FeatureHighlight:`, `enum FeatureHighlightCatalog`) — un doc-comment qui citerait ces noms ne suffit pas ; et il exige la comparaison par `components(separatedBy`, pas un `compare(_:)` lexicographique.
```

```
### AC-5231 [type: new]
Assertion: la règle « affiché une seule fois par version » vit entièrement dans `WhatsNewStore` : le dernier numéro vu est persisté dans `UserDefaults` sous la clé "whatsNewSeenRelease", un utilisateur qui n'a rien vu vaut "0.0.0", `shouldShow` compare la release de contenu à cet état et `markSeen()` écrit la release courante.
Check post-impl: sh -c 'f=Sources/Features/WhatsNew/WhatsNewStore.swift; test -f "$f" && grep -qE "struct WhatsNewStore" "$f" && grep -qE "static let seenReleaseKey" "$f" && grep -qE "whatsNewSeenRelease" "$f" && grep -qE "let defaults: UserDefaults" "$f" && grep -qE "var seenRelease" "$f" && grep -qE "0[.]0[.]0" "$f" && grep -qE "var shouldShow" "$f" && grep -qE "FeatureHighlightCatalog[.]isNewer" "$f" && grep -qE "func markSeen" "$f" && grep -qE "defaults[.]set" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `grep -rn "seenRelease\|WhatsNewStore" Sources/ Tests/` → 0 ligne)
Post-state attendu: PASS
Note: `UserDefaults` est INJECTÉ (`let defaults: UserDefaults`, patron `BackupSettingsStore(suiteName:)`) pour que les tests utilisent une suite jetable ; la clé est une constante partagée — `AuthViewModel` s'en sert à l'étape suivante.
```

```
### AC-5232 [type: new]
Assertion: `WhatsNewViewModel` est un `@MainActor @Observable` mince qui n'a AUCUN état propre — « vu / pas vu » est relu du store à chaque appel — et expose le catalogue, la release de contenu, la release vue, `shouldPresentAutomatically()` et `markSeen()`.
Check post-impl: sh -c 'f=Sources/Features/WhatsNew/WhatsNewViewModel.swift; test -f "$f" && grep -qE "@MainActor" "$f" && grep -qE "@Observable" "$f" && grep -qE "final class WhatsNewViewModel" "$f" && grep -qE "private let store: WhatsNewStore" "$f" && grep -qE "init\(store:" "$f" && grep -qE "let highlights = FeatureHighlightCatalog[.]all" "$f" && grep -qE "let release = FeatureHighlightCatalog[.]release" "$f" && grep -qE "var seenRelease" "$f" && grep -qE "store[.]seenRelease" "$f" && grep -qE "func shouldPresentAutomatically" "$f" && grep -qE "store[.]shouldShow" "$f" && grep -qE "func markSeen" "$f" && grep -qE "store[.]markSeen" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: l'assertion discriminante est la double délégation `store.seenRelease` / `store.shouldShow` / `store.markSeen` : un view model qui recopierait l'état en mémoire se désynchroniserait du store relu au lancement suivant.
```

```
### AC-5233 [type: new]
Assertion: `WhatsNewView` rend les cartes du catalogue depuis une liste paresseuse, fournit le repli SF Symbol quand l'asset est absent, et n'enveloppe RIEN dans un `NavigationStack` (elle est poussée depuis About, qui vit dans le stack de ProfileView) ; elle ne porte le bouton « Done » que lorsqu'elle est présentée en feuille (`onDone` non nul).
Check post-impl: sh -c 'f=Sources/Features/WhatsNew/WhatsNewView.swift; test -f "$f" && grep -qE "struct WhatsNewView: View" "$f" && grep -qE "@Bindable var vm: WhatsNewViewModel" "$f" && grep -qE "ScrollView" "$f" && grep -qE "LazyVStack" "$f" && grep -qE "ForEach\(vm[.]highlights\)" "$f" && grep -qE "imageName" "$f" && grep -qE "Image\(systemName" "$f" && grep -qE "var onDone" "$f" && grep -qE "confirmationAction" "$f" && ! grep -qE "NavigationStack \{" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
Note: le check vise la DÉCLARATION (`NavigationStack {`) et non le mot seul — un doc-comment expliquant l'absence de stack ferait échouer un grep littéral, comme constaté sur la carte sync-status (AC-5031).
```

```
### AC-5234 [type: new]
Assertion: la ligne du hub existe — `ProfileView` reçoit `whatsNew`, rend une ligne identifiée `aboutRow` qui pousse `AboutView(whatsNew:)` — et `AboutView` donne la version réelle du bundle plus les deux liens identifiés `aboutWhatsNewRow` et `aboutLicensesRow`.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; test -f "$f" && grep -qE "var whatsNew: WhatsNewViewModel" "$f" && grep -qE "aboutRow" "$f" && grep -qE "AboutView\(whatsNew:" "$f" && g=Sources/Features/About/AboutView.swift && test -f "$g" && grep -qE "struct AboutView: View" "$g" && grep -qE "CFBundleShortVersionString" "$g" && grep -qE "CFBundleVersion" "$g" && grep -qE "aboutWhatsNewRow" "$g" && grep -qE "aboutLicensesRow" "$g" && grep -qE "WhatsNewView\(vm:" "$g" && grep -qE "LicensesView\(\)" "$g" && ! grep -qE "NavigationStack \{" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`ProfileView.swift` ne contient ni `aboutRow` ni `AboutView` ; `Sources/Features/About/` n'existe pas ; `grep -rn "AboutView" Sources/` → 0 ligne)
Post-state attendu: PASS
Note: la section About s'insère APRÈS Administration et AVANT Security — l'ordre n'est pas vérifiable par ce grep, il l'est en revue ; le critère mesurable est que la ligne et les deux identifiants existent, et qu'AboutView ne déclare pas de stack.
```

```
### AC-5235 [type: new]
Assertion: la composition root fabrique le store UNE fois et la feuille automatique est câblée dans `AuthenticatedRoot` : le view model est injecté par le conteneur, la présentation est évaluée à la connexion et marquée vue à la fermeture, quel que soit le mode de fermeture (`onDismiss` couvre le balayage vers le bas).
Check post-impl: sh -c 'f=Sources/DependencyContainer.swift; test -f "$f" && grep -qE "func makeWhatsNewViewModel" "$f" && grep -qE "WhatsNewStore\(defaults:" "$f" && g=Sources/RootView.swift && test -f "$g" && grep -qE "whatsNew: WhatsNewViewModel" "$g" && grep -qE "makeWhatsNewViewModel\(\)" "$g" && grep -qE "showWhatsNew" "$g" && grep -qE "onDismiss" "$g" && grep -qE "whatsNew[.]markSeen" "$g" && grep -qE "\.task\(id:" "$g" && grep -qE "WhatsNewView\(vm: whatsNew" "$g" && grep -qE "whatsNew: whatsNew" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune factory WhatsNew ; `RootView.swift` ne contient ni `showWhatsNew` ni `makeWhatsNewViewModel()`)
Post-state attendu: PASS
Note: `markSeen()` est en `onDismiss` et non dans le bouton Done — sinon un balayage vers le bas ferait réapparaître la feuille au lancement suivant. La feuille vit dans `AuthenticatedRoot`, seul présentateur stable (`Sources/RootView.swift:82,114,233-235`).
```

```
### AC-5236 [type: new]
Assertion: l'ajout d'un compte marque la release courante comme vue, dans le chemin de session lui-même (`applySession`, partagé par le login mot de passe et par OAuth) et NON dans `restoreSession()` — un compte fraîchement ajouté ne reçoit pas une série rédigée avant lui, mais une session restaurée après mise à jour reçoit bien la série neuve.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; test -f "$f" && grep -qE "WhatsNewStore[.]seenReleaseKey" "$f" && grep -qE "FeatureHighlightCatalog[.]release" "$f" && awk "/private func applySession/,/^    }/" "$f" | grep -qE "WhatsNewStore[.]seenReleaseKey" && ! awk "/func restoreSession/,/^    }/" "$f" | grep -qE "WhatsNewStore" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`applySession` (`:330-345`) et `restoreSession` (`:120`) écrivent bien dans `defaults`, mais aucune occurrence de `WhatsNewStore`/`FeatureHighlightCatalog` n'existe dans le fichier : `awk` sur `applySession` → 0 ligne)
Post-state attendu: PASS
Note: les deux `awk` bornent la fonction (corps fermé à quatre espaces d'indentation) — c'est le seul moyen de distinguer les deux chemins de session, que la spec oppose explicitement ; un grep global sur le fichier passerait même si l'écriture était posée au mauvais endroit.
```

```
### AC-5237 [type: new]
Assertion: les licences affichées sont les fichiers d'attribution RÉELLEMENT embarqués : `ThirdPartyLicense.licenseText(for:)` lit une ressource du bundle, le fichier de la dépendance SPM est présent dans `Resources/Acknowledgements/`, ce dossier est énuméré dans `project.yml` (sinon il n'est pas copié) et aucun texte de licence n'est recopié dans le Swift.
Check post-impl: sh -c 'f=Sources/Features/About/ThirdPartyLicense.swift; test -f "$f" && grep -qE "struct ThirdPartyLicense" "$f" && grep -qE "static let all" "$f" && grep -qE "resourceName" "$f" && grep -qE "func licenseText" "$f" && grep -qE "Bundle[.]main[.]url\(forResource:" "$f" && grep -qE "socket" "$f" && ! grep -qE "Permission is hereby granted" "$f" Sources/Features/About/LicensesView.swift && test -f Resources/Acknowledgements/socket.io-client-swift.txt && grep -qE "path: Resources/Acknowledgements" project.yml && g=Sources/Features/About/LicensesView.swift && test -f "$g" && grep -qE "struct LicensesView: View" "$g" && grep -qE "DisclosureGroup" "$g" && grep -qE "monospaced" "$g" && grep -qE "textSelection" "$g" && grep -qE "licenseMissingRow" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Features/About/` absent, `Resources/Acknowledgements` absent, `grep -n "Acknowledgements" project.yml` → 0 ligne ; `Resources/` ne contient que `Assets.xcassets`, `Localizable.xcstrings`, `TeslaCar.usdz`, `Info.plist` et les entitlements)
Post-state attendu: PASS
Note: un échec de chargement doit produire la ligne identifiée `licenseMissingRow` — c'est ce qui rend visible une panne de packaging plutôt qu'un écran silencieusement vide. Le texte de licence n'est jamais recopié dans le Swift : le fichier embarqué est la copie exacte livrée par le paquet.
```

```
### AC-5238 [type: new]
Assertion: les tests unitaires couvrent la persistance de la règle « une fois par version » et la comparaison de versions NUMÉRIQUE — `"3.10.0"` doit battre `"3.9.0"`, ce qu'une comparaison lexicographique rate dès la dixième mineure — et le packaging des licences est prouvé par un test qui résout chaque licence déclarée dans le bundle.
Check post-impl: sh -c 'f=Tests/WhatsNewViewModelTests.swift; n=0; test -f "$f" && n=$(grep -cE "func test_" "$f") && test "$n" -ge 8 && grep -qE "test_shouldShow_whenNothingSeenYet" "$f" && grep -qE "test_shouldShow_isFalse_onceMarked" "$f" && grep -qE "test_markSeen_writesTheCatalogRelease" "$f" && grep -qE "test_isNewer_isNumericNotLexicographic" "$f" && grep -qE "3[.]10[.]0" "$f" && grep -qE "test_isNewer_isFalse_forAnOlderOrEqualRelease" "$f" && grep -qE "test_catalog_excludesTheAndroidOnlyHighlight" "$f" && grep -qE "test_catalog_hasNoDuplicateIdentifiers" "$f" && grep -qE "test_highlights_haveNonEmptyTitleAndBody" "$f" && grep -qE "UserDefaults\(suiteName:" "$f" && g=Tests/ThirdPartyLicenseTests.swift && test -f "$g" && grep -qE "test_everyDeclaredLicense_resolvesToANonEmptyBundledFile" "$g" && grep -qE "test_socketIO_isDeclared" "$g" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (les deux fichiers de tests sont absents ; `n=0` précède le `test -f` pour que le compteur ne soit jamais comparé vide)
Post-state attendu: PASS
Note: `test_shouldShow_isFalse_onceMarked` doit RELIRE le store (pas seulement le view model) ; un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passerait verte par omission.
```

```
### AC-5239 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'f=/tmp/immich_whatsnew_test.log; n=0; test -f "$f" && grep -qE "TEST SUCCEEDED" "$f" && n=$(grep -oE "Executed [0-9]+ tests" "$f" | grep -oE "[0-9]+" | sort -n | tail -1) && [ -n "$n" ] && test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent — `n=0` et le garde `[ -n "$n" ]` évitent le `test: : integer expression expected` du relevé non borné)
Post-state attendu: PASS
```
