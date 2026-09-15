# Task: person-birthday

Status: planifié — **aucune AC ouverte** (écart G15 du registre `.omp/backlog/ImmichSwiftUI-backlog.md` §2.17,
ligne 790 : la modale `person_edit_birthday_modal.widget.dart` et l'en-tête `person_sliver_app_bar.dart` côté
Flutter n'ont aucun équivalent iOS alors que `PersonResponseDto.birthDate` est déjà décodé).

## Plan (résumé)

**Objectif** : l'utilisateur ouvre la fiche d'une personne reconnue et lit son anniversaire sous son nom ; un
5ᵉ bouton d'action « Birthday » ouvre une feuille dédiée avec un `DatePicker` natif dont l'enregistrement
remplace immédiatement la valeur de la liste en mémoire ; il peut aussi effacer un anniversaire existant. Un
seul champ du DTO part sur le fil à chaque appel, la date voyage en date-seule `YYYY-MM-DD`.

**Approche retenue** : A — la date-seule est une chaîne convertie par un helper dédié `PersonBirthday`
(`Calendar.current` + `DateComponents`, donc sans dérive de fuseau) ; **poser** une date passe par
`PersonUpdateDto(birthDate:)` tel quel, **effacer** passe par un corps minimal `PersonBirthdayClearDto` qui
écrit un `null` explicite ; la surface est une feuille portée par un 5ᵉ `actionButton` du header, l'affichage
une ligne `Label` sous le décompte de photos.

**Le piège central de la fiche** : le `encode(to:)` **synthétisé** de `PersonUpdateDto` encode ses optionnels
avec `encodeIfPresent`, donc `PersonUpdateDto(birthDate: nil)` produit un corps **sans clé `birthDate`** — le
serveur n'a rien à mettre à jour et l'anniversaire reste en place, en silence. Le schéma OpenAPI déclare
`birthDate` `type: string / format: date / nullable: true` : l'effacement exige un `null` **explicite** (un
`""` est rejeté par `format: date`). C'est la raison d'être du DTO dédié, et de l'AC-5151/AC-5158 qui le
verrouillent.

**Étapes** : (1) NEW `Sources/Core/Utilities/PersonBirthday.swift` (`date(from:)`, `wire(from:)`,
`display(_:)`) ; (2) EDIT `Sources/Core/Types/DTOs+People.swift` (`PersonBirthdayClearDto` + `encodeNil`) ;
(3) EDIT `Sources/Core/Protocols/ImmichClient.swift` (`clearPersonBirthday(id:)`) ; (4) EDIT
`Sources/Services/ImmichAPIClient.swift` (même `PUT /api/people/{id}`, seul le corps change) ; (5) EDIT
`Tests/Mocks/MockImmichClient.swift` (conformité + capture `lastClearedPersonBirthdayId`) ; (6) EDIT
`Sources/Features/People/PeopleViewModel.swift` (extraction de `apply(_:_:)`, puis `setBirthday(_:to:)`) ;
(7) NEW `Sources/Features/People/BirthdayEditorSheet.swift` ; (8) EDIT `Sources/Features/People/PeopleView.swift`
(5ᵉ `actionButton` + `.sheet(item:)`, ligne du header) ; (9) EDIT `Tests/PeopleViewModelTests.swift` (3 cas) ;
(10) NEW `Tests/PersonBirthdayTests.swift` (4 cas) ; (11) EDIT `Tests/DTOEncodingTests.swift` (le piège et sa
parade) ; (12) `xcodegen generate` + suite complète.

**Incertitudes** : sémantique serveur de `{"birthDate": null}` (à vérifier par `curl` contre un serveur réel —
voir `.omp/person-birthday/person-birthday.specs.md` § Incertitudes) ; détents de présentation et style du
`DatePicker` (arbitrage visuel) ; locale effective de `PersonBirthday.display` hors environnement SwiftUI.

## Critères

```
### AC-5150 [type: new]
Assertion: le format date-seule vit dans un helper dédié `Sources/Core/Utilities/PersonBirthday.swift`, hors de la vue : parse, format filaire et libellé localisé — c'est la seule logique de la fiche qui puisse dériver d'un jour.
Check post-impl: sh -c 'f=Sources/Core/Utilities/PersonBirthday.swift; test -f "$f" && grep -qE "enum PersonBirthday" "$f" && grep -qE "static func date\(from wire: String\?\) -> Date\?" "$f" && grep -qE "static func wire\(from date: Date\) -> String" "$f" && grep -qE "static func display" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `grep -rn "PersonBirthday" Sources/` ne renvoie rien, le dépôt n'a aucun parseur de date seule : `Sources/Services/JSONCoding.swift:52` et `Sources/Core/Utilities/LongDateFormatter.swift:15-33` ne connaissent que des ISO-8601 horodatés)
Post-state attendu: PASS
```

```
### AC-5151 [type: new — le piège d'encodage]
Assertion: l'effacement a son propre corps `PersonBirthdayClearDto`, mono-champ, qui écrit un `null` EXPLICITE avec `encodeNil` : le `encode(to:)` synthétisé de `PersonUpdateDto` omet ses optionnels `nil` (`encodeIfPresent`), donc `PersonUpdateDto(birthDate: nil)` ne peut pas exprimer « mets ce champ à null ».
Check post-impl: sh -c 'f=Sources/Core/Types/DTOs+People.swift; grep -qE "struct PersonBirthdayClearDto: Encodable" "$f" && grep -qE "func encode\(to encoder: Encoder\) throws" "$f" && grep -qE "encodeNil\(forKey: .birthDate\)" "$f" && grep -qE "enum CodingKeys: String, CodingKey \{ case birthDate \}" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun `encodeNil` dans `Sources/` aujourd'hui — c'est le premier précédent du dépôt, d où le doc-comment obligatoire qui explique POURQUOI le type existe ; `PersonUpdateDto` seul est le piège)
Post-state attendu: PASS
```

```
### AC-5152 [type: new]
Assertion: la route d'effacement est déclarée au protocole et implémentée sur le MÊME chemin HTTP que la pose (`PUT /api/people/{id}` via `sendAuthed`), seul le corps change.
Check post-impl: sh -c 'grep -qE "func clearPersonBirthday\(id: String\) async throws -> PersonResponseDto" Sources/Core/Protocols/ImmichClient.swift && grep -qE "func clearPersonBirthday" Sources/Services/ImmichAPIClient.swift && grep -qE "AnyEncodable\(PersonBirthdayClearDto\(\)\)" Sources/Services/ImmichAPIClient.swift && grep -qE "path: ImmichAPI.people.path" Sources/Services/ImmichAPIClient.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucune des deux occurrences : seul `updatePerson(id:dto:)` existe, `ImmichClient.swift:164` et `ImmichAPIClient.swift:392`)
Post-state attendu: PASS
```

```
### AC-5153 [type: new — la conformité du double]
Assertion: le mock conforme au protocole (seuls deux types conforment à `ImmichClient`) capture l'id effacé et implémente `clearPersonBirthday(id:)` : sans la méthode, le mock cesse de conformer et TOUTE la suite cesse de compiler.
Check post-impl: sh -c 'f=Tests/Mocks/MockImmichClient.swift; grep -qE "var lastClearedPersonBirthdayId: String\?" "$f" && grep -qE "func clearPersonBirthday\(id: String\) async throws" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`Tests/Mocks/MockImmichClient.swift:169` porte `lastUpdatePersonDto` et `:707` le mock d `updatePerson`, mais aucune capture ni méthode d effacement)
Post-state attendu: PASS
```

```
### AC-5154 [type: new — deux voies d'écriture, une sémantique]
Assertion: `PeopleViewModel` porte l'action en deux branches au-dessus d'un chemin de résultat PARTAGÉ (`apply`), et chaque branche n'envoie qu'un seul champ : `PersonUpdateDto(birthDate:)` pour poser, `clearPersonBirthday` pour effacer — la réécriture de `people[i]` et la pose d'`errorMessage` ne sont pas dupliquées.
Check post-impl: sh -c 'f=Sources/Features/People/PeopleViewModel.swift; grep -qE "func setBirthday\(_ person: PersonResponseDto, to wire: String\?\) async" "$f" && grep -qE "private func apply\(_ id: String" "$f" && grep -qE "PersonUpdateDto\(birthDate: wire" "$f" && grep -qE "client.clearPersonBirthday\(id: person.id\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (aucun `setBirthday` : `PeopleViewModel.swift:96-112` n a que rename/toggleFavorite/toggleHidden/setFeatureFace, toutes au-dessus du `update(_:_:)` privé `:114`)
Post-state attendu: PASS
```

```
### AC-5155 [type: new]
Assertion: la feuille d'édition est un fichier dédié (pas `PeopleView.swift`, déjà ~300 lignes) avec sa PROPRE pile, un `DatePicker` natif en date seule et les trois contrôles adressables par identifiant plutôt que par libellé traduit ; « Clear Birthday » n'apparaît que s'il y a quelque chose à effacer.
Check post-impl: sh -c 'f=Sources/Features/People/BirthdayEditorSheet.swift; test -f "$f" && grep -qE "struct BirthdayEditorSheet: View" "$f" && grep -qE "NavigationStack" "$f" && grep -qE "DatePicker" "$f" && grep -qE "graphical" "$f" && grep -qE "displayedComponents: .date" "$f" && grep -qE "hasExistingBirthday" "$f" && grep -qE "birthdayPicker" "$f" && grep -qE "birthdaySave" "$f" && grep -qE "birthdayClear" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent — `Sources/Features/People/` ne contient aujourd hui que PeopleView/PeopleViewModel, le renommage passe par un `TextField` en ligne `PeopleView.swift:243-258`)
Post-state attendu: PASS
```

```
### AC-5156 [type: new]
Assertion: la fiche gagne un 5ᵉ bouton d'action (après « Hide », avant `mergeMenu`) et une seconde feuille `.sheet(item:)` pilotée par la personne, sans identifiant ad hoc — `PersonResponseDto` est déjà `Identifiable`.
Check post-impl: sh -c 'f=Sources/Features/People/PeopleView.swift; grep -qE "birthdayPerson" "$f" && grep -qE "BirthdayEditorSheet\(" "$f" && grep -qE "actionButton\(\"calendar\"" "$f" && grep -qE "PersonBirthday.date\(from: person.birthDate\)" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (le `HStack` de `PeopleView.swift:182-195` porte exactement quatre boutons et un seul `.sheet(item:)`, celui du renommage `:243-258`)
Post-state attendu: PASS
```

```
### AC-5157 [type: new]
Assertion: l'anniversaire se lit dans l'en-tête de la fiche (sous le décompte de photos), disparaît de lui-même quand la valeur est absente — aucune chaîne « inconnu » — et porte son identifiant ; la ligne de liste `personRow` n'est pas touchée.
Check post-impl: sh -c 'f=Sources/Features/People/PeopleView.swift; grep -qE "PersonBirthday.display\(person.birthDate\)" "$f" && grep -qE "personBirthdayValue" "$f" && grep -qE "systemImage: \"calendar\"" "$f" && echo PASS || echo FAIL'
Pre-state attendu: FAIL (`grep -rn "birthDate" Sources/` ne renvoie aujourd hui que `Sources/Core/Types/DTOs+People.swift` : la valeur est décodée mais aucun écran ne la lit)
Post-state attendu: PASS
```

```
### AC-5158 [type: new]
Assertion: les tests verrouillent les trois contrats non visibles — « un seul champ part » (le DTO de pose a cinq champs à `nil`), « l'effacement ne passe pas par `PersonUpdateDto` » (l'ancien DTO ne doit PAS partir), et le piège d'encodage lui-même : `PersonUpdateDto(birthDate: nil)` omet la clé, `PersonBirthdayClearDto()` émet `"birthDate":null`.
Check post-impl: sh -c 'f=Tests/PersonBirthdayTests.swift; test -f "$f" && n=$(grep -cE "func test_" "$f") && test "$n" -ge 4 && grep -qE "test_wireRoundTrip_isIdentity" "$f" && grep -qE "test_parse_rejectsMalformed" "$f" && grep -qE "test_people_setBirthday_sendsBirthDateOnly" Tests/PeopleViewModelTests.swift && grep -qE "test_people_setBirthday_clearsViaDedicatedRoute" Tests/PeopleViewModelTests.swift && grep -qE "test_people_setBirthday_failure_setsError" Tests/PeopleViewModelTests.swift && grep -qE "PersonBirthdayClearDto" Tests/DTOEncodingTests.swift && echo PASS || echo FAIL'
Pre-state attendu: FAIL (fichier absent ; `Tests/PeopleViewModelTests.swift:79,92` s arrête à rename/toggleFavorite et `Tests/DTOEncodingTests.swift:345` ne couvre que `PersonUpdateDto` tous champs explicites)
Post-state attendu: PASS
Note: un nouveau `Tests/*.swift` n'est compilé qu'après `xcodegen generate` (deux sources et un test ajoutés) — sans régénération la suite passe « verte » par omission, et le fichier de test n'est même pas découvert.
```

```
### AC-5159 [type: regression]
Assertion: suite complète ≥ baseline mesurée avant implémentation (dernier relevé connu : 886 tests, `-only-testing:ImmichSwiftUITests`) et TEST SUCCEEDED.
Check post-impl: sh -c 'f=/tmp/immich_personbirthday_test.log; test -f "$f" && grep -qE "TEST SUCCEEDED" "$f" && n=$(grep -oE "Executed [0-9]+ tests" "$f" | grep -oE "[0-9]+" | sort -n | tail -1) && test "$n" -ge 886 && echo PASS || echo FAIL'
Pre-state attendu: FAIL (log absent)
Post-state attendu: PASS
```
