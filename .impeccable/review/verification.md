# Native widget verification

Approved comp: ../mocks/widget-a-balanced.png. User explicitly selected A.
Sources are real windows discovered on the user's Mac, not staged demo data.

The running debug app was inspected with CUA. Saved snapshots: widget-idle.png,
widget-live.png, widget-paused.png. These show native macOS at its actual utility
scale (424 × 164 logical points), including keyboard focus in live/paused states.
Google Chrome disappeared during discovery between captures; the empty slot is
real state, not a content omission. No mobile target exists. Light appearance and
accessibility fallbacks are implemented using system environments; those alternate
OS environments have not been changed on the user's machine for screenshots.

Verified: click selection, Return activation, Tab and arrow focus, pause/resume,
context menu with slots 1–9 and unpin, Command-comma Settings, Command-W close,
Command-M minimize, and restore using Command-Control-C. No detached line or
transparent shadow padding appears in the exact-size window capture.

Tests: 201 pass in 34 suites, including native window bounds, key/main eligibility,
and Close/Minimize menu validation and close/reopen. Source models, global hotkey
handling, preview hover delay, pin assignment, and capture isolation are preserved.
The background is native regular material with a neutral tint, not a bitmap.

Quality bar: the approved A comp and existing native macOS surfaces in DESIGN.md;
no catalog visual world was chosen. The surface seed was 324e2ed7 (candidate 6),
run before compositional mocks. No web detector findings: this is SwiftUI/AppKit.

## Final correction and verdict

The finish reviewer found one fidelity issue: A's selected shortcut badge needed
an accent fill. Fixed; conflict red takes precedence, and paused/pending use orange.
Final screenshots: widget-live-final.png and widget-paused-final.png.
Reviewer verdict: resolved, with no introduced visual regressions. Visual review
is clear. Only Warp remained open in the final captures; source count is real.

The footer now hosts the tested native WindowDragView above the SwiftUI hosting
view, preserving its Settings/Minimize/Hide context menu. A new integration test
verifies the footer's native hit target, alongside the existing 1:1 movement test.
CUA verified the native footer context menu. A physical drag remains unverified:
CUA returned windowNotFoundAtPosition for in-bounds coordinates on the floating
window. A direct window-server query confirmed window 22103 is 424 × 164 at (1261, 755),
matching the complete visible surface. No external permission or OS preference
was changed for testing. The controller was left idle after verification.


## Compact C refinement

The user selected Compact C and requested a smaller desktop footprint. The
controller now measures 360 × 128 logical points (34% less area than A), with
8-point insets/gaps and 80 × 66 previews. App identities sit above previews,
shortcut keycaps sit at bottom right, and one centered status line replaces the
separate footer band. The native footer drag region remains 24 points high.
Long guidance falls back to the status title; help and VoiceOver retain its full
message. Labels and keycaps retain their previous font sizes.

One batched native inspection verified idle, live, paused, keyboard focus,
Option–2 selection, Tab/Right navigation, Return activation, and source pin/unpin
menus. Captures are widget-compact-idle.png, widget-compact-live.png,
widget-compact-paused.png, and widget-compact-keyboard.png. The window-server
query confirmed Width = 360 and Height = 128, exactly matching its screenshot.
No detached title-bar line or transparent layout margin appeared. No visual
correction was needed. The app was left idle after testing.

All 201 tests in 34 suites pass, including geometry and native footer hit testing.
Strict Swift format lint, warnings-as-errors release build, plist/shell checks,
and diff whitespace checks pass. This refinement leaves source state, capture,
permissions, settings, and Stage action behavior unchanged. Physical dragging and
alternate OS appearance checks retain the prior verification limits above.


## Footer alignment and live symbol

The compact widget retains its 360 × 128 bounds. Status now aligns left and
next-action guidance aligns right. The identity row uses play.fill for live and
pause.fill for paused, both centered in a 12-point-wide slot with the same
9-point semibold font. The accessible Live/Paused values remain unchanged.

A batched native review confirmed idle footer spacing, Option–3 selection,
play/pause alignment, and click-to-pause. Captures: widget-compact-footer-idle.png,
widget-compact-footer-live.png, and widget-compact-footer-paused.png. All 201 tests,
strict format lint, warnings-as-errors release build, plist and shell checks pass.
