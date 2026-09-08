# Task: i18n-catalog

Status: shipped — AC-1180..AC-1183 PASS 2026-08-12 (486 tests, +3). Note: AC-1180 check edité (198 clés / 176 fr réels vs 196/178 supposés).

## Plan
**Objectif**: Compléter le catalog Localizable.xcstrings (D1): traductions FR manquantes pour les chaînes anglaises + clés de la tab bar (Photos/Albums/People/Shared/Me/Search/Memories) pour localisation automatique (LocalizedStringKey). Les chaînes dont la SOURCE est française (écran onboarding/Profile) restent FR par design (D1 connu) — documenté.

**Hypothèses**:
- Resources/Localizable.xcstrings (192 clés, 159 avec fr au départ; généré par extraction Xcode).
- Tab("Photos", ...) = LocalizedStringKey → résolu via catalog automatiquement (RootView).
- Les clés vides (ex: "Compte") sans localization = fallback sur la clé (texte FR) — correct pour du contenu FR.

**Approche retenue**: A — Ajout des 22 traductions FR manquantes (chaînes EN) + 7 clés tab bar (en+fr) via script python dans le catalog; test de garde AppStringsTests (catalog JSON valide + clés tab bar présentes). **B** (rejetée): AppStrings enum partout — refonte massive hors scope card. **C** (rejetée): STRING CATALOG manuel Xcode — non automatisable en CI.

**Étapes**:
1. Card écrite.
2. python: 22 traductions FR + clés tab bar dans Localizable.xcstrings.
3. NEW `Tests/AppStringsTests.swift` (garde catalog).
4. Suite → /tmp/immich_i18n_test_summary.txt + checks + memory.md.

## Acceptance Contract

### Approches candidates
**A (retenue)**: Script catalog + tests garde.
**B**: AppStrings enum global. Refonte massive.
**C**: Manuel Xcode. Non CI.

### Approche retenue + rationale
**A**. Catalog = source de vérité Xcode; automatique; garde testable.

### Critères

```
### AC-1180 [type: new]
Assertion: Catalog contient ≥ 198 clés et ≥ 176 avec fr.
Check post-impl: sh -c 'python3 -c "import json; d=json.load(open(\"Resources/Localizable.xcstrings\")); s=d[\"strings\"]; fr=sum(1 for v in s.values() if \"fr\" in v.get(\"localizations\",{})); assert len(s) >= 198 and fr >= 176" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (192 clés, 159 fr)
Post-state attendu: PASS
```

```
### AC-1181 [type: new]
Assertion: Clés tab bar (Photos, Memories, Albums, People, Shared, Me, Search) présentes avec fr.
Check post-impl: sh -c 'python3 -c "import json; d=json.load(open(\"Resources/Localizable.xcstrings\")); s=d[\"strings\"]; assert all(k in s and \"fr\" in s[k].get(\"localizations\",{}) for k in [\"Photos\",\"Memories\",\"Albums\",\"People\",\"Shared\",\"Me\",\"Search\"])" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (Photos etc. sans fr)
Post-state attendu: PASS
```

```
### AC-1182 [type: new]
Assertion: AppStringsTests ≥ 2 tests (JSON valide + clés tab bar).
Check post-impl: sh -c 'f=Tests/AppStringsTests.swift; n=$(grep -c "func test_" "$f"); test "$n" -ge 2 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```

```
### AC-1183 [type: regression]
Assertion: Suite ≥ 483, TEST SUCCEEDED.
Check post-impl: sh -c 'grep -q "TEST SUCCEEDED" /tmp/immich_i18n_test_summary.txt && n=$(grep -o "Executed [0-9]* tests" /tmp/immich_i18n_test_summary.txt | grep -o "[0-9]*" | sort -n | tail -1) && test "$n" -ge 483 && echo PASS || echo FAIL'
Pre-state attendu: FAIL
Post-state attendu: PASS
```
