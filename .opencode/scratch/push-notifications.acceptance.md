# Task: push-notifications

Status: plan

## Plan

**Objectif**: Implémenter les notifications push pour ImmichSwiftUI (parité Flutter). Notifications pour uploads terminés, shared album activity, et nouvelles photos de partenaires.

**Hypothèses** (ground truth vérifié):
- iOS 26 target → `UNUserNotificationCenter` disponible.
- `AuthViewModel` gère login/logout — register/unregister token possible.
- `BackupNotificationService` (Services/) gère notifications locales déjà.
- `UploadViewModel` + `BackupEngine` gèrent les uploads.
- Activity feed (comments, likes) via `ActivityResponseDto`.
- RealtimeService (Socket.IO) pour mises à jour live.

**Approche retenue**: A — `PushNotificationService` + `PushNotificationStore` + `PushNotificationViewModel` + `PushNotificationSettingsView` + integration Auth/Backup.
**B (rejetée)**: Tout dans AuthViewModel → couplage mal placé.
**C (rejetée)**: Notifications locales uniquement → pas de push.

**Étapes**:
1. NEW `PushNotificationService.swift` (Services/) — requestAuthorization(), registerDevice(), unregisterDevice(), handlePush(payload:), callbacks onBackupComplete/onNewActivity/onNewPartnerPhoto.
2. NEW `PushNotificationStore.swift` (Services/) — Persist settings: notificationsEnabled, backupEnabled, activityEnabled, partnerEnabled dans UserDefaults("pushNotificationSettings").
3. NEW `PushNotificationViewModel.swift` (Features/Settings/) — loadSettings(), saveSettings(), registerDevice(), unregisterDevice(), isRegistered.
4. NEW `PushNotificationSettingsView.swift` (Features/Settings/) — Master toggle + sub-toggles (backup, activity, partner).
5. EDIT `AuthViewModel.swift` — registerDevice() au login + unregisterDevice() au logout.
6. EDIT `UploadViewModel.swift` — Appeler onBackupComplete() à la fin d'un upload réussi.
7. EDIT `ActivityFeedViewModel.swift` — Appeler onNewActivity() sur création de commentaire.
8. EDIT `ProfileView.swift` — Ajouter "Notifications" navigation link.
9. Tests — `PushNotificationServiceTests` +5 (auth, register, unregister, dispatch), `PushNotificationViewModelTests` +4.
10. Build + suite complète.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Service dédié + store persisté + VM dédié + settings view + intégration auth/backup/activity.
**B**: Tout dans AuthViewModel → couplage.
**C**: Notifications locales uniquement → insuffisant.

### Approche retenue + rationale
**A**. Service isolé, testable, réutilisable par widget et background scheduler.

### Critères

```
### AC-3300 [type: new]
Assertion: PushNotificationService expose requestAuthorization(), registerDevice(), unregisterDevice(), handlePush(payload:), onBackupComplete, onNewActivity, onNewPartnerPhoto dans Sources/Services/PushNotificationService.swift.
Check post-impl: sh -c 'f=Sources/Services/PushNotificationService.swift; test -f "$f" && grep -qE "func requestAuthorization" "$f" && grep -qE "func registerDevice" "$f" && grep -qE "func unregisterDevice" "$f" && grep -qE "func handlePush" "$f" && grep -qE "onBackupComplete" "$f" && grep -qE "onNewActivity" "$f" && grep -qE "onNewPartnerPhoto" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3301 [type: new]
Assertion: PushNotificationStore persiste notificationsEnabled, backupEnabled, activityEnabled, partnerEnabled dans UserDefaults suite "pushNotificationSettings".
Check post-impl: sh -c 'f=Sources/Services/PushNotificationStore.swift; test -f "$f" && grep -qE "notificationsEnabled" "$f" && grep -qE "backupEnabled" "$f" && grep -qE "activityEnabled" "$f" && grep -qE "partnerEnabled" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3302 [type: new]
Assertion: PushNotificationViewModel expose loadSettings(), saveSettings(), registerDevice(), unregisterDevice(), isRegistered, connectionStatus dans Features/Settings/PushNotificationViewModel.swift.
Check post-impl: sh -c 'f=Sources/Features/Settings/PushNotificationViewModel.swift; test -f "$f" && grep -qE "func loadSettings" "$f" && grep -qE "func saveSettings" "$f" && grep -qE "func registerDevice" "$f" && grep -qE "var isRegistered" "$f" && grep -qE "connectionStatus" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3303 [type: new]
Assertion: PushNotificationSettingsView expose master toggle, sub-toggles (backup, activity, partner), status indicator, reconnect button, open system settings dans Features/Settings/PushNotificationSettingsView.swift.
Check post-impl: sh -c 'f=Sources/Features/Settings/PushNotificationSettingsView.swift; test -f "$f" && grep -qE "backupEnabled" "$f" && grep -qE "activityEnabled" "$f" && grep -qE "partnerEnabled" "$f" && grep -qE "Reconnect" "$f" && grep -qE "openURL" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent)
Post-state attendu: PASS
```

```
### AC-3304 [type: new]
Assertion: AuthViewModel appelle registerDevice() au login + unregisterDevice() au logout.
Check post-impl: sh -c 'f=Sources/Features/Auth/AuthViewModel.swift; grep -qE "registerDevice" "$f" && grep -qE "unregisterDevice" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3305 [type: new]
Assertion: UploadViewModel appelle onBackupComplete() à la fin d'un upload réussi (phase .done).
Check post-impl: sh -c 'f=Sources/Features/Upload/UploadViewModel.swift; grep -qE "onBackupComplete" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3306 [type: new]
Assertion: ProfileView expose "Notifications" navigation link vers PushNotificationSettingsView.
Check post-impl: sh -c 'f=Sources/Features/Profile/ProfileView.swift; grep -qE "Notifications" "$f" && grep -qE "PushNotificationSettingsView" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3307 [type: new]
Assertion: PushNotificationServiceTests expose ≥5 tests; PushNotificationViewModelTests expose ≥4 tests.
Check post-impl: sh -c 'f=Tests/PushNotificationServiceTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f"); test "$n" -ge 5 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-3308 [type: regression]
Assertion: Suite complète ≥ baseline, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -qE "TEST SUCCEEDED" /tmp/immich_push_test_summary.txt && n=$(grep -oE "Executed [0-9]+ tests" /tmp/immich_push_test_summary.txt | grep -oE "[0-9]+" | sort -n | tail -1); test "$n" -ge 200 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
