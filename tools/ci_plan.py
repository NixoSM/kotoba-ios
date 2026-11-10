#!/usr/bin/env python3
"""Decides what a CI run has to do, so Mac minutes are spent only when needed.

Called by the `changes` job of .github/workflows/build.yml. It answers:
  app        does this change touch anything that goes into the app?
  ocr        does it touch the camera code (tests that need a Mac)?
  pages      does it touch what the results page is drawn from (new photographs)?
  tree       the exact source tree, as git names it
  built_run  on main: the earlier run that already built this same tree
             (a merged pull request), so the app is not built twice
  mac        may this run use a Mac at all? Not while the pull request is a
             draft: the Mac waits for "Ready for review", or a run by hand

Run the self-test with:  python3 tools/ci_plan.py --self-test
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

# Anything that can change the app, its tests, or how they are built.
APP = re.compile(
    r"^(App/|Extensions/|Packages/|Entitlements/|Tests/|Package\.swift$|project\.yml$|"
    r"tools/ci_plan\.py$|tools/render_|tools/screen-check/|\.github/workflows/)"
)
# What the results page is drawn from: a change here gets new photographs of it.
PAGES = re.compile(
    r"^(App/Sources/(ResultsPage|Appearance|HeadwordGroup|SearchResults)\.swift$|App/Resources/Fonts/|"
    r"Packages/KotobaCore/Sources/KotobaCore/|Tests/KotobaAppLogicTests/(RenderTests|Fixtures)\.swift$|"
    r"tools/render_|\.github/workflows/)"
)
# The camera reader and its tests: these need Apple's recognizer.
OCR = re.compile(r"^Packages/KotobaCore/(Sources/KotobaOCR/|Tests/KotobaOCRTests/|Package\.swift$)")


def plan(files, full=False):
    """What a change to `files` needs. `None` means "unknown": do everything."""
    if files is None:
        return {"app": True, "ocr": full, "pages": True}
    return {
        "app": any(APP.search(f) for f in files),
        "ocr": full or any(OCR.search(f) for f in files),
        "pages": any(PAGES.search(f) for f in files),
    }


def mac_allowed(event, draft):
    """A draft pull request is work still in progress: Linux checks only.

    Marking it "Ready for review" starts a new run, and that one builds.
    A push to main and a run started by hand always may.
    """
    return not (event == "pull_request" and draft)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def changed_files(event, before):
    if event == "pull_request":
        # HEAD is GitHub's trial merge of the pull request: its first parent is the base branch.
        result = git("diff", "--name-only", "HEAD^1", "HEAD")
    elif event == "push" and before and set(before) != {"0"}:
        result = git("diff", "--name-only", before, "HEAD")
    else:
        return None  # started by hand, or nothing to compare with
    if result.returncode != 0:
        return None
    return [line for line in result.stdout.splitlines() if line]


def find_built_run(tree):
    """The run that uploaded the marker `built-<tree>`, or "" when there is none."""
    repo, token = os.environ.get("GITHUB_REPOSITORY"), os.environ.get("GH_TOKEN")
    if not repo or not token:
        return ""
    url = f"https://api.github.com/repos/{repo}/actions/artifacts?name=built-{tree}&per_page=10"
    request = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            data = json.load(response)
    except Exception as error:  # never let a lookup problem stop a build
        print(f"Could not ask GitHub about earlier builds ({error}): building.")
        return ""
    for artifact in data.get("artifacts", []):
        run = (artifact.get("workflow_run") or {}).get("id")
        if run and not artifact.get("expired"):
            return str(run)
    return ""


def main():
    event = os.environ.get("EVENT", "")
    full = os.environ.get("FULL", "") == "true"
    mac = mac_allowed(event, os.environ.get("DRAFT", "") == "true")
    files = changed_files(event, os.environ.get("BEFORE", ""))
    result = plan(files, full)
    tree = git("rev-parse", "HEAD^{tree}").stdout.strip()
    built_run = find_built_run(tree) if event == "push" and result["app"] and tree else ""

    repo = os.environ.get("GITHUB_REPOSITORY", "")
    lines = []
    if files is None:
        lines.append("Started by hand or nothing to compare with: doing everything.")
    else:
        lines.append(f"{len(files)} file(s) changed.")
    if not result["app"]:
        lines.append("Nothing that goes into the app changed: **no Mac build**.")
    elif built_run:
        lines.append(
            f"This exact code was already built: **download Kotoba-ipa from "
            f"[that run](https://github.com/{repo}/actions/runs/{built_run})**. No second Mac build."
        )
    elif not mac:
        lines.append(
            "This pull request is a draft: **no Mac build yet**, only the checks on Linux. "
            "To build Kotoba.ipa, open the pull request and press **Ready for review**."
        )
    else:
        lines.append("The app is built on a Mac." + (" The camera tests run too." if result["ocr"] else ""))
    print("\n".join(lines))

    outputs = {
        "app": "true" if result["app"] else "false",
        "ocr": "true" if result["ocr"] else "false",
        "pages": "true" if result["pages"] else "false",
        "tree": tree,
        "built_run": built_run,
        "mac": "true" if mac else "false",
    }
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            for key, value in outputs.items():
                out.write(f"{key}={value}\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as out:
            out.write("### What this run does\n" + "\n\n".join(lines) + "\n")
    print(outputs)


def self_test():
    def check(files, app, ocr, pages, full=False):
        assert plan(files, full) == {"app": app, "ocr": ocr, "pages": pages}, (files, plan(files, full))

    check(["README.md", "docs/texthooker.md"], False, False, False)
    check(["tools/textractor-extension/kotoba_websocket.c"], False, False, False)
    check(["App/Sources/SearchView.swift"], True, False, False)
    check(["App/Sources/ResultsPage.swift"], True, False, True)
    check(["App/Resources/Fonts/KleeOne-Regular.ttf"], True, False, True)
    check(["Packages/KotobaCore/Sources/KotobaCore/Romaji.swift"], True, False, True)
    check(["Packages/KotobaCore/Sources/KotobaOCR/VerticalOCR.swift"], True, True, False)
    check(["Packages/KotobaCore/Package.swift"], True, True, False)
    check(["Tests/KotobaAppLogicTests/AppModelTests.swift"], True, False, False)
    check(["tools/screen-check/run.sh"], True, False, False)
    check(["tools/render_screenshots.js"], True, False, True)
    check(["project.yml"], True, False, False)
    check([".github/workflows/build.yml"], True, False, True)
    check(["README.md"], False, True, False, full=True)
    check(None, True, False, True)
    check(None, True, True, True, full=True)
    check([], False, False, False)

    # Only a draft pull request keeps the Mac waiting.
    assert not mac_allowed("pull_request", True)
    assert mac_allowed("pull_request", False)
    assert mac_allowed("push", False)
    assert mac_allowed("workflow_dispatch", False)
    assert mac_allowed("workflow_dispatch", True)
    print("ci_plan self-test OK")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
    else:
        main()
