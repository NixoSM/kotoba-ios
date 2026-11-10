#!/usr/bin/env bash
# Type-checks the app's screens on Linux. See README.md in this folder.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../App"

# The files checked: the logic the screens use, then the screens themselves.
# A screen that needs the camera, the web view or the audio player cannot be
# checked here; what the others use from it is in Sources/Screens/Stubs.swift.
files=(
  LogicSupport/LinuxStandIns.swift
  Sources/AppModel.swift
  Sources/AppSettings.swift
  Sources/Appearance.swift
  Sources/Diagnostics.swift
  Sources/HeadwordGroup.swift
  Sources/L10n.swift
  Sources/MediaLink.swift
  Sources/PickedFile.swift
  Sources/Reason+Italian.swift
  Sources/ResultsPage.swift
  Sources/SearchResults.swift
  Sources/WordIndex.swift
  Sources/AnkiSettingsView.swift
  Sources/DiagnosticsView.swift
  Sources/DictionariesView.swift
  Sources/ResultsPane.swift
  Sources/SearchView.swift
  Sources/SettingsView.swift
  Sources/WordsView.swift
)

links="$here/Sources/Screens"
find "$links" -type l -delete
for file in "${files[@]}"; do
  [ -f "$app/$file" ] || { echo "screen-check: $file is listed in run.sh but does not exist" >&2; exit 1; }
  ln -s "$app/$file" "$links/$(basename "$file")"
done

log="$here/.build.log"
if swift build --package-path "$here" > "$log" 2>&1; then
  echo "screen-check: ${#files[@]} files compile."
else
  # Each error once, then the compiler's own words for the detail.
  grep -E "error:" "$log" | sort -u || true
  echo "----"
  tail -n 60 "$log"
  echo
  echo "screen-check: the screens do not compile against the stand-ins."
  echo "If the error is in our code, fix it: the Mac would have said the same."
  echo "If it names a SwiftUI feature the stand-ins lack, add it to"
  echo "tools/screen-check/Sources/SwiftUI/SwiftUI.swift, with the real signature."
  exit 1
fi
