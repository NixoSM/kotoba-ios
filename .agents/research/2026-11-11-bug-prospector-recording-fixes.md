# Bug Prospector Report: screen-recording fixes (PR #8, v0.16.2)

**Date:** 2026-11-11
**Scope:** files changed on `claude/project-thread-os2u9y` against `main` (LensView, ReadingSupport, ResultsPage, ResultsWebView, SearchResults, AppSettings, PhotoReader, WordAim, VerticalOCR, GrayImage). Only the changed code paths were read closely.
**Lenses Applied:** Quick 3: Assumption, Error Path, Boundary
**Platform:** iOS only. The app is sideloaded, not on a store, so there is no 1-Star Risk column (see `.claude/skills/README.md`).
**Source glob:** `**/*.swift` (plus the page's own JavaScript inside ResultsPage.swift)
**Accelerators:** full. Run on Linux plus a Playwright check of the fold script; camera code is CI-only.

## Summary

| Status | Count |
|--------|-------|
| Bugs Found | 0 (1 fragile item fixed before release) |
| Fragile Code | 3 |
| OK (Already Guarded) | 7 |
| Needs Review | 0 |

## Issue Rating Table

| # | Finding | Lens | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Confidence | Status |
|---|---------|------|---------|-----------|-------------|-----|-------------|------------|------------|--------|
| F1 | ResultsPage.swift fold script: measured once, even before the page had a width | Assumption / Boundary | 🟢 Medium | ⚪ Low | 🟢 Medium | 🟠 Excellent | ⚪ 1 file | Trivial | verified (Playwright, 50 px → 393 px) | Fixed |
| F2 | ResultsPage.swift fold script: pictures that load after the measurement make a definition taller without folding it | Boundary | ⚪ Low | ⚪ Low | ⚪ Low | 🟡 Marginal | ⚪ 1 file | Small | probable | Deferred |
| F3 | LensView.swift readSentence: reading the next columns (up to 8 vertical reads) runs on the frame queue | Boundary | ⚪ Low | ⚪ Low | ⚪ Low | 🟡 Marginal | ⚪ 1 file | Small | needs-runtime | Deferred |

## Fragile Code

### F1. ResultsPage.swift, `window.kotobaFold`: fixed
**Current behavior (before the fix):** each definition was measured once, the first time the script ran. If WebKit ran it before the view had its size, every line wrapped one character at a time, so short definitions looked tall, folded, and showed "Show all".
**Fix:** the script measures nothing while the page is narrower than 120 px, and runs again on `resize`. Checked in Chromium: a page loaded at 50 px wide folds nothing, and after it is resized to 393 px the long definition folds.
**User experience if it breaks:** short definitions would show half-faded with a "Show all" button they don't need.

### F2. Pictures that load after the measurement
**Breaking scenario:** a definition made mostly of dictionary pictures. The images load after the script runs, the definition gets taller, and it stays unfolded.
**Recommendation:** run the fold again on each image's `load` event if this ever shows up.
**User experience if it breaks:** that one definition doesn't fold. Nothing is hidden or lost.

### F3. Reading the next columns pauses live reading
**Current behavior:** once per new word, and only when its sentence reaches the edge of its column, up to 4 reads on each side run on the camera's frame queue.
**Breaking scenario:** a slow phone, or a page where no neighbouring column is found, so all 8 reads run.
**User experience if it breaks:** after a word locks, the dashed outline may stop following for a moment. Needs the phone to measure.

## Already Guarded (Reference)
- LensView `onChange(of: sentence)`: it changes the results only when they belong to the current word (`searchedText == pick.query`). A sentence for a new word can't land on the old word's results. It also fixes an older gap: tapping the same word in a second sentence used to keep the first sentence for Anki, because the search didn't run again for the same text.
- LensView `onSentence`: it is dropped when the word on screen has changed (`pick == picked`, and `stabilizer.shown == shownPick` on the view's side).
- `readSentence`: it uses the pick from the frame the columns were read in (`lastRead.pick`), and only when it is the same word.
- `VerticalOCR.neighbours`: it stops at the picture's edge, takes only a column on the right side no more than 3 em away, and returns nil when there is none. The sentence then stays as one column.
- `WordAim.sentenceEdges` / `sentence(of:before:after:)`: an empty line returns (false, false), and the start index is clamped. A column that begins with a closing bracket after 。 is cut correctly by `sentence(in:around:)`. Tests are in WordAimTests.
- `OCRLine.adjacent`: lines with no frame are skipped. It behaves the same as the photo reader's old inline code: nearest overlapping line, within 2.5 line widths.
- `AppSettings.remember`: the limit is 20 characters, so Japanese inflected forms and short English phrases still count. Long chips saved before this version are kept until 40 newer searches push them out.

## After You Fix These Findings
F1 was fixed in this branch. bug-echo on the branch's bug fixes (heading/results mismatch, single-column sentence) is in the PR description.
