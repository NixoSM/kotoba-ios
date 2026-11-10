# screen-check

Kotoba is written without a Mac. The only compiler that knows SwiftUI runs on
GitHub's Mac machines, where a minute costs ten times a Linux one, so a typo in
a screen used to cost a whole Mac build to find.

This folder lets the Swift compiler on Linux read the screens first:

    tools/screen-check/run.sh

It compiles the screens listed in `run.sh`, together with the logic they use,
against **stand-ins** for SwiftUI, UIKit, Photos and UniformTypeIdentifiers:
declarations with the same names and shapes as the real ones and no behaviour.

What it catches: everything a compiler catches in our own code. A misspelt
property, a wrong argument, a missing `case`, an optional not unwrapped, a
closure of the wrong type.

What it does not: anything about SwiftUI itself. If the real SwiftUI has no
such function, or behaves differently from what we assumed, only the Mac build
(and then the phone) will tell. Passing here is necessary, not sufficient.

## When it fails

- The error is in our code: fix it. The Mac would have said the same, later.
- The error says SwiftUI has no member something, and you know the real one
  does: add the declaration to `Sources/SwiftUI/SwiftUI.swift`, copying the
  real signature from Apple's documentation. Keep it as strict as the real one;
  a stand-in that accepts anything catches nothing.

## Adding a screen

Add its file to the list in `run.sh`. If it uses something from a file that
cannot be compiled on Linux (camera, web view, audio), declare just that in
`Sources/Screens/Stubs.swift`.

Not checked today: the camera screens, the web view, the audio player, the
texthooker tab, the share extension and `KotobaApp.swift`.
