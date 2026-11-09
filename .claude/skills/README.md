# Project skills

Third-party Claude skills vetted for Kotoba. Each folder is the upstream `skills/<name>/`
directory, unchanged, plus its `LICENSE`, `NOTICE` and the upstream commit it was copied
from (`.upstream-commit`). All three are by Terry Nyberg / Coffee & Code LLC, Apache-2.0.

| Skill | Upstream | When it runs |
|---|---|---|
| `bug-echo` | https://github.com/Terryc21/bug-echo | After a bug fix: find other places with the same defect |
| `bug-prospector` | https://github.com/Terryc21/bug-prospector | Before a release or after a big feature: hunt for bugs that haven't fired yet |
| `tutorial-creator` | https://github.com/Terryc21/tutorial-creator | Only on request: annotated lessons from Kotoba's own code |

Left out on purpose: `bug-echo/agents/` (Codex config), `tutorial-creator/examples/`
(sample output, including a PDF), and the Python/TypeScript/Rust progressions.

## How these skills must adapt to this project

The skills were written for someone at a Mac with Xcode, answering questions live.
Kotoba is different, and these notes override the skills where they conflict.

- **No Mac, no Xcode, no Swift in the sandbox.** GitHub Actions is the only compiler.
  Where a skill says "build both platforms" or "verify with Instruments/simulator", push
  to a branch and run the `build.yml` workflow instead, and say the check is CI-only.
  Never claim a fix was verified on a device.
- **The person is usually away.** Where a skill asks a multiple-choice question
  (AskUserQuestion), take the option marked Recommended, say which one you took, and
  continue. Ask only before something that cannot be undone.
- **bug-prospector Step 0:** the answer is always "iOS only". Kotoba is sideloaded with a
  free Apple ID, not on the App Store, so treat it as *not* store-distributed and drop
  the 1-Star Risk column.
- **Reports:** write them to `.agents/research/` on the working branch as the skills say,
  and attach a copy in the thread. Don't commit reports to `main` unless asked.
- **Commits:** follow the repo's normal commit rules and attribution. The `bug-echo:`
  subject prefix is fine to keep.
- **tutorial-creator:** run it only when asked. Its config and progress live in
  `.claude/tutorial-config.yaml` and `tutorials/`; commit them, because cloud sessions
  lose anything not in git (the `~/.claude/tutorial-creator/registry.yaml` it offers to
  write does not survive). The Anki/PDF flashcard export installs `genanki`, `mistune` or
  `reportlab` from PyPI; ask first.

## Updating

Re-copy `skills/<name>/` from upstream, update `.upstream-commit`, and re-read the diff
before committing: these files are instructions Claude follows.
