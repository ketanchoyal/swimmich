# Task: share-extension

Status: planifié — **aucune AC ouverte** (écart G21 du registre `.omp/backlog/ImmichSwiftUI-backlog.md` : aucune
cible `com.apple.share-services` dans `project.yml`, aucune entrée depuis la feuille de partage d'iOS).

## Plan (résumé)

**Objectif** : sélectionner des photos/vidéos dans Photos, Messages ou Safari, choisir « Immich » dans la feuille
de partage, et voir une extension système lister les pièces jointes avec un sélecteur d'album et un bouton Upload
suivant l'état de chaque envoi (en file / en cours / terminé / échec) ; l'upload part du processus de l'extension
vers `POST /api/assets`, l'app peut rester fermée.

**Approche retenue** : A — cible d'extension native `ImmichShareExtension` (`NSExtensionPointIdentifier =
com.apple.share-services`, classe principale `ShareViewController`) dont le transport et le modèle de session sont
ajoutés à `ImmichSharedKit` (seul framework partageable : l'app compile `Sources/` en bloc, une extension ne peut
pas embarquer `Sources/Features/**`), l'upload se faisant depuis le processus de l'extension avec la session lue
dans le Keychain.

**Étapes** : (1) NEW `Resources/ImmichShareExtension.entitlements` (groupe Keychain de l'app) ; (2) NEW
`ImmichShareExtension/Info.plist` (share-services + règle d'activation image/movie + ATS) ; (3) EDIT `project.yml`
(cible, embed dans l'app, scheme) ; (4) déplacement de `MultipartBody` vers `ImmichSharedKit` en `public` ;
(5) `WidgetSession.deviceId` + écriture depuis `AuthViewModel.publishWidgetSession()` ; (6) NEW
`Sources/ImmichSharedKit/SharedUploadClient.swift` (upload multipart + albums) ; (7) NEW `ShareItem`,
`ShareExtensionViewModel`, `ShareConfirmationView`, `ShareViewController` ; (8) NEW `Tests/ShareUploadClientTests`
et `Tests/ShareExtensionViewModelTests` ; (9) `xcodegen generate` + suite.

**Incertitudes** : capacité « Keychain Sharing » de l'App ID de l'extension (sans elle iOS refuse de lancer le
processus, invisible sur simulateur — même piège que le groupe du widget) ; champ `albumName` d'`AlbumResponseDto` ;
budget d'extension pour une vidéo volumineuse (aucune reprise prévue, hors périmètre).

## Critères

```
### AC-5210 [type: new]
Assertion: `project.yml` déclare la cible d'extension `ImmichShareExtension` (type app-extension, bundle id, Info.plist, entitlements), l'embarque dans l'app et la construit dans le scheme — sinon une cible non listée n'est jamais buildée.
Check post-impl: sh -c 'f=project.yml; grep -qE "^  ImmichShareExtension:" "$f" && grep -qE "type: app-extension" "$f" && grep -qE "PRODUCT_BUNDLE_IDENTIFIER: fr.millianlmx.immich-ios.share-extension" "$f" && grep -qE "path: ImmichShareExtension/Info.plist" "$f" && grep -qE "CODE_SIGN_ENTITLEMENTS: Resources/ImmichShareExtension.entitlements" "$f" && grep -qE "NSExtensionPointIdentifier: com.apple.share-services" "$f" && grep -qE "ImmichShareExtension: all" "$f" && test -f Resources/ImmichShareExtension.entitlements && grep -qE "keychain-access-groups" Resources/ImmichShareExtension.entitlements && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`project.yml` ne contient aucune occurrence de « ShareExtension » ni de « com.apple.share-services », et `Resources/ImmichShareExtension.entitlements` n'existe pas)
Post-state attendu: PASS
```

```
### AC-5211 [type: new]
Assertion: l'Info.plist de l'extension est un point d'entrée share-services sans storyboard, dont la classe principale est `ShareViewController` du module, avec la règle d'activation image/movie et l'ATS permissif (un Immich auto-hébergé en HTTP simple sur le LAN est bloqué par ATS dans le processus de l'extension, jamais sur loopback).
Check post-impl: sh -c 'f=ImmichShareExtension/Info.plist; test -f "$f" && grep -qE "com.apple.share-services" "$f" && grep -qE "PRODUCT_MODULE_NAME" "$f" && grep -qE "ShareViewController" "$f" && grep -qE "NSExtensionActivationRule" "$f" && grep -qE "public.image" "$f" && grep -qE "public.movie" "$f" && grep -qE "NSAllowsArbitraryLoads" "$f" && grep -qE "PHSupportedMediaTypes" "$f" && grep -qE "CFBundleDisplayName" "$f" && ! grep -qE "NSExtensionMainStoryboard" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — aucun `ImmichShareExtension/Info.plist` dans le dépôt)
Post-state attendu: PASS
```

```
### AC-5212 [type: new]
Assertion: les quatre fichiers Swift de l'extension existent avec leurs symboles : le modèle d'item (états miroirs de l'écran Flutter d'upload), le ViewModel `@Observable`, l'écran de confirmation et le contrôleur.
Check post-impl: sh -c 'd=ImmichShareExtension; test -f "$d/ShareItem.swift" && grep -qE "struct ShareItem" "$d/ShareItem.swift" && grep -qE "enum ShareItemStatus" "$d/ShareItem.swift" && grep -qE "case enqueued" "$d/ShareItem.swift" && grep -qE "case running" "$d/ShareItem.swift" && grep -qE "case complete" "$d/ShareItem.swift" && grep -qE "case failed" "$d/ShareItem.swift" && test -f "$d/ShareExtensionViewModel.swift" && grep -qE "@Observable" "$d/ShareExtensionViewModel.swift" && grep -qE "final class ShareExtensionViewModel" "$d/ShareExtensionViewModel.swift" && grep -qE "init\(uploader:" "$d/ShareExtensionViewModel.swift" && grep -qE "var canUpload" "$d/ShareExtensionViewModel.swift" && grep -qE "func uploadAll" "$d/ShareExtensionViewModel.swift" && grep -qE "func loadAlbums" "$d/ShareExtensionViewModel.swift" && grep -qE "func toggle" "$d/ShareExtensionViewModel.swift" && test -f "$d/ShareConfirmationView.swift" && test -f "$d/ShareViewController.swift" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (dossier `ImmichShareExtension/` inexistant)
Post-state attendu: PASS
```

```
### AC-5213 [type: new — session partagée par le Keychain]
Assertion: la session voyage par l'item Keychain existant du widget, et non par un App Group : `WidgetSession` porte désormais l'identifiant d'installation (illisible depuis le conteneur de l'extension car `DeviceIdentity` lit les `UserDefaults` de l'app), l'app l'écrit au même endroit unique qu'aujourd'hui, et l'extension le lit avec le même droit d'accès.
Check post-impl: sh -c 's=Sources/ImmichSharedKit/WidgetSession.swift; u=Sources/Features/Auth/AuthViewModel.swift; c=ImmichShareExtension/ShareViewController.swift; grep -qE "public var deviceId: String" "$s" && grep -qE "deviceId: String\? = nil" "$s" && grep -qE "deviceId: DeviceIdentity.current" "$u" && grep -qE "WidgetSessionStore" "$c" && grep -qE "keychain-access-groups" Resources/ImmichShareExtension.entitlements && grep -qE "keychain-access-groups" Resources/ImmichWidgets.entitlements && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`WidgetSession.swift` n'expose aucun `deviceId` — champs relevés : baseURL, token, userName, userId, trustedHosts — et `AuthViewModel.publishWidgetSession()` ne passe pas d'identifiant d'appareil)
Post-state attendu: PASS
```

```
### AC-5214 [type: new — chemin d'upload dans le processus de l'extension]
Assertion: `ShareUploadClient` (dans `ImmichSharedKit`, seul framework visible d'une extension) poste un multipart streamé sur `POST /api/assets` avec le Bearer, le champ `assetData`, les quatre champs de date/appareil et le checksum SHA1 base64 ; `MultipartBody` est devenu partagé et public (il recopie le fichier par blocs, ce qui rend tenable l'upload d'une vidéo en budget d'extension réduit) et son ancien emplacement app a disparu.
Check post-impl: sh -c 'f=Sources/ImmichSharedKit/SharedUploadClient.swift; m=Sources/ImmichSharedKit/MultipartBody.swift; test -f "$f" && grep -qE "public protocol ShareUploading" "$f" && grep -qE "public struct SharedUploadClient" "$f" && grep -qE "public enum ShareUploadError" "$f" && grep -qE "api/assets" "$f" && grep -qE "assetData" "$f" && grep -qE "fileCreatedAt" "$f" && grep -qE "fileModifiedAt" "$f" && grep -qE "deviceAssetId" "$f" && grep -qE "deviceId" "$f" && grep -qE "Authorization" "$f" && grep -qE "Bearer" "$f" && grep -qE "x-immich-checksum" "$f" && grep -qE "Insecure.SHA1" "$f" && grep -qE "uploadTask" "$f" && grep -qE "WidgetDataProvider" "$f" && grep -qE "public struct MultipartBody" "$m" && grep -qE "public mutating func writeStreamed" "$m" && ! test -f Sources/Services/MultipartBody.swift && grep -qE "MultipartBody" Sources/Services/ImmichAPIClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Sources/Services/MultipartBody.swift` porte `struct MultipartBody` en interne — l.4 — et aucun `Sources/ImmichSharedKit/SharedUploadClient.swift` n'existe)
Post-state attendu: PASS
Note: les deux derniers termes vont ensemble — l'ancien fichier disparaît (`Sources/Services/ImmichAPIClient.swift:619` construit aujourd'hui `MultipartBody()` et `JSONCoding.swift:71` en porte l'extension) mais le seul appelant de l'app continue de référencer le type : le fichier déplacé reste compilé par la cible app, qui compile `Sources` en bloc (`project.yml:20`), donc aucun appelant ne bouge et le type reste visible sans `import ImmichSharedKit` (le kit est compilé deux fois).
```

```
### AC-5215 [type: new — rattachement à l'album]
Assertion: le client expose la liste des albums (nom lu depuis `albumName`) et le rattachement des assets téléversés, sérialisé en `{"ids": [...]}` sur `PUT /api/albums/{id}/assets`, appelé après coup par le ViewModel et seulement si un album est sélectionné.
Check post-impl: sh -c 'f=Sources/ImmichSharedKit/SharedUploadClient.swift; v=ImmichShareExtension/ShareExtensionViewModel.swift; grep -qE "public struct ShareAlbum" "$f" && grep -qE "albumName" "$f" && grep -qE "func albums" "$f" && grep -qE "api/albums" "$f" && grep -qE "func addAssets" "$f" && grep -qE "selectedAlbumId" "$v" && grep -qE "addAssets" "$v" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun fichier de client partagé ; le seul rattachement existant est `ImmichAPIClient.addAssetsToAlbum(albumId:dto:)`, dans la cible app, invisible d'une extension)
Post-state attendu: PASS
```

```
### AC-5216 [type: new — écran de confirmation sans logique métier]
Assertion: l'écran de confirmation est une projection pure du ViewModel : sélecteur d'album (« Aucun album » = pas d'album), progression par item, bouton conditionné par `canUpload`, bandeau d'erreur — et ne connaît aucun transport (pas de `ShareUploading` dans la vue).
Check post-impl: sh -c 'f=ImmichShareExtension/ShareConfirmationView.swift; test -f "$f" && grep -qE "struct ShareConfirmationView" "$f" && grep -qE "ShareExtensionViewModel" "$f" && grep -qE "Picker" "$f" && grep -qE "ProgressView" "$f" && grep -qE "canUpload" "$f" && grep -qE "errorMessage" "$f" && grep -qE "serverLabel" "$f" && ! grep -qE "ShareUploading" "$f" && ! grep -qE "URLSession|URLRequest" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-5217 [type: new — ce qui est testable hors extension]
Assertion: les tests du kit et du ViewModel existent : le multipart (champ `assetData`, Bearer, checksum), le décodage `status: duplicate` et l'échec serveur sont testés via `CapturingURLProtocol` ; l'ordre des états et l'appel conditionnel à `addAssets` sont testés avec un double de `ShareUploading` — et aucun test n'importe `ImmichSharedKit` (le kit est compilé deux fois, l'import rendrait chaque symbole ambigu).
Check post-impl: sh -c 'a=Tests/ShareUploadClientTests.swift; b=Tests/ShareExtensionViewModelTests.swift; test -f "$a" && test -f "$b" && grep -qE "@testable import ImmichSwiftUI" "$a" && grep -qE "@testable import ImmichSwiftUI" "$b" && grep -qE "CapturingURLProtocol" "$a" && grep -qE "assetData" "$a" && grep -qE "x-immich-checksum" "$a" && grep -qE "duplicate" "$a" && grep -qE "401" "$a" && grep -qE "ShareUploading" "$b" && grep -qE "addAssets" "$b" && ! grep -rqE "import ImmichSharedKit" Tests && n=$(grep -cE "func test_" "$a"); m=$(grep -cE "func test_" "$b"); test "$n" -ge 4 && test "$m" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (les deux fichiers n'existent pas ; `Tests/` n'a pas de test de client partagé)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` — sans régénération la suite passe « verte » par omission.
```

```
### AC-5218 [type: new — refus propre quand aucune session n'est disponible]
Assertion: utilisateur déconnecté (ou session absente du Keychain) : le contrôleur ne tente aucun upload, lit la session, retient les pièces jointes image/movie en les copiant dans le conteneur de l'extension pendant que celui de l'app hôte est encore lisible, et dispose des deux seules sorties autorisées d'une extension (`cancelRequest` / `completeRequest`).
Check post-impl: sh -c 'f=ImmichShareExtension/ShareViewController.swift; test -f "$f" && grep -qE "final class ShareViewController" "$f" && grep -qE "UIViewController" "$f" && grep -qE "extensionContext" "$f" && grep -qE "loadFileRepresentation" "$f" && grep -qE "temporaryDirectory" "$f" && grep -qE "WidgetSessionStore" "$f" && grep -qE "guard let session|if let session|session == nil" "$f" && grep -qE "UIHostingController" "$f" && grep -qE "cancelRequest\(withError:" "$f" && grep -qE "completeRequest\(returningItems:" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `grep -rn "share-services" Sources/ project.yml` ne renvoie rien)
Post-state attendu: PASS
```

```
### AC-5219 [type: regression]
Assertion: l'app reste compilable et la suite complète passe au-dessus de la baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`), le déplacement de `MultipartBody` et le nouveau `Sources/ImmichSharedKit/*` n'ayant cassé ni la cible app ni la cible widget.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_share_extension_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_share_extension_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
