# Task: push-notifications — autorisation des notifications (issue #16, P5)

Status: implémenté — **8/8 AC PASS** (2026-09-13)

## Pourquoi la carte d'origine est morte

La carte (AC-3300…AC-3308) spécifiait une pile **APNs** : `registerDevice()` /
`unregisterDevice()` / `handlePush(payload:)` contre un
`POST /api/users/me/device-token`. Vérifié le 2026-09-13 — **rien de tout cela
n'existe** :

| Affirmation | Réalité |
|---|---|
| `POST /api/users/me/device-token` à ajouter | **0 occurrence** dans l'OpenAPI publié (`main`, `v1.135.0`). Aucun schéma APNs/push. Le serveur n'expose que `/notifications` (GET/PUT/DELETE), `/notifications/{id}`, `/admin/notifications*` |
| « Parity with Flutter client » | Le client Flutter n'a **aucun** push : `mobile/pubspec.yaml` = `flutter_local_notifications` (local) + `socket_io_client`, pas de `firebase_messaging`. `NotificationDto` n'a qu'un consommateur, le client **web** (`web/src/lib/stores/notification-manager.svelte.ts`) |
| « ImmichSwiftUI has no UNUserNotificationCenter handling » | Faux : `BackupNotificationService` (notif locale de fin de run) existe depuis la card backup |
| `PushNotificationSettingsView` avec toggles backup/activity/partner + `connectionStatus` + `Reconnect` | Rien à quoi se brancher : pas de connexion à surveiller, pas de push serveur, pas de canal par type |

Conséquence : les 9 AC d'origine ne pinnaient que des `grep` sur des fichiers
locaux — ils seraient passés au vert sur une fiction, exactement comme
`POST /assets/:stackId/assets` (stacks) et `PATCH /memories/:id` (mémoires).
**Retirés** (AC-3300…AC-3308), remplacés par le contrat ci-dessous.

## Périmètre réel (ce que fait le client Flutter)

`mobile/lib/widgets/settings/notification_setting.dart` — écran unique :
lit l'état de permission OS, propose **Enable** (`requestNotificationPermission`),
bascule sur **Open Settings** quand c'est accordé (ou refusé définitivement).
Aucun appel serveur. C'est la parité réelle, et c'est le trou du dépôt : la
demande d'autorisation partait en feu-et-oublie au début de chaque run de backup
(`UploadViewModel.runBackup`), sans aucun endroit où voir l'état ni le réparer
après un refus.

**Approche retenue** : écran « Notifications » poussé depuis le hub « Me »
(section Management), alimenté par le **seam unique** `NotificationServicing`.
**Rejetée** : agrandir la pile de widgets (scope B, hors parité, route inutile) ;
garder deux wrappers `UNUserNotificationCenter` (deux conventions pour le même
objet).

## Critères

```
### AC-4100 [type: new]
Assertion: un seul wrapper UNUserNotificationCenter subsiste, exposé sous le seam `NotificationServicing` (permission + demande + notif locale de fin de backup) ; `BackupNotificationService.swift` n'existe plus.
Check: sh -c 'f=Sources/Services/NotificationService.swift; test -f "$f" && test ! -f Sources/Services/BackupNotificationService.swift && grep -qE "protocol NotificationServicing" "$f" && grep -qE "enum NotificationPermission" "$f" && grep -qE "static func from" "$f" && n=$(grep -rl "UNUserNotificationCenter" Sources | wc -l | tr -d " "); test "$n" = "1" && echo PASS || echo FAIL'
Pré-état (worktree HEAD c741730): FAIL
Post-état: PASS
```

```
### AC-4101 [type: new]
Assertion: `NotificationsViewModel` expose `permission`, `isEnabled`, `canAsk`, `isRequesting`, `loaded`, `load()`, `requestPermission()` et ne relance pas une demande déjà en vol.
Check: sh -c 'f=Sources/Features/Notifications/NotificationsViewModel.swift; test -f "$f" && grep -qE "func load\(\) async" "$f" && grep -qE "func requestPermission\(\) async" "$f" && grep -qE "var isEnabled" "$f" && grep -qE "var canAsk" "$f" && grep -qE "var isRequesting" "$f" && grep -qE "guard !isRequesting" "$f" && echo PASS || echo FAIL'
Pré-état: FAIL (fichier absent)
Post-état: PASS
```

```
### AC-4102 [type: new]
Assertion: `NotificationSettingsView` montre le statut, un bouton Enable tant que le système n'a jamais demandé, un bouton Open System Settings sinon, et ouvre bien les réglages iOS.
Check: sh -c 'f=Sources/Features/Notifications/NotificationSettingsView.swift; test -f "$f" && grep -qE "notificationsStatusRow" "$f" && grep -qE "notificationsEnableButton" "$f" && grep -qE "notificationsOpenSettingsButton" "$f" && grep -qE "openSettingsURLString" "$f" && grep -qE "openURL" "$f" && grep -qE "vm.canAsk" "$f" && echo PASS || echo FAIL'
Pré-état: FAIL (fichier absent)
Post-état: PASS
```

```
### AC-4103 [type: new]
Assertion: le hub « Me » pousse l'écran Notifications (ligne adressable `notificationsRow`), et le container en fabrique le VM.
Check: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "NotificationSettingsView\(vm:" "$f" && grep -qE "notificationsRow" "$f" && grep -qE "makeNotificationsViewModel" Sources/DependencyContainer.swift && grep -qE "notifications: notifications" Sources/RootView.swift && echo PASS || echo FAIL'
Pré-état: FAIL
Post-état: PASS
```

```
### AC-4104 [type: new]
Assertion: les 8 chaînes neuves de l'écran ont leur entrée FR dans le catalogue.
Check: sh -c 'for k in "Notifications" "Enable Notifications" "Open System Settings" "On" "Off" "Notifications are off. iOS only asks once, so turn them back on in System Settings." "Immich tells you when a backup finishes." "Immich tells you when a backup finishes, so a background backup isn'\''t silent."; do python3 -c '\''import json,sys; d=json.load(open("Resources/Localizable.xcstrings"))["strings"]; k=sys.argv[1]; sys.exit(0 if k in d and "fr" in d[k].get("localizations",{}) else 1)'\'' "$k" || { echo "MISSING $k"; echo FAIL; exit 1; }; done; echo PASS'
Pré-état: FAIL (`MISSING Notifications`)
Post-état: PASS (catalogue 399 → 407 clés)
```

```
### AC-4105 [type: new]
Assertion: `Tests/NotificationsViewModelTests.swift` couvre la table de mapping des 5 `UNAuthorizationStatus`, les deux réponses système à la demande, la bascule du bouton et la non-réentrance.
Check: sh -c 'f=Tests/NotificationsViewModelTests.swift; n=$(grep -cE "func test_" "$f" 2>/dev/null || echo 0); test -f "$f" && test "$n" -ge 6 && grep -qE "ephemeral" "$f" && grep -qE "WhileInFlight" "$f" && echo PASS || echo FAIL'
Pré-état: FAIL (fichier absent)
Post-état: PASS (6 tests)
```

```
### AC-4106 [type: regression]
Assertion: suite unitaire complète ≥ 831, TEST SUCCEEDED.
Check: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_notifications_test.log && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_notifications_test.log | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 831 && echo PASS || echo FAIL'
Pré-état: PASS — baseline mesurée sur le même worktree HEAD : **831 tests, TEST SUCCEEDED** (`/tmp/immich_notifications_prestate.log`)
Post-état: PASS — **837 tests, TEST SUCCEEDED** (+6), `-only-testing:ImmichSwiftUITests`, iPhone 17
```

```
### AC-4107 [type: new]
Assertion: l'écran est atteint depuis le hub dans l'app réelle et son rendu est conforme (statut + une seule action) — scénario XCUITest `test_10_notifications` contre un stub committé, captures écrites.
Check: sh -c 'grep -qE "Test Case .*test_10_notifications[^ ]* passed" /tmp/immich_notifications_ui.log && test -s /tmp/shot-45-notifications-settings.png && echo PASS || echo FAIL'
Pré-état: FAIL (scénario inexistant)
Post-état: PASS
```

## Livré

- **NEW** `Sources/Services/NotificationService.swift` — `NotificationPermission`
  (`isEnabled`, `static func from(UNAuthorizationStatus)` : `.provisional` et
  `.ephemeral` = activé), protocole `NotificationServicing` (tout `async` +
  `Sendable`, pour qu'un fake `@MainActor` le satisfasse), impl
  `NotificationService`.
- **DELETE** `Sources/Services/BackupNotificationService.swift` — absorbé.
- **EDIT** `Sources/Features/Upload/UploadViewModel.swift` — seam renommé,
  demande toujours en feu-et-oublie (`Task { await … }` : un run n'attend pas la
  réponse de l'utilisateur), `await` sur la notif de fin.
- **NEW** `Sources/Features/Notifications/NotificationsViewModel.swift` —
  `permission`, `loaded`, `isRequesting`, `isEnabled`, `canAsk`, `load()`,
  `requestPermission()` (guard de réentrance).
- **NEW** `Sources/Features/Notifications/NotificationSettingsView.swift` —
  `Form` : statut (`notificationsStatusRow`), **Enable** (`notificationsEnableButton`)
  tant que `canAsk`, sinon **Open System Settings**
  (`notificationsOpenSettingsButton`, `UIApplication.openSettingsURLString`),
  footer par état.
- **EDIT** `Sources/Features/Profile/ProfileView.swift` — ligne
  `notificationsRow` juste après « Backup » ; `Sources/DependencyContainer.swift`
  (`makeNotificationsViewModel()`) ; `Sources/RootView.swift` (`@State` + init +
  passage à `ProfileView`).
- **EDIT** `Resources/Localizable.xcstrings` — 8 clés EN/FR ajoutées à la main
  (l'extraction Xcode ne tourne pas en build CLI, et un build Xcode incrémental
  supprime des clés valides : `git diff` vérifié, +80 lignes, aucune clé
  existante touchée).
- **NEW** `Tests/Mocks/MockNotificationService.swift` (recorder :
  `permissionResult`, `requestResult`, compteurs, `beforeRequestReturns` pour
  parquer une demande en vol) + `Tests/NotificationsViewModelTests.swift` (6).
- **EDIT** `UITests/ImmichRenderScreenshots.swift` — scénario
  `test_10_notifications` + `allowNotificationsAlertIfPresent()`.
  Stub : `UITests/stubs/immich_stub_offline.py` **réutilisé** — la feature n'a
  aucun comportement serveur propre, le stub ne fournit que l'onboarding, le
  handshake OAuth et le shell authentifié.

## Preuves d'exécution réelle

`python3 UITests/stubs/immich_stub_offline.py 8421` puis
`-only-testing:ImmichSwiftUIUITests/ImmichRenderScreenshots/test_10_notifications`,
**vert deux fois** — et les deux branches de l'écran ont été exercées :

1. simulateur chaud (permission déjà accordée) → statut **« Activé »** +
   **« Ouvrir les réglages système »**, footer activé ;
2. après `xcrun simctl uninstall booted fr.millianlmx.immich-ios` (remet la
   permission à `notDetermined`) → statut **« Désactivé »** + **« Activer les
   notifications »**, tap → **l'alerte système iOS** (« Autoriser » via
   SpringBoard) → l'écran bascule sur **« Activé »** + « Ouvrir les réglages
   système ».

Captures : `/tmp/shot-45-notifications-hub.png` (la ligne est bien dans Gestion,
entre Sauvegarde et Doublons), `-settings.png` (état `notDetermined`),
`-allowed.png` (après la réponse système). Suite complète rejouée sur un
**worktree HEAD** pour le pré-état : 831 → **837 tests, TEST SUCCEEDED**.

## Écarts et décisions

- **Pas de toggles par type** (backup/activity/partner) : le seul type que l'app
  produit est l'alerte locale de fin de backup, et le serveur n'en pousse aucun.
  Les ajouter serait de la décoration (et la carte d'origine les pinnait depuis
  une feature fantôme).
- **`canAsk` n'est vrai que pour `.notDetermined`** : après un refus iOS ignore
  les appels suivants, donc un second bouton « Enable » serait mort — l'écran
  envoie vers Réglages système à la place (comportement Flutter identique).
- **La demande de permission au début d'un run de backup est conservée** : c'est
  elle qui fait apparaître l'invite pour un utilisateur qui n'ouvre jamais cet
  écran.
- `notifyBackupComplete` est devenu `async` : l'appel se fait après la fin du run,
  dans un contexte déjà async — aucun changement de timing.
- Reste hors périmètre (et n'existe côté serveur) : APNs, device-token,
  notifications in-app `/api/notifications` (le web seul les consomme). Si un
  jour on veut la surface in-app, c'est une feature neuve, pas une parité.
