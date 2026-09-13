# Task: push-notifications

> ⚠️ **OBSOLÈTE (2026-09-13)** — cette spec décrit une pile APNs qui n'existe pas :
> `POST /api/users/me/device-token` est absent de toutes les versions publiées de
> l'OpenAPI, et le client Flutter n'a aucun push (`flutter_local_notifications` +
> socket.io seulement). Seul l'écran d'autorisation OS a été livré, sous le nom
> « Notifications » (issue #16, AC-4100…AC-4107). **La carte
> `.opencode/scratch/push-notifications.acceptance.md` fait foi**, pas ce fichier.

**Objectif** : Implémenter les notifications push pour ImmichSwiftUI (parité Flutter). Le Flutter gère les notifs pour uploads terminés, shared album activity, et nouvelles photos de partenaires. ImmichSwiftUI n'a aucune gestion de `UNUserNotificationCenter`.

**Hypothèses** :
- iOS 26 target — `UNUserNotificationCenter` disponible nativement.
- `AuthViewModel` gère le login/logout — on peut s'y brancher pour register/unregister token.
- `RealtimeService` (Core/Protocols/) peut être étendu pour notifier les changements d'album.
- `BackupNotificationService` existe déjà pour les notifications locales de backup.
- `UploadViewModel` + `BackupEngine` gèrent les uploads — on peut notifier à la fin.
- Shared album activities (comments, likes) viennent via `ActivityResponseDto` (API polling dans AlbumDetailView).
- Partnership new photos : le serveur push les notifications, on les réceptionne.

**Approche retenue** : A — wrapper `PushNotificationService` dans Services/ + `PushNotificationViewModel` + registration dans Auth flow + handling dans RootView + sheet pour settings.
- **B (rejetée)** : tout dans AuthViewModel. Le auth module n'est pas le bon endroit pour la logique push.
- **C (rejetée)** : uniquement notifications de backup. C'est insuffisant — le Flutter notifie aussi pour activities et partners.

## Étapes

1. **PushNotificationService** — NEW `Sources/Services/PushNotificationService.swift` :
   - `requestAuthorization()` → UNUserNotificationCenter.requestAuthorization.
   - `registerDevice()` → delegate async → APNs token → POST /api/notifications/register (si endpoint existe, sinon fallback local only).
   - `unregisterDevice()` → POST /api/notifications/unregister.
   - `handlePush(payload: [String: Any])` — dispatch vers les handlers (backup done, activity, partner).
   - `onBackupComplete` callback.
   - `onNewActivity` callback.
   - `onNewPartnerPhoto` callback.
   - `PushNotificationSettings` : notificationsEnabled, backupNotifications, activityNotifications, partnerNotifications.
2. **PushNotificationStore** — NEW `Sources/Services/PushNotificationStore.swift` :
   - Persist settings dans UserDefaults ("pushNotificationSettings").
   - `var notificationsEnabled: Bool`, `var backupEnabled: Bool`, `var activityEnabled: Bool`, `var partnerEnabled: Bool`.
3. **PushNotificationViewModel** — NEW `Sources/Features/Settings/PushNotificationViewModel.swift` :
   - Load/save settings.
   - `func registerDevice()` / `unregisterDevice()`.
   - `var isRegistered: Bool` (APNs token reçu).
4. **PushNotificationSettingsView** — NEW `Sources/Features/Settings/PushNotificationSettingsView.swift` :
   - Toggle "Push notifications" principal.
   - Sous-toggles : "Backup complete", "Shared album activity", "Partner new photos".
5. **Auth integration** — `AuthViewModel.registerDevice()` au login, `unregisterDevice()` au logout.
6. **Backup integration** — `UploadViewModel` appelle `PushNotificationService.onBackupComplete()` à la fin d'un upload.
7. **Activity integration** — `ActivityFeedViewModel` appelle `PushNotificationService.onNewActivity()` sur création de commentaire.
8. **Tests** — `PushNotificationServiceTests` (auth, register, unregister, dispatch), `PushNotificationViewModelTests`.
9. **xcodegen + suite**.

## Acceptance Contract

### Approches candidates
**A (retenue)** : Service dédié + store persisté + VM dédié + settings view + intégration auth/backup/activity.
**B** : Tout dans AuthViewModel. Couplage mal placé.
**C** : Notifications locales uniquement (pas APNs). Manque push push across devices.

### Approche retenue + rationale
**A**. Service isolé, testable, réutilisable par le widget et le background scheduler. Parity Flutter.

### Critères

```
### AC-PN01 [type: new]
Assertion: PushNotificationService existe (NEW file) avec requestAuthorization, registerDevice, unregisterDevice, push handlers.
Check post-impl: sh -c 'f=Sources/Services/PushNotificationService.swift; test -f "$f" && grep -q "func requestAuthorization" "$f" && grep -q "func registerDevice" "$f" && grep -q "func unregisterDevice" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN02 [type: new]
Assertion: PushNotificationStore persist les settings (notificationsEnabled, backupEnabled, activityEnabled, partnerEnabled).
Check post-impl: sh -c 'f=Sources/Services/PushNotificationStore.swift; test -f "$f" && grep -q "notificationsEnabled" "$f" && grep -q "backupEnabled" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN03 [type: new]
Assertion: PushNotificationViewModel expose loadSettings(), saveSettings(), registerDevice(), isRegistered.
Check post-impl: sh -c 'f=Sources/Features/Settings/PushNotificationViewModel.swift; test -f "$f" && grep -q "func loadSettings" "$f" && grep -q "func registerDevice" "$f" && grep -q "var isRegistered" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN04 [type: new]
Assertion: PushNotificationSettingsView existe dans Settings/ avec toggles principaux et sous-toggles.
Check post-impl: sh -c 'f=Sources/Features/Settings/PushNotificationSettingsView.swift; test -f "$f" && grep -q "backupEnabled" "$f" && grep -q "activityEnabled" "$f" && grep -q "partnerEnabled" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN05 [type: new]
Assertion: AuthViewModel appelle registerDevice() au login + unregisterDevice() au logout.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -q "registerDevice\|unregisterDevice\|PushNotificationService" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN06 [type: new]
Assertion: UploadViewModel appelle onBackupComplete() à la fin d'un upload (BackupEngine.run phase .done).
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -q "onBackupComplete\|PushNotificationService" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-PN07 [type: regression]
Assertion: Suite ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_push_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_push_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
