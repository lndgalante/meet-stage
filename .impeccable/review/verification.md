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

## Dock-height controller

The controller is now 336 × 88 logical points, with 74 × 40 previews, the existing
11-point identities/shortcuts, and a 20-point footer/drag surface. The first native
inspection showed that a 360-point width did not leave sufficient space beside
the laptop Dock; the final width preserves all four slots within that gap.

Dock placement prefers the right gap, then the left, and shares the detected
Dock frame's vertical center. If neither gap fits, the Dock is hidden or on a
side, or its bounds are unavailable, placement stays within the visible desktop.
Recent macOS versions expose a full-screen Dock window, so the app reads the
Dock's AX list when already trusted and otherwise tries window-server bounds.
It never asks for new permission to position the controller.

A batched native inspection confirmed idle, live, paused, empty-slot, and keyboard
focus states, plus the Control–Command–D placement command. The window server
reported 336 × 88 at Quartz (1374, 1019) on the 1728 × 1117 display, placing the
controller in the right Dock gap. Native close/relaunch returned to idle and
restored the same position. No screen appearance or privacy preferences changed.
Light appearance and alternate accessibility settings were not visually retested;
their existing semantic fonts, colors and environment handling are unchanged.

All 213 tests in 35 suites pass with warnings as errors, including new coverage
for Dock gap centering, smaller and wider Docks, side/hidden/unavailable Docks,
negative display coordinates, offscreen saved positions, and native saved frames.
Strict Swift format lint, localization plist validation, package signature checks,
and diff whitespace checks pass. The final debug app is built and running.

## Native glass and magnetic Dock attachment

The controller retains 336 × 88 bounds and now uses native clear Liquid Glass,
28-point continuous corners, and its system-rendered edge. Horizontal insets are
16 points, column gaps remain 8, and previews are 70 × 40. Reduce Transparency
uses a solid system background; Increase Contrast adds a semantic inset edge.
No additional decorative border or sampled tint sits over the native glass.

Real CUA footer drags verified detachment and capture: a drag moved the widget
from Quartz (1368, 1019) to (1358, 879); moving it back near the Dock snapped it
to (1368, 1019). The saved attachment was right, with a 12-point gap from the
Dock's detected frame. Relaunch restored that attachment. The user can hold
Option to bypass snapping; a tooltip on the native footer explains it.

The capture radius is 24 points and the release radius is 44 points. While
attached and visible, the widget checks the Dock every 500 ms and follows when
a valid target fits. Dragging uses the targets captured at pickup, with no AX
queries during pointer movement. Snap coordinates use whole points because
AppKit rounds native window origins; this avoids repeated tracking updates.

All 221 tests in 36 suites pass with warnings as errors. New coverage includes
both Dock ends, capture/release behavior, distant drags, unavailable targets,
negative display coordinates, Option bypass, saved attachment restoration, and
native mouse down/drag/up routing with snap and pull-away behavior. Strict Swift
format lint, localization plist validation, package signature checks, and diff
whitespace checks pass. Real Dock resizing and alternate OS appearance settings
were not changed for verification. The final debug app is running idle, attached.

Native clear glass is composited by the window server: isolated CUA window
captures omit that backdrop. Cropped desktop screenshots were used for the
material comparison, alongside native accessibility state for the controls.

## Free dragging and restored corners

Restored the requested 16-point panel radius. Dragging now uses a native pan
recognizer on the stable frame view, with priority over hosted source gestures.
It delays click delivery until the pan fails, preserving ordinary preview clicks.
The footer retains its native drag surface as a fallback. Background-window
moving is disabled so movement cannot bypass attachment handling.

Pickup cancels attachment tracking immediately. Every drag origin follows the
pointer unchanged; magnetic attachment is applied only on release within 24
points of a target. Option skips the drop snap. The 44-point resistance was
removed. Regression coverage now verifies movement before release and snapping
after release, as well as the existing free movement and Option bypass checks.

Real CUA pointer drags without modifiers were verified from a preview, an app
label, and the footer. The native origin moved from (1368, 10) to (1338, 130),
then (1298, 180), then (1298, 200), matching the requested pointer deltas. The
attachment preference cleared. Dropping beside the Dock restored (1368, 10)
and the right attachment. Coordinate-based preview clicks still paused and
resumed Warp; drags did not select a source. A cropped desktop screenshot
confirmed the smaller corners. The controller was returned to idle afterward.

All 221 tests in 36 suites pass with warnings as errors. Strict Swift format
lint, localization validation, package signature checks, and diff whitespace
checks pass. The rebuilt app is running with the fix.

## Initial drag and preview cleanup

Native hit testing reproduced refusal of the first mouse-down at four locations
inside the inactive controller: its edge, an empty label, and preview areas.
Adding `allowsWindowActivationEvents()` plus full panel and source-rail hit areas
resolved every failure. The regression also covers the native footer. This follows
[Apple's window activation guidance](https://developer.apple.com/documentation/SwiftUI/Customizing-window-styles-and-state-restoration-behavior-in-macOS).

Real pointer drags covered a source preview, source label, empty preview, empty
label, panel edge, and between-tile gap without Option. In the rebuilt app, an
empty-label drag detached from AppKit (1368, 10) to (1288, 110). A source-preview
drop at (1383, 20) snapped to (1368, 10), persisting right-side attachment.
Ordinary coordinate clicks selected and paused Warp; drags did not select it.
Snapping was retained after passing these checks.

The desktop crop `/tmp/meet-stage-widget-cleanup.png` confirms the empty-slot
window icon and keyboard-focus inset dashed edge are gone. The paused state
retains its orange outline, pause symbol, Return cue, and status text.

All 222 tests in 36 suites pass with warnings treated as errors. Strict Swift
format lint and `git diff --check` pass. The debug app was rebuilt and relaunched,
and verification capture was stopped with the controller left idle beside the Dock.
