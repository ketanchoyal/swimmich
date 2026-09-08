# Task: widgets-appintents

Status: shipped — AC-1170..AC-1174 PASS 2026-08-12 (483 tests, +3).

## Plan
**Objectif**: Home-screen widget + App Intents (Siri/Shortcuts) — parity Flutter élargie. Infrastructure existe: extension ImmichWidgets (Live Activity P2) + framework ImmichSharedKit.

**Hypothèses**:
- project.yml: ImmichWidgets (app-extension, ImmichWidgets/), ImmichSharedKit (framework), widgetkit-extension plist OK (P2).
- AppIntents = framework Apple; AppShortcutsProvider s'enregistre dans le target APP.
- Le widget statique ne peut pas atteindre les VMs de l'app (process séparé) → widget simple (icône + nom + widgetURL → ouvre l'app); intents interactifs = dans l'app via AppShortcutsProvider.
- BackupNowAppIntent: perform() → DependencyContainer.shared.makeUploadViewModel().runBackup() → .result().

**Approche retenue**: A — `AppIntent` dans l'app: BackupNowAppIntent (title "Back up now", perform lance le backup via container) + AppShortcutsProvider (1 raccourci) ; widget: ImmichHomeWidget StaticConfiguration (icône AppIcon + "Immich" + widgetURL deep link app.immich://backup) enregistré dans ImmichWidgetsBundle (aux côtés de BackupLiveActivity). **B** (rejetée): widget data-rich (app group container + token partagé) — sécurité + scope. **C** (rejetée): intent dans le widget (cross-process impossible sans partage).

**Étapes**:
1. Card écrite.
2. NEW `Sources/AppIntents.swift` (main target): BackupNowAppIntent + AppShortcutsProvider.
3. ImmichWidgets: NEW `ImmichHomeWidget.swift` + widgetURL handling (ImmichSwiftUIApp onOpenURL → backup).
4. ImmichSwiftUIApp: .onOpenURL deep link backup.
5. Tests: AppIntentsTests (title, provider count, description).
6. xcodegen + suite → /tmp/immich_widgets_test_summary.txt + checks + memory.md.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Intent app-side + widget statique.
**B**: Widget data-rich. Sécurité/scope.
**C**: Intent widget. Cross-process impossible.

### Approche retenue + rationale
**A**. Siri/Shortcuts fonctionnels, widget simple sûr, infra extension réutilisée.

### Critères

```
### AC-1170 [type: new]
Assertion: BackupNowAppIntent (AppIntent, title "Back up now") + AppShortcutsProvider.
Check post-impl: sh -c 'f=Sources/AppIntents.swift; test -f "$f" && grep -q "struct BackupNowAppIntent: AppIntent" "$f" && grep -q "Back up now" "$f" && grep -q "AppShortcutsProvider" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1171 [type: new]
Assertion: perform() lance le backup via DependencyContainer + retourne .result().
Check post-impl: sh -c 'f=Sources/AppIntents.swift; grep -q "func perform" "$f" && grep -q "makeUploadViewModel" "$f" && grep -q "runBackup" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1172 [type: new]
Assertion: ImmichHomeWidget StaticConfiguration dans ImmichWidgets + enregistré dans ImmichWidgetsBundle + widgetURL.
Check post-impl: sh -c 'f=ImmichWidgets/ImmichHomeWidget.swift; test -f "$f" && grep -q "StaticConfiguration" "$f" && grep -q "widgetURL" "$f" && grep -q "ImmichHomeWidget" ImmichWidgets/BackupLiveActivity.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1173 [type: new]
Assertion: onOpenURL deep link app.immich://backup dans ImmichSwiftUIApp + tests ≥ 2.
Check post-impl: sh -c 'grep -q "onOpenURL" Sources/ImmichSwiftUIApp.swift && f=Tests/AppIntentsTests.swift; n=$(grep -c "func test_" "$f"); test "$n" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1174 [type: regression]
Assertion: Suite ≥ 480, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_widgets_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_widgets_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 480 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
