# Bug Prospector Report: files changed by the health check

**Date:** 2026-11-10
**Scope:** the 38 Swift files changed on `claude/project-thread-lalraj` against `main`, without the texthooker files (`App/Sources/Texthooker/*`, `HookText.swift`, `tools/texthooker`, `tools/textractor-extension`), which belong to another thread
**Lenses Applied:** Quick 3: Assumption Audit, Error Path Exerciser, Boundary Conditions
**Files Analyzed:** 38
**Source glob:** `**/*.swift`
**Accelerators:** full
**Platform:** iOS only. Not distributed through a store (sideloaded), so there is no 1-Star Risk column.
**Checked on:** Linux only. Nothing here was verified on a phone. Where a finding says "reproduced", it was reproduced on Linux with Swift 6.2.4, whose Foundation is the same code iOS 17 and later run for links.

The options marked Recommended were taken where the skill asks (iOS only; fix all bugs now), because the person was away.

## Summary

| Status | Count |
|--------|-------|
| Bugs Found | 8 (all fixed) |
| Fragile Code | 5 (3 fixed, 2 left open) |
| OK (Already Guarded) | 14 listed |
| Needs Review | 1 |

## Issue Rating Table

Sorted by Urgency, then ROI.

| # | Finding | Lens | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Confidence | Status |
|---|---------|------|---------|-----------|-------------|-----|-------------|------------|------------|--------|
| 1 | Anki.swift:281 — an Anki field name with a space or in Japanese closes the app on ＋ | Assumption | 🔴 Critical | ⚪ Low | 🔴 Critical | 🟠 Excellent | ⚪ 1 file | Trivial | verified | Fixed |
| 2 | AppModel.swift:156 — Yomitan settings picked during an import: the app freezes, then blames the backup | Assumption | 🟡 High | ⚪ Low | 🟡 High | 🟠 Excellent | ⚪ 1 file | Trivial | probable | Fixed |
| 3 | HeadwordGroup.swift:68 — a sort dictionary that is not installed or is switched off leaves results unsorted | Assumption | 🟡 High | ⚪ Low | 🟡 High | 🟠 Excellent | 🟢 2 files | Trivial | verified | Fixed |
| 4 | AppModel.swift:350 — a frequency dictionary imports as "0 voci importate" | Boundary | 🟢 Medium | ⚪ Low | 🟢 Medium | 🟠 Excellent | ⚪ 1 file | Trivial | verified | Fixed |
| 5 | YomitanImporter.swift:35 — a .zip cut short or a malformed bank says only "the operation couldn't be completed" | Error Path | 🟢 Medium | ⚪ Low | 🟢 Medium | 🟢 Good | 🟢 2 files | Small | verified | Fixed |
| 6 | Diagnostics.swift:51 — the app writes over the share panel's diary lines | Assumption | 🟢 Medium | ⚪ Low | 🟢 Medium | 🟢 Good | 🟢 2 files | Small | verified | Fixed |
| 7 | SettingsView.swift:41 — "open screenshots" switches itself back off without a word when Photos access is refused | Error Path | ⚪ Low | ⚪ Low | ⚪ Low | 🟢 Good | ⚪ 1 file | Trivial | needs-runtime | Fixed |
| 8 | AppModel.swift:262 — picking dictionary files when the database did not open does nothing | Error Path | ⚪ Low | ⚪ Low | ⚪ Low | 🟢 Good | ⚪ 1 file | Trivial | verified | Fixed |
| F1 | AppModel.swift:400 — deleting or switching a dictionary while the database is busy is ignored silently | Error Path | ⚪ Low | ⚪ Low | ⚪ Low | 🟢 Good | ⚪ 1 file | Trivial | verified | Fixed |
| F2 | WordsView.swift:14 — the filter of the Parole tab does not understand romaji | Assumption | ⚪ Low | ⚪ Low | ⚪ Low | 🟢 Good | ⚪ 1 file | Trivial | probable | Fixed |
| F3 | DictionariesView.swift:276 — the "order with its frequencies" switch does not appear after switching the dictionary on | Boundary | ⚪ Low | ⚪ Low | ⚪ Low | 🟡 Marginal | ⚪ 1 file | Trivial | needs-runtime | Fixed |
| F4 | DictionaryStore.swift:397 — index building at launch can meet an import and hold up searches for five seconds | Assumption | ⚪ Low | 🟡 High | ⚪ Low | 🔴 Poor | ⚪ 1 file | Medium | probable | Deferred |
| F5 | AppModel.swift:142 — anything that opens `kotoba://mined?k=…` ticks a word as sent to Anki | Assumption | ⚪ Low | ⚪ Low | ⚪ Low | 🟡 Marginal | 🟢 2 files | Small | verified | Deferred |

## Implementation Plan

All phases below are done; the plan is kept as the record of the order.

### Phase 1: The crash — 1 fix
**Files:** `Packages/KotobaCore/Sources/KotobaCore/Anki.swift`
**Findings:** 1
**Rationale:** the only finding that closes the app; committed and pushed on its own first.
**Verify:** `swift test --filter AnkiAndMetaTests` (new test `testAnkiMobileURLWithAnyFieldName`).

### Phase 2: Imports and settings in the model — 6 fixes
**Files:** `App/Sources/AppModel.swift`, `App/Sources/HeadwordGroup.swift`, `Packages/KotobaCore/Sources/KotobaCore/YomitanImporter.swift`
**Findings:** 2, 3, 4, 5, 8, F1
**Rationale:** the importer gains an error case (finding 5) that the model's messages depend on, so the engine change comes first.
**Verify:** both `swift test` suites.

### Phase 3: Diary and screens — 4 fixes
**Files:** `App/Sources/Diagnostics.swift`, `DiagnosticsView.swift`, `SettingsView.swift`, `WordsView.swift`, `DictionariesView.swift`
**Findings:** 6, 7, F2, F3
**Verify:** app-logic tests, `tools/screen-check/run.sh`.

## Detailed Findings

### 1. Anki.swift:281 — an Anki field name with a space or in Japanese closes the app on ＋
**Lens:** Assumption Audit
**Assumption:** field names are plain ASCII words such as `Word` or `Glossary`.
**Violation scenario:** the note type has a field called "Word Reading" (the Kaishi 1.5k deck, the usual beginner's deck, names its fields this way), or 単語, or anything with `#`. Or you tap "Aggiungi un campo" in the new field editor, which proposes the name "Campo 6", give it something to hold, and send a word.
**Consequence:** the app closes on the spot. The link to AnkiMobile was assembled with the names as typed, and Foundation ends the program when a query still holds a space or a non-ASCII letter (`Fatal error: Attempting to set percentEncodedQuery with invalid characters`). Reproduced on Linux for "Word Reading", 単語 and "A&B=C#D"; "Word" passes.

**Code before:**
```swift
components.percentEncodedQuery = items.map { item in
    "\(item.name)=\((item.value ?? "").addingPercentEncoding(withAllowedCharacters: strict) ?? "")"
}.joined(separator: "&")
```

**Fix applied:**
```swift
components.percentEncodedQuery = items.map { item in
    "\(encoded(item.name))=\(encoded(item.value ?? ""))"
}.joined(separator: "&")
```

**User experience:**
- **Before:** you tap ＋ on a word and Kotoba vanishes. It does so every time, for every word, until the field is renamed, and nothing says the field name is the cause.
- **After:** AnkiMobile opens with the note filled in, whatever the fields are called.

This bug is older than the health check, but step J made it one tap away: the field editor's own default name contains a space. I have not seen AnkiMobile receive such a link. The test checks that the link reads back to the same names and values, which is what a standard link reader does.

### 2. AppModel.swift:156 — Yomitan settings picked during an import: the app freezes, then blames the backup
**Lens:** Assumption Audit
**Assumption:** nothing else is writing the database when the settings are applied.
**Violation scenario:** the new first-run screen lists "import your Yomitan settings" as step three, right after choosing the dictionary files. A large dictionary takes minutes to import, in one long write. Doing step three meanwhile writes the dictionary order through the app's main connection, which waits for the import (`busy_timeout = 5000`) on the main thread and then fails.
**Consequence:** the screen stops answering for five seconds, then an alert says "Non riesco a leggere questo backup di Yomitan: … database is locked". Nothing is applied, and the backup was fine.

**Fix applied:**
```swift
guard !isBusy else {
    errorMessage = tr("Le impostazioni di Yomitan si applicano ai dizionari già importati. Aspetta che Kotoba finisca di scriverli, poi riprova.")
    return
}
```

**User experience:**
- **Before:** a frozen app, then an error that points at the wrong thing. A newcomer would conclude their backup is broken.
- **After:** an immediate note to wait for the import, and the same file applies afterwards.

Confidence is "probable" for the five-second wait: it follows from the timeout in the code, and I did not time it before fixing. The fix itself is tested (`testYomitanSettingsWaitForTheImportToEnd`).

### 3. HeadwordGroup.swift:68 — a sort dictionary that is not installed or is switched off leaves results unsorted
**Lens:** Assumption Audit
**Assumption:** the frequency dictionary named in the settings exists on the phone and is switched on.
**Violation scenario:** a Yomitan backup from the computer names the frequency dictionary used there. If the phone does not have it, or you later switch it off in Dizionari, every word's rank comes back empty.
**Consequence:** results are no longer ordered by how common a word is. No message, and the picker in Impostazioni shows a blank choice.

**Code before:**
```swift
let sortDictionary = sortDictionary ?? store.frequencyDictionaries().first
```

**Fix applied:**
```swift
let available = store.frequencyDictionaries()
let sortDictionary = sortDictionary.flatMap { available.contains($0) ? $0 : nil } ?? available.first
```
The picker now lists the missing choice as "… (non disponibile)" (`SettingsView.swift:92`).

**User experience:**
- **Before:** after importing your Yomitan settings, rare words start appearing above common ones and you cannot tell why.
- **After:** the first available frequency dictionary orders the results until the chosen one is there, and the picker shows which one you chose.

### 4. AppModel.swift:350 — a frequency dictionary imports as "0 voci importate"
**Lens:** Boundary Conditions (zero)
**Violation scenario:** importing a frequency list or a pitch-accent dictionary, which hold no words at all. Almost everyone imports at least one.
**Consequence:** the summary read "JPDB: 0 voci importate", which looks like a failed import.
**Fix applied:** `AppModel.summary(of:)` (`:369`) says "JPDB: 500.000 frequenze e accenti importati" when there are no words and no kanji.
**User experience:**
- **Before:** you import a frequency list, read "0", and import it again or go looking for another file.
- **After:** the line says what the dictionary brought.

### 5. YomitanImporter.swift:35 — a .zip cut short or a malformed bank says only "the operation couldn't be completed"
**Lens:** Error Path Exerciser
**Violation scenario:** a download that did not finish (the commonest bad file), or a dictionary with one bank that is not in Yomitan's format.
**Consequence:** the alert passed the error's `localizedDescription`, which for these error types is Apple's generic sentence with a type name and a number.
**Fix applied:** the importer wraps archive failures in `YomitanImportError.unreadableZip` (`:39`, `:124`); the model gives it, and the two format errors, their own sentences (`AppModel.swift:385`). The Yomitan-backup message got the same treatment for a .json that holds no settings.
**User experience:**
- **Before:** "Import fallito: The operation couldn't be completed. (ZIPFoundation.Archive.ArchiveError error 3.)"
- **After:** "Non riesco a leggere questo file .zip: è rovinato o lo scaricamento non è finito. Scaricalo di nuovo."

The "before" wording is Apple's documented behaviour, not something I saw on the phone. That the new sentences are chosen for a half file and for a bad bank is tested (`testAFileThatIsNotAZipSaysSo`, `testAZipCutShortIsReportedAsSuchAndLeavesNothing`).

### 6. Diagnostics.swift:51 — the app writes over the share panel's diary lines
**Lens:** Assumption Audit
**Assumption:** this program is the only one writing the diary file.
**Violation scenario:** the diary is written by the app and by the share panel, which is a separate program. Each kept its own copy in memory and wrote the whole file from it.
**Consequence:** the app's next line erased everything the share panel had written since the app started. The diary exists to explain problems after the fact, and the share panel's half of it mostly never survived.
**Fix applied:** the file is read before every line and before every display (`Diagnostics.load()`, `:29`). Test: `testTwoProgramsWriteTheSameDiaryWithoutErasingEachOther`.
**User experience:**
- **Before:** no visible symptom, until the day something goes wrong in the share panel and Impostazioni › Diagnostica has nothing about it.
- **After:** no visible change; the lines are there when they are needed.

This only matters when the app and the panel share storage. With a signing that gives no App Group they keep separate folders, and the panel's diary is out of the app's reach either way.

### 7. SettingsView.swift:41 — "open screenshots" switches itself back off without a word
**Lens:** Error Path Exerciser
**Violation scenario:** you switch it on and answer "Don't Allow" to the Photos question, or had refused before.
**Fix applied:** an alert with the path to the permission, the same sentence the camera screen uses.
**User experience:**
- **Before:** the switch slides on and back off. It looks broken.
- **After:** it says Kotoba cannot see your photos and where to allow it.

### 8. AppModel.swift:262 — picking dictionary files when the database did not open does nothing
**Lens:** Error Path Exerciser
**Violation scenario:** the database failed to open at launch (announced once, in an alert). The first-run screen is then shown, with its "Scegli i file…" button.
**Fix applied:** a message that the dictionaries are not available and where the details are. Test: `testImportingWithNoDatabaseSaysSo`.
**User experience:**
- **Before:** you pick files and nothing happens, as many times as you try.
- **After:** you are told the database did not open.

## Fragile Code (Works Now, May Break Later)

### F1. AppModel.swift:400 — deleting or switching a dictionary while the database is busy is ignored silently
**Lens:** Error Path Exerciser
**Current behavior:** the screens disable these controls during an import or a delete, so the silent `return` is not normally reached.
**Breaking scenario:** a control that is not disabled (I could not confirm on Linux that a disabled row also disables its swipe action).
**Fix applied:** a short note, "Aspetta che Kotoba finisca di scrivere i dizionari", and an import asked for during a delete gets the same.
**User experience if it breaks:** you confirm "Elimina" and the dictionary stays, with no explanation.

### F2. WordsView.swift:14 — the filter of the Parole tab does not understand romaji
**Lens:** Assumption Audit
**Current behavior:** the filter matched kanji and kana only, while the main search box accepts "neko".
**Fix applied:** the filter tries the romaji readings too. Compiled against the stand-ins only; the logic lives in the screen file and has no test of its own.
**User experience if it breaks:** with an Italian keyboard you type "neko" and are told no word matches, although 猫 is in the list.

### F3. DictionariesView.swift:276 — the frequency switch does not appear after switching the dictionary on
**Lens:** Boundary Conditions
**Current behavior:** whether a dictionary has frequencies was looked up once, when its page opened; a dictionary that was off at that moment never showed the switch until the page was reopened.
**Fix applied:** looked up again when the dictionary is switched on or off.

### F4. DictionaryStore.swift:397 — index building at launch can meet an import
**Lens:** Assumption Audit
**Current behavior:** dictionaries imported with versions before 0.6 get their search indexes built at launch, in batches written through the main connection.
**Breaking scenario:** such a dictionary still waiting for its index, and an import started in the first moments after launch. The batch waits up to five seconds for the import while holding the lock searches need, then gives up until the next launch.
**Recommendation:** give the index builder its own connection, as import and delete have. Left open: it needs a dictionary from a very old version that never finished indexing, and the change touches code that 81 tests currently hold steady.
**User experience if it breaks:** one search that takes five seconds, and kana search for that old dictionary missing until Kotoba is opened again.

### F5. AppModel.swift:142 — anything that opens `kotoba://mined?k=…` ticks a word
**Lens:** Assumption Audit
**Current behavior:** the tick appears when AnkiMobile opens this address after saving the note.
**Breaking scenario:** another app or a web page opening the same address.
**Recommendation:** put a one-time code in the return address and accept only that. Left open: the worst outcome is a wrong tick on a word, which "Dimentica" in the Parole tab removes.

## Already Guarded (Reference)
- `AppModel.swift:303` — `importQueue.removeFirst()` follows `guard !importQueue.isEmpty`.
- `AppModel.swift:418` — the hand-made copy of `move(fromOffsets:toOffset:)` filters indexes and clamps the insert position.
- `Appearance.swift:269` — `all[0]` on a fixed, non-empty list of themes.
- `HeadwordGroup.swift:35-42` — `groups[key]!` right after the key is inserted.
- `SearchResults.swift:177`, `:185` — `found[key]!` for keys taken from `order`, which is filled together with `found`.
- `ResultsPage.swift:208`, `Anki.swift:211`, `:218`, `:241` — `[0]` only in the branch where the count is 1.
- `YomitanFormat.swift:99`, `:123`, `:139` — `row[0]` after `row.count >= 6`, `>= 3`, `>= 4`.
- `YomitanImporter.swift` — progress is 0, not a division by zero, for a dictionary with no banks.
- `Romaji.swift:62` — long-vowel spellings are capped at 27, so a word full of macrons cannot multiply searches without limit.
- `Deinflector.swift` — the new zero-length ending is skipped for empty text and for text that cannot end an ichidan stem.
- `DictionaryStore.end(ofPrefix:)` — steps past the surrogate gap and drops a last character that has no successor.
- `WordsView.swift` `ThumbIndex` — the row under the finger is clamped to the list; with no words there is nothing to jump to.
- `AnkiSettingsView.swift:108-116` — field bindings check the index, since a row can outlive its field for a moment.
- `SigningInfo.notice` — no profile gives no warning; an expired one says so.

## Needs Human Review
- `App/Sources/LongWork.swift:23` — when iOS's background time runs out, the import is asked to stop and the background task is ended only once it really has. If undoing a large half-written dictionary takes longer than the few seconds iOS leaves at that point, iOS closes the app. The database is safe either way (the half-written dictionary is discarded on the next open), but the "import was stopped" message would not appear. Only a phone can tell how long that takes. `needs-runtime`.

Also checked while here: the address behind "Apri l'elenco dei dizionari" (`https://yomitan.wiki/dictionaries/`) was fetched on 2026-11-10. It answers, and it lists Jitendex, JMdict, JMnedict, KANJIDIC and the frequency lists, each linking to its project page rather than straight to a .zip.

## Echo of these fixes

The project asks for bug-echo after every fix. For the fixes above, by pattern:

- **Text handed to a link builder without encoding (finding 1):** 1 other candidate family, 0 echoes. `MediaLink.swift:18`, `AudioPlayer.swift:20` and `ShareViewController.swift:69` all use `queryItems`, which encodes for them. `Anki.swift:281` was the only `percentEncoded…` setter in the code.
- **A write through the main connection while an import holds the database (finding 2):** `setEnabled` and `reorder` are behind `isBusy`; `apply` now is; the launch-time index builder is F4 above.
- **A setting that names something that may not be there (finding 3):** `collapsedDictionaries` naming a missing dictionary has no effect; `ankiFormat` names things in another app and cannot be checked. No echo.
- **An error shown through `localizedDescription` for a type that does not describe itself (finding 5):** covered for `SQLiteError`, `YomitanImportError`, `YomitanFormatError`, `DictionaryStoreError` and `YomitanSettings.ParseError`. The remaining uses (`DictionariesView.swift:228`, `AppearanceView.swift:100`) show Apple's own file errors, which describe themselves.
- **A file two programs write from memory (finding 6):** the settings are also shared, and the app already reads them again every time it comes to the front (`AppModel+Device.swift:13`). No echo.

Not scanned as part of this echo: the texthooker files. One thing seen in passing there, for that thread: `HookConnection.swift:42` builds its address by joining text, which returns no address for odd input instead of crashing, so it is not an echo of finding 1.

## Checks run after the fixes

- Engine: 81 tests, 0 failures.
- App logic: 61 tests, 1 skipped (the page renderer, which runs in CI), 0 failures.
- Translations: OK, 368 texts.
- Syntax parse of every app, shared and extension file: OK.
- Screen stand-in compile: 20 files.
