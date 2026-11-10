# bug-echo Report: the six bug shapes fixed by the health check

**Date:** 2026-11-10
**Pattern source:** user-described (six shapes, taken from the fixes in commits `2619f7f`, `909fa34`, `621eb46`, `70e5b74`, `26aa025`)
**Scan tool:** regex (`grep`), then every match read in its file
**Files scanned:** 61 Swift files (`App/Sources`, `App/Shared`, `Extensions`, `Packages/KotobaCore/Sources`)
**Pattern validated against pre-fix file:** n/a for user-described
**Checked on:** Linux only (engine tests, app-logic tests, syntax parse, screen stand-in compile). Nothing here was verified on a phone. The Mac build on the pull request is the first real compile of the screen files.

## Pattern

The health check fixed six kinds of mistake. This scan looked for the same kinds elsewhere.

| # | Anti-pattern | Correct pattern | Search |
|---|---|---|---|
| P1 | An error is thrown away (`try?`, `catch { return [] }`) and the screen shows "nothing", with no reason anywhere | Tell the person, or at least write it in the diary (Impostazioni › Diagnostica) | `try\?`, `catch \{\s*return` |
| P2 | Long database work on the main thread, or under the lock that searches need | Work away from the screen, on its own connection or in small batches | calls to the store from `@MainActor` code |
| P3 | Something is marked as done at the tap, not when it is known to have worked | Mark it on confirmed success | `markMined`, `remember(`, saved "seen" keys |
| P4 | Text from a dictionary file reaches HTML, CSS or an attribute without escaping | `GlossaryHTML.escape`, percent-encoding, plain-name checks | string interpolation into `"<…"` |
| P5 | Looking a file up by path inside a loop over the same archive | One pass over the archive | `archive[` |
| P6 | A late answer from a finished job overwrites the state of the job that replaced it | Check that the answer still belongs to the current job | `Task { @MainActor`, `.task(id:`, `DispatchQueue.main.async`, `MainActor.run` |

## Summary

- BUG findings: 3 (all fixed)
- WATCH findings: 8 (5 fixed, 1 partly, 2 left as they are)
- OK findings: listed at the end, with the 5 reference sites marked CANON
- REVIEW findings: 0

P2 and P5 produced no findings: the remaining database calls on the main thread are single small queries, the index building takes the lock per batch of 4,000 or 8,000 rows, and no per-path archive lookup is left.

## BUG Findings

### Issue Rating Table

| # | Finding | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | A photo from the library that cannot be opened does nothing and says nothing (P1) | 🟢 MEDIUM | ⚪ Low | 🟢 Medium | 🟢 Good | ⚪ 1 file | Trivial | Fixed |
| 2 | A screenshot that cannot be loaded does nothing and says nothing (P1) | 🟢 MEDIUM | ⚪ Low | 🟢 Medium | 🟢 Good | ⚪ 1 file | Trivial | Fixed |
| 3 | Alerts about a database error hide the actual reason (P1) | 🟢 MEDIUM | ⚪ Low | 🟢 Medium | 🟠 Excellent | 🟢 6 alerts, 1 file changed | Trivial | Fixed |

**Reference implementation:** `App/Sources/AppModel.swift:99` (`refresh()`): the error goes to the person through `report(…)` and to the diary in the same line. Findings 1 and 2 follow that shape with a toast, because the camera screen's own note line (`CameraView.swift:133`) is only visible while no picture is shown.

### Detailed findings

**1. A photo from the library that cannot be opened does nothing and says nothing**

`App/Sources/CameraView.swift:163` (before the fix)

```swift
Task {
    if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
        show(picked)
    }
    pickerItem = nil
}
```

**Why this is a bug:** when the photo cannot be read (still in iCloud with no network, or a format iOS will not decode) the `if` is simply skipped.
**Fix applied:** the `else` branch calls `cannotOpen()`, which shows "Non riesco ad aprire questa immagine" and writes a diary line (`CameraView.swift:167`, `:238`). Same shape as `AppModel.swift:99`.
**User experience:**
- **Before:** you pick a photo, the picker closes, and the screen stays exactly as it was. Nothing tells you whether to wait or try again.
- **After:** a short message at the bottom says the picture could not be opened.

**2. A screenshot that cannot be loaded does nothing and says nothing**

`App/Sources/CameraView.swift:231` (before the fix)

```swift
let picked: UIImage? = await withCheckedContinuation { continuation in
    PHImageManager.default().requestImage(for: asset, …) { image, _ in continuation.resume(returning: image) }
}
if let picked { show(picked) }
```

**Why this is a bug:** Photos answers `nil` when it cannot produce the image. The two cases before it (no permission, no screenshot found) each show a note; this third one was forgotten.
**Fix applied:** `else { cannotOpen() }` (`CameraView.swift:234`).
**User experience:**
- **Before:** you take a screenshot, come back to Kotoba, the Camera tab opens and stays empty. Because the screenshot was already marked as seen (see WATCH 8), it is not offered again.
- **After:** the same message as in finding 1, and "Ultimo screenshot" is there to try again.

**3. Alerts about a database error hide the actual reason**

`Packages/KotobaCore/Sources/KotobaCore/SQLite.swift:9` (before the fix), shown through `error.localizedDescription` at `App/Sources/AppModel.swift:99`, `:364`, `:375`, `:392`, `:420` and the new `:108`.

```swift
public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite \(code): \(message)" }
}
```

**Why this is a bug:** the alerts added in step E pass `error.localizedDescription`. For an error type that does not say how to describe itself to people, Apple's answer is the generic "The operation couldn't be completed. (KotobaCore.SQLiteError error 1.)". The real message only reached the diary.
**Fix applied:** `SQLiteError` now conforms to `LocalizedError` and gives its own description (`SQLite.swift:14`). One line, and every alert that shows a database error gains the real text.
**User experience:**
- **Before:** "Non riesco a eliminare «JMdict»: The operation couldn't be completed." You cannot tell a full disk from a damaged file.
- **After:** "Non riesco a eliminare «JMdict»: SQLite 13: database or disk is full".

This one is stated from reading the code and from the Linux test `testALookupThatCannotReadTheDatabaseSaysWhy`. The generic wording quoted above is Apple's documented behaviour, not something I saw on the phone.

## WATCH Findings (near-threshold, defensive only)

### Issue Rating Table

| # | Finding | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | Settings that cannot be read are replaced by defaults, silently, and saved over (P1) | 🟢 MEDIUM | ⚪ Low | 🟡 High | 🟠 Excellent | 🟢 2 files | Small | Fixed |
| 2 | Every lookup in the engine answers "nothing found" when the database cannot be read (P1) | 🟢 MEDIUM | ⚪ Low | 🟢 Medium | 🟢 Good | 🟢 13 sites, 3 files | Small | Fixed |
| 3 | Your own CSS is written into the page as typed (P4) | ⚪ LOW | ⚪ Low | ⚪ Low | 🟢 Good | ⚪ 1 file | Trivial | Fixed |
| 4 | A slow audio download plays over the word asked for after it (P6) | ⚪ LOW | ⚪ Low | ⚪ Low | 🟢 Good | ⚪ 1 file | Trivial | Fixed |
| 5 | A slower photo picked earlier replaces the one picked after it (P6) | ⚪ LOW | ⚪ Low | ⚪ Low | 🟡 Marginal | ⚪ 1 file | Trivial | Fixed |
| 6 | The share panel closes without a word when it cannot read what was shared (P1) | ⚪ LOW | ⚪ Low | ⚪ Low | 🟡 Marginal | ⚪ 1 file | Trivial | Partly: diary line only |
| 7 | The texthooker saves its lines without checking that the write worked (P1) | ⚪ LOW | ⚪ Low | 🟢 Medium | 🟢 Good | ⚪ 1 file | Trivial | Deferred: another thread's files |
| 8 | A screenshot is marked as seen before it is known to have opened (P3) | ⚪ LOW | 🟡 High | ⚪ Low | 🔴 Poor | ⚪ 1 file | Small | Skipped on purpose |

### Detailed findings

**1. Settings that cannot be read are replaced by defaults, silently, and saved over**

`App/Sources/AppSettings.swift:48` and `App/Sources/AppModel+Device.swift:12` (before the fix)

```swift
static func load() -> AppSettings {
    guard let data = …, let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
    return settings
}
// every time Kotoba comes to the front:
let saved = AppSettings.load()
if saved != settings { settings = saved }   // didSet saves
```

**Why this is WATCH not BUG:** today both programs that write the settings (the app and the share panel) are the same build, so the shapes always agree. It becomes real the day a later version changes the shape of the Anki note, or of any of the four parts that were read strictly (`ankiFormat`, `sortFrequencyDictionary`, `mined`, `collapsedDictionaries`).
**Fix applied:** each part is read on its own and falls back to its default alone (`AppSettings.swift:34`). When anything could not be read, the saved data is copied once to `settings.v1.unreadable` and a diary line names the parts (`:75`). Coming back to the app no longer replaces the settings in use with defaults when the saved ones cannot be read at all (`AppModel+Device.swift:13`). Tests: `testAPartInAnotherShapeDoesNotLoseTheRest`, `testSettingsThatCannotBeReadAreKeptApart`.
**User experience if it crosses the threshold:** after an update the theme, the Anki note setup, the search history and the whole list of words already sent to Anki are gone at once, with no message. That list has no other copy: AnkiMobile cannot tell Kotoba which words it has.
**Limit of the fix:** nothing reads the kept copy back yet. It is there so that a later version, or I with the diary in hand, can recover from it.

**2. Every lookup in the engine answers "nothing found" when the database cannot be read**

`Packages/KotobaCore/Sources/KotobaCore/DictionaryStore.swift`, 13 sites before the fix: eight `try?` (`index(ofDictionary:)`, `stylesheets()`, three in `reverseSearch`, `frequencyDictionaries()`, `media`, `loadGlossaries`) and five `catch { return … }` (`frequencyRanks`, `termMeta`, `lookup`, `kanji`, `entriesStarting`).

```swift
} catch {
    return []
}
```

**Why this is WATCH not BUG:** it is a deliberate design, and a sound one: a search should never fail halfway because one side query did. The database is in WAL mode, so reads do not collide with an import. It only matters when the file is damaged or was written by a build with a different table layout.
**Fix applied:** the design stays. The store gained one listener, `onReadError` (`DictionaryStore.swift:177`), told by all 13 sites. The app writes each distinct failure in the diary once per launch (`Diagnostics.logOnce`) and shows one alert per launch, "La ricerca non riesce a leggere i dizionari: …" (`AppModel.swift:79`, `:105`). Also fixed on the way: a list of frequency dictionaries that could not be read was remembered as empty until the next change to the dictionaries (`DictionaryStore.swift:644`). Tests: `testALookupThatCannotReadTheDatabaseSaysWhy`, `testASearchThatCannotReadTheDatabaseSaysSoOnce`.
**User experience if it crosses the threshold:** every search says "Nessun risultato" as if the word did not exist, and the diagnostics page, which was built for exactly this moment, has nothing in it.

**3. Your own CSS is written into the page as typed**

`App/Sources/ResultsPage.swift:67` (before the fix): `<style>\(a.customCSS)</style>`

**Why this is WATCH not BUG:** it is text you typed yourself or imported from your own Yomitan backup, not text from a dictionary, and the page's content policy already stops it from running or loading anything. The only effect is cosmetic: a `</style>` inside it (for example in a `content: "…"` string) ends the style block early and the rest of your CSS appears as text at the top of every results page.
**Fix applied:** `</` becomes `<\/`, which means the same to CSS and nothing to HTML (`ResultsPage.ownCSS`, `:75`). Ordinary CSS, including `@media (width < 600px)`, is untouched. Test: `testYourOwnCSSCannotSpillOntoThePage`.
**User experience if it crosses the threshold:** a line of raw CSS printed above the results after pasting a snippet from the web.

**4. A slow audio download plays over the word asked for after it**

`App/Sources/AudioPlayer.swift:21` (before the fix)

**Why this is WATCH not BUG:** it needs two taps on two different play buttons while the first download is still running, which takes a slow connection.
**Fix applied:** each request takes a number, and a download that arrives after a newer request stays silent (`AudioPlayer.swift:23`, `:28`). Not testable on Linux (no AVFoundation there).
**User experience if it crosses the threshold:** you tap word A, nothing, you tap word B, B starts and is cut off by A.

**5. A slower photo picked earlier replaces the one picked after it**

`App/Sources/CameraView.swift:160` (before the fix). Same shape as 4, for two photos picked in quick succession.
**Fix applied:** the loaded picture is shown only if it is still the one selected (`CameraView.swift:165`, `:169`). Reference: `App/Sources/PhotoReader.swift:173` (`shown === image`).

**6. The share panel closes without a word when it cannot read what was shared**

`Extensions/Share/ShareViewController.swift:38` (line 37 before the fix): `guard let text = await sharedText() else { return finish() }`

**Why this is WATCH not BUG:** iOS only offers Kotoba for text, so there is normally something to read.
**Fix applied (partial):** a diary line, "Nothing to read in what was shared" (`:39`). A message on screen would need the panel to be built first and was left out: it is more than this finding is worth.
**User experience if it crosses the threshold:** you choose Kotoba in the share sheet and the sheet just closes.

**7. The texthooker saves its lines without checking that the write worked**

`App/Sources/Texthooker/HookerModel.swift:244` and `:252`: `try? data.write(to: url, options: .atomic)`

**Why this is WATCH not BUG:** the write only fails when the phone is out of space.
**Suggested fix (defensive, not urgent):** `do { try … } catch { Diagnostics.shared.log("Texthooker lines not saved: \(error)") }`.
**Status:** not touched. These files belong to the texthooker work in another thread, and I was asked to stay out of them.
**User experience if it crosses the threshold:** the lines received from the PC are gone the next time the app opens, with no trace of why.

**8. A screenshot is marked as seen before it is known to have opened**

`App/Sources/AppModel+Device.swift:66`: the screenshot's id is saved, then the Camera tab is asked to open it.

**Why this is WATCH not BUG:** "seen" here means "Kotoba already offered this one", and it has to be saved first or the same screenshot would reopen every time you come back to the app. With BUG 2 fixed, a failed load now says so, and the "Ultimo screenshot" button opens it on demand.
**Suggested fix:** none. Moving the mark to after the load would trade a silent case that is now announced for a screenshot that keeps reopening.

## OK Findings (intentional, no action needed)

Reference sites (OK, CANON):
- `App/Sources/AppModel.swift:99` - P1: a failed read is shown to the person and written in the diary.
- `App/Sources/AppModel.swift:310` - P6: progress from an import that is no longer the current one is ignored (`position == importDone + 1`).
- `App/Sources/SearchView.swift:60` - P6: a search result is dropped when a newer query took over. `CameraView.swift:180`, `LensView.swift:122`, `ResultsPane.swift:70` and `ShareViewController.swift:165` do the same.
- `App/Sources/PhotoReader.swift:159`, `:173`, `:350` - P6: text recognition answers are dropped when another picture is on screen.
- `Packages/KotobaCore/Sources/KotobaCore/GlossaryHTML.swift:114`, `:128` - P4: attribute and style names from a dictionary must be plain names, and their values are escaped.

P1, intentional:
- `App/Sources/Appearance.swift:54`, `App/Sources/Texthooker/HookerModel.swift:36-41`, `Packages/KotobaCore/Sources/KotobaCore/HookText.swift:66-71` - a missing or odd setting falls back to its default, which is the purpose.
- `App/Sources/Appearance.swift:149`, `:154`, `App/Sources/Palette.swift:34`, `App/Shared/SharedStorage.swift:24`, `:36`, `:69`, `:78` - creating a folder that may exist, listing a folder that may not, tidying up.
- `App/Sources/LensView.swift:439`, `:454`, `:472`, `:514`, `:523`, `:531` - camera settings that are optional refinements. Camera permission itself is handled and explained at `LensView.swift:106`.
- `App/Sources/ResultsWebView.swift:33` - falls back to loading the whole page; `:105` answers the page's request with a failure.
- `App/Sources/Diagnostics.swift:31`, `:58`, `:74` - the diary cannot log its own failure to write.
- `App/Sources/Diagnostics.swift:110`, `:118`, `App/Shared/SharedStorage.swift:86`, `:89` - reading the signing profile, absent in tests and the simulator; the page then shows "unknown".
- `App/Sources/AppModel.swift:449` - size of the database file for the diagnostics page.
- `App/Sources/AppSettings.swift:114`, `HookerModel.swift:53` - encoding these plain types cannot fail.
- `App/Sources/AudioPlayer.swift:55` - handing the sound back to the music app.
- `App/Sources/PhotoReader.swift:159` - Live Text is an extra on top of the app's own reading, which reports on its own.
- `Packages/KotobaCore/Sources/KotobaCore/Glossary.swift:9`, `GlossaryHTML.swift:11`, `DictionaryStore.swift:216`, `:577`, `:580`, `:614`, `:725`, `:726` - one malformed entry inside a dictionary is skipped instead of failing the whole search.
- `Packages/KotobaCore/Sources/KotobaCore/SQLite.swift:68` - rollback after an error that is itself rethrown.
- `Packages/KotobaCore/Sources/KotobaOCR/VerticalOCR.swift:438`, `:449`, `HorizontalOCR.swift:25`, `:35` - a tile that cannot be read yields no text.
- `Extensions/Share/ShareViewController.swift:79` - tries the next attachment.
- All `try? await Task.sleep` - a cancelled pause.

P2: `refresh`, `frequencyDictionaries`, `index(ofDictionary:)`, `setEnabled`, `reorder` are single small queries. `buildMissingReverseIndexes` and `buildMissingKanaIndexes` run detached and take the lock per batch. Delete and import run on their own connections. `App/Sources/KotobaApp.swift:49` (texthooker readings) is one indexed lookup per word.

P3: `App/Sources/AppModel+Device.swift:42` marks the clipboard as looked at before reading it, on purpose: reading again would raise the paste prompt again. `App/Sources/SearchView.swift:66` remembers a search only after results arrived and you stopped typing. `AppModel.swift:143` ticks a word only when AnkiMobile calls back with success (the original fix).

P4: every interpolation in `ResultsPage.swift` and `Anki.swift` goes through `GlossaryHTML.escape` or percent-encoding, or carries HTML already produced by `GlossaryHTML`. Dictionary titles in CSS selectors go through a hash (`ResultsPage.scopeID`). Fonts come from a fixed list. New results reach the page as a JSON literal (`ResultsWebView.swift:33`).

P5: no match. `YomitanImporter.swift:41` walks the archive once.

P6: `AppModel.swift:216-231` (index progress) is safe while the function is called once, at launch. A comment now says so.

## REVIEW Findings (need human judgment)

None.

## Checks run after the fixes

- Engine: 79 tests, 0 failures (`swift test` in `Packages/KotobaCore`, Linux).
- App logic: 55 tests, 1 skipped (the page renderer, which only runs in CI), 0 failures.
- Translations: OK, 360 texts.
- Syntax parse of every app, shared and extension file: OK.
- Screen stand-in compile: 20 files.
- Not compiled anywhere yet: `CameraView.swift`, `AudioPlayer.swift`, `AppModel+Device.swift` and the share panel. They pass the syntax parse only. The Mac build will be their first real compile.
