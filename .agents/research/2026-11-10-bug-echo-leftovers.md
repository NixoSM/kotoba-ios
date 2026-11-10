# bug-echo: the three leftovers of the health check

Date: 2026-11-10. Branch: `claude/project-thread-lalraj`. Scope: the fixes for F4 and F5 of
`2026-11-10-bug-prospector-health-check-branch.md`, and the kanji frequency lists.
Checked on Linux only (engine 82 tests, app logic 64, screen stand-ins). Nothing here was
verified on a device.

## The fixes echoed

| # | Fix | Pattern looked for elsewhere |
|---|---|---|
| P1 | `kotoba://mined` now needs a code only this copy of Kotoba knows (`MinedLink.code`) | An address any app can open that changes what Kotoba remembers |
| P2 | Imports, deletes and Yomitan settings wait while the launch-time index builder writes (`AppModel.isIndexing`) | A write through the connection searches use, while another writer may hold the database |
| P3 | `kanji_meta_bank` files are read (schema 7, table `kanji_meta`) | A file of a Yomitan dictionary that the importer drops without a word |

## Findings

| # | Where | Class | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `AppModel.swift` `handle(url:)`, case `search` | OK | – | – | – | – | – | – | Meant to be open: the widget and the share panel use it; it only fills the search box |
| 2 | `ResultsPane.swift` `search`, `lookup`, `audio`, `mine` links | OK | – | – | – | – | – | – | Reached only from the results page, which loads no foreign script (CSP + nonce); `onOpenURL` in `KotobaApp.swift` goes to `AppModel.handle(url:)` and never to these |
| 3 | `AppModel.swift` `setEnabled`, `move`, `delete`, `importYomitanSettings` | OK (CANON) | – | – | – | – | – | – | All behind `isBusy`, which now includes the index builder |
| 4 | `YomitanImporter.swift` file list: `tag_bank_N.json` is not read | WATCH | ⚪ Low | ⚪ Low | ⚪ Low | 🟡 Marginal | ⚪ 2 files | Medium | Left open |
| 5 | Dictionaries imported before this version | WATCH | ⚪ Low | – | ⚪ Low | – | – | – | Told to the person |

### 4. Tag notes of a dictionary are dropped
`tag_bank` files explain a dictionary's tags ("v5" = "godan verb") and give them a colour group.
Kotoba shows the tag names as written and never the explanation.
**User experience now:** a tag such as `uk` or `v5r` is shown bare; in Yomitan, hovering it says what it means.
**After a fix:** tapping or reading a tag would give its meaning. This is a feature of its own, not a bug of this change, so it is left for a decision.

### 5. Kanji frequencies of lists already on the phone
A list imported with 0.16.0 or earlier had its `kanji_meta_bank` files skipped: the numbers are not in the database.
**User experience:** no frequency under the kanji until that dictionary is deleted and imported again. Nothing is lost or wrong meanwhile.

## Not verifiable here
- Whether AnkiMobile returns the address unchanged with two query items (`c` and `k`). It did with one. If it does not, the tick will not appear after saving a note, and the diary will hold the line "A note-saved address without Kotoba's code was ignored".
- The share panel and the app must read the same code: it is kept in the shared settings (`SharedStorage.defaults`). On Linux a stand-in takes its place.
