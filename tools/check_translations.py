#!/usr/bin/env python3
"""Checks that no Italian is left over when Kotoba runs in English or Japanese.

Run from the repository root:  python3 tools/check_translations.py
It exits with an error, and says where, when:
  1. a tr("…") key is missing from L10n.table, or the table has a key twice;
  2. an English or Japanese translation is empty, still Italian, or has
     different {0} placeholders from the Italian;
  3. a SwiftUI view or an App Intent shows a Latin-letter text that skips tr()
     (in the widget/intent files, which can't use tr(), the text must be a key
     in Localizable.strings instead);
  4. the it/en/ja .strings files don't have the same keys, or Info.plist
     permission texts in project.yml have no InfoPlist.strings translation.
No Swift needed: CI runs it on Linux in a few seconds.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANGS = ("it", "en", "ja")
STR = r'"((?:[^"\\\n]|\\.)*)"'

# Words that only appear in Italian. Some are also English or brand words
# ("Kotoba", "Anki"), so this list holds only unambiguous ones.
ITALIAN_WORDS = {
    "il", "della", "dello", "degli", "delle", "nel", "nella", "sono", "perché", "è",
    "oppure", "anche", "questo", "questa", "cerca", "appunti", "lente", "apri",
    "impostazioni", "fotocamera", "dizionari", "dizionario", "parola", "parole",
    "tocca", "seleziona", "scatta", "aggiungi", "elimina", "chiudi", "mostra",
    "nessun", "nessuna", "voci", "lingua", "aspetto", "tema", "testo", "ricerca",
}
# Italian on purpose: the search box lists the languages you can type in.
ALLOWED_ITALIAN = {"日本語 · English · italiano · romaji", "イタリア語"}

# Texts that are fine in every language: names, units, Japanese.
UNTRANSLATED_OK = {"Kotoba", "Anki", "OK", "Auto", "Layout", "Zoom"}

errors = []


def fail(path, line, msg):
    errors.append(f"{path.relative_to(ROOT)}:{line}: {msg}")


def unescape(s):
    """Swift/.strings escapes that matter here; \\( interpolation stays as is."""
    return re.sub(r'\\(["\\nt])', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def placeholders(s):
    return sorted(set(re.findall(r"\{\d+\}", s)))


def looks_italian(text):
    if text in ALLOWED_ITALIAN:
        return False
    words = re.findall(r"[A-Za-zàèéìòùÀÈÉÌÒÙ']+", text)
    return any(w.lower().strip("'") in ITALIAN_WORDS for w in words)


def needs_translation(text):
    """A text a reader would see as words: has Latin letters, not just a name."""
    stripped = re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "", text)  # Swift interpolation
    if stripped.strip() in UNTRANSLATED_OK:
        return False
    stripped = re.sub(r"\b(pt|ms)\b", "", stripped)  # units
    return re.search(r"[A-Za-zàèéìòù]{2,}", stripped) is not None


def line_of(text, index):
    return text.count("\n", 0, index) + 1


# 1–2. The tr() table ---------------------------------------------------------
l10n_path = ROOT / "App/Sources/L10n.swift"
l10n = l10n_path.read_text(encoding="utf-8")
start = l10n.index("static let table")
table_src = l10n[start:]
entry_re = re.compile(STR + r"\s*:\s*\(\s*" + STR + r"\s*,\s*" + STR + r"\s*\)", re.S)
table = {}
for m in entry_re.finditer(table_src):
    key, en, ja = (unescape(g) for g in m.groups())
    line = line_of(l10n, start + m.start())
    if key in table:
        fail(l10n_path, line, f"key is in the table twice (the app would crash): {key!r}")
    table[key] = (en, ja)
    for lang, value in (("en", en), ("ja", ja)):
        if not value.strip():
            fail(l10n_path, line, f"{lang} translation is empty for {key!r}")
        elif placeholders(value) != placeholders(key):
            fail(l10n_path, line, f"{lang} placeholders {placeholders(value)} differ from {placeholders(key)} in {key!r}")
        if looks_italian(value):
            fail(l10n_path, line, f"{lang} translation still contains Italian: {value!r}")
# A line like `"x": (` the regex didn't understand would hide a key.
declared = len(re.findall(r'^\s*' + STR + r'\s*:', table_src, re.M))
if declared != len(table):
    fail(l10n_path, line_of(l10n, start), f"table has {declared} keys but only {len(table)} could be read: check its syntax")

swift_files = sorted(p for d in ("App", "Extensions") for p in (ROOT / d).rglob("*.swift"))
tr_re = re.compile(r"\btr\(\s*" + STR)
for path in swift_files:
    src = path.read_text(encoding="utf-8")
    for m in tr_re.finditer(src):
        key = unescape(m.group(1))
        if "\\(" in m.group(1):
            fail(path, line_of(src, m.start()), f"tr() key uses \\( \\) interpolation, so it can never match: use {{0}}: {key!r}")
        elif key not in table:
            fail(path, line_of(src, m.start()), f"missing from L10n.table (shows in Italian in en/ja): {key!r}")

# 4. .strings files --------------------------------------------------------------
strings_re = re.compile(r"^\s*" + STR + r"\s*=\s*" + STR + r"\s*;", re.M)


def read_strings(path):
    src = path.read_text(encoding="utf-8")
    return {unescape(k): unescape(v) for k, v in strings_re.findall(src)}


string_tables = {}  # (folder, file name) -> {lang: {key: value}}
for path in sorted(ROOT.rglob("*.lproj/*.strings")):
    if ".git" in path.parts:
        continue
    lang = path.parent.name.removesuffix(".lproj")
    string_tables.setdefault((path.parent.parent, path.name), {})[lang] = (path, read_strings(path))

for (folder, name), by_lang in string_tables.items():
    missing_langs = [l for l in LANGS if l not in by_lang]
    if missing_langs:
        some = next(iter(by_lang.values()))[0]
        fail(some, 1, f"{name} has no {', '.join(missing_langs)} version next to it")
    all_keys = set().union(*(set(t) for _, t in by_lang.values()))
    for lang, (path, values) in by_lang.items():
        for key in sorted(all_keys - set(values)):
            fail(path, 1, f"{lang}: missing key {key!r}")
        if lang in ("en", "ja"):
            for key, value in values.items():
                if looks_italian(value):
                    fail(path, 1, f"{lang}: still Italian: {key!r} = {value!r}")

# 3. Texts that skip tr() ------------------------------------------------------
# Files that run where tr() isn't compiled in (widgets, intents): their texts
# must be keys of a Localizable.strings that the target bundles.
localizable = {}
for (folder, name), by_lang in string_tables.items():
    if name == "Localizable.strings" and "it" in by_lang:
        localizable.update(by_lang["it"][1])
shortcut_phrases = {}
for (folder, name), by_lang in string_tables.items():
    if name == "AppShortcuts.strings" and "it" in by_lang:
        shortcut_phrases.update(by_lang["it"][1])

ui_call = re.compile(
    r"\b(Text|Label|Button|Section|Toggle|Picker|TextField|Stepper|Link|Menu|LabeledContent|"
    r"ContentUnavailableView|navigationTitle|alert|confirmationDialog|accessibilityLabel|"
    r"accessibilityHint|help|displayName|description|IntentDescription|shortTitle)\(\s*" + STR
)
resource_assign = re.compile(r"(?:LocalizedStringResource|shortTitle:)\s*=?\s*" + STR)
phrase_re = re.compile(r"phrases:\s*\[(.*?)\]", re.S)

for path in swift_files:
    if path == l10n_path:
        continue
    src = path.read_text(encoding="utf-8")
    uses_strings_file = "AppIntent" in src or "ControlWidget" in src or "AppShortcutsProvider" in src
    hits = [(m.start(), m.group(1 + (m.re is ui_call))) for m in ui_call.finditer(src)]
    hits += [(m.start(), m.group(1)) for m in resource_assign.finditer(src)]
    for pos, raw in hits:
        text = unescape(raw)
        if not needs_translation(text):
            continue
        if uses_strings_file:
            if text not in localizable:
                fail(path, line_of(src, pos), f"not in Localizable.strings, so it stays Italian in en/ja: {text!r}")
        else:
            fail(path, line_of(src, pos), f"shown without tr(), so it stays Italian in en/ja: {text!r}")
    for block in phrase_re.finditer(src):
        for m in re.finditer(STR, block.group(1)):
            phrase = unescape(m.group(1)).replace("\\(.applicationName)", "${applicationName}")
            if phrase not in shortcut_phrases:
                fail(path, line_of(src, block.start()), f"Siri phrase missing from AppShortcuts.strings: {phrase!r}")

# Info.plist permission texts: written in Italian in project.yml.
project = (ROOT / "project.yml").read_text(encoding="utf-8")
infoplist = {}
for (folder, name), by_lang in string_tables.items():
    if name == "InfoPlist.strings":
        for lang, (_, values) in by_lang.items():
            infoplist.setdefault(lang, {}).update(values)
for m in re.finditer(r"^\s*(NS\w+UsageDescription):", project, re.M):
    for lang in ("en", "ja"):
        if m.group(1) not in infoplist.get(lang, {}):
            fail(ROOT / "project.yml", line_of(project, m.start()), f"{m.group(1)} has no {lang} InfoPlist.strings translation")

if errors:
    print("Italian would show up in the English or Japanese app:\n")
    print("\n".join(errors))
    print(f"\n{len(errors)} problem(s).")
    sys.exit(1)
print(f"Translations OK: {len(table)} app texts, {sum(len(b) for b in string_tables.values())} .strings files.")
