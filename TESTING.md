# BetterMeets testing guide

BetterMeets keeps deterministic decisions in plain Swift and treats macOS
framework integration as an edge. Tests should follow the same boundary: cover
policies, geometry, persistence, state transitions, and AppKit configuration in
automation; verify privacy prompts and live window-server behavior with the
packaged app.

## Test layers

| Layer | Examples | Expected coverage |
| --- | --- | --- |
| Pure policy and geometry | shortcut reconciliation, capture selection and frame generations, exact-window focus, window eligibility, auto-zoom camera and styled-frame transforms, normalized coordinates, stage sizing, Demo Mode text matching, intent classification, command debounce, cloud authorization, and reply parsing | Every branch and boundary value |
| Persistence | presentation settings, shortcut pins and exclusions, corrupt or legacy data | Defaults, round trips, normalization, and invalid input |
| Main-actor models | annotation fading, spotlight state, armed presentation effects | State changes and cancellation-sensitive behavior |
| AppKit integration | overlay window levels, event-monitor ownership, drag surfaces, workspace notifications | Configuration and callback translation that can run without privacy consent |
| Live macOS integration | ScreenCaptureKit, global mouse monitoring, Accessibility permission, Carbon hotkeys, meeting-app window capture, microphone transcription (SpeechAnalyzer), AX-tree indexing, Vision text recognition, synthesized clicks | Manual packaged-app verification |

## Required local checks

Run these before handing off a change:

```bash
swift format lint --strict --recursive Sources Tests Package.swift scripts/generate-app-icon.swift
swift test --enable-code-coverage -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
plutil -lint Resources/Info.plist
zsh -n build-app.sh dev-app.sh scripts/build-and-package.sh scripts/generate-appcast.sh scripts/notarize-app.sh
./build-app.sh
git diff --check
```

CI packages the app on every change. Local runs of `./build-app.sh` verify the
same Metal, App Intents, resources, entitlements, and signing boundaries.

## Writing maintainable tests

- Prefer Swift Testing suites named for behavior, with test names that describe
  the user-visible invariant rather than the implementation method.
- Put new decision logic in a plain value or policy and test it without
  ScreenCaptureKit, `UserDefaults.standard`, or a live workspace whenever
  possible.
- Use a unique `UserDefaults` suite and remove its persistent domain in cleanup.
- Keep UI and AppKit tests on `@MainActor`; do not hide actor crossings behind
  `@unchecked Sendable` test helpers unless a lock protects all shared state.
- Test both sides of coordinate boundaries. Window effects deliberately accept
  their maximum X/Y edges, while annotation drags clamp pointer overshoot.
- When fixing a bug, add the smallest regression test that fails for the old
  behavior and names the invariant that was violated.

## Manual platform matrix

After changing capture lifecycle, source discovery, presentation monitoring,
window configuration, or permissions, build the packaged debug app with
`./dev-app.sh` and verify:

1. Launching without Screen Recording permission shows inline guidance without
   opening a system dialog. The controller's permission button requests access.
   Verify access can be granted and recovered by restarting the packaged app.
   With an Apple Development certificate, rebuild twice and confirm access
   persists. Packaging a release must leave the running debug bundle unchanged.
2. Selecting, switching, pausing, and resuming windows never publishes a source
   as live before its first complete frame.
3. Closing, minimizing, hiding, restoring, and renaming a source preserves the
   documented shortcut behavior.
4. Slots 1 through 9 use the modifier selected in Settings and report conflicts
   without changing capture state. Disabled must unregister every global slot.
5. The Demo Stage remains draggable and resizable, preserves the selected
   source aspect ratio, and is capturable by the target meeting app.
6. Pointer capture, click ripples, spotlight, annotations, and keystrokes appear
   only for the focused selected source and clean up after switching or stopping.
7. Accessibility and Reduce Motion settings produce the documented fallback
   behavior.
8. With Auto Polish enabled, clicking the focused source starts a zoom
   immediately around the click. Small pointer movements leave the camera still;
   moving outside the safe zone recenters it smoothly. After roughly two seconds
   without another click, the stage returns to 1×. The Demo Stage mirrors the
   currently visible macOS cursor at exactly 2× with the same hotspot, while the
   real source pointer is never moved or blocked.
9. In Settings → Stage, verify each backdrop and the padding, corner, blur,
   shadow and zoom-strength controls update the Demo Stage. The
   source stays aspect-correct and never reveals empty video while zoomed.
10. Turn on Reduce Motion and confirm zoom is restrained, cursor travel does not
    animate, and all controls remain usable. Spotlight and Draw cancel the
    current auto zoom and continue to take input precedence.
11. Enable Demo Mode. Confirm the Voice introduction appears once, before any
    listening or cloud request. “Not Now” must leave Voice off; “Continue” must
    remember the introduction across launches. Confirm the microphone prompt
    appears when access has not yet been granted and
    that a revoked microphone permission re-disables the toggle at next launch.
    With a live, focused source, naming a visible control ("the Receive button")
    highlights it on the Demo Stage and zooms to it, and the presenter-only
    caption never appears in the shared capture. Confirm listening continues
    while BetterMeets is focused but no command fires unless the source is
    frontmost, and that everything tears down on stop, pause, and source switch.
12. With Accessibility granted, saying "click <control>" glides the pointer to
    the control and opens it; naming the control without an action verb must
    only highlight it. With Accessibility
    declined, confirm Demo Mode still highlights text-recognized controls but does
    not click. Verify a Chromium/Electron app's web controls become targetable
    (the accessibility enhancement plus text-recognition fallback), and that
    repeating the same phrase does not double-fire within the debounce window.
13. After the Voice introduction, add a model API key and confirm cloud
    understanding works automatically. Start a command and immediately remove
    the key, change provider, focus another app, and switch source in separate
    runs. Confirm the old request never applies an action. Switching providers
    must use only the selected provider's key, without another introduction.
    Verify on-device commands still work when the selected model has no key.
14. With Cloud understanding and input actuation enabled, confirm “show the
    Search field” only highlights it, “type hello in Search” enters exactly
    “hello,” and negated or screen-authored instructions never type. Move focus
    to another field during a longer command and confirm entry stops before the
    next character.
15. Select one of two windows from the same app, bring the sibling window to the
    front, and issue click and type commands. Confirm neither command actuates
    until the selected window itself is focused. Repeat with two maximized
    same-frame windows and confirm the ambiguous match fails closed.
16. Select a source with Option–1 through Option–9. Verify the controller shows
    only the carousel and guidance, including the paused and empty states.
    Resize and move the source: the vertical actions should use the right
    gutter, then the left gutter, or sit inside when neither fits, centered
    vertically and kept on screen. Check a second display, full screen,
    minimizing, switching apps, stopping capture, and keyboard access through
    Window → Show Stage Actions. Share only Demo Stage in Google Meet and
    confirm the controls stay absent with both inside and outside placement.
17. Open the action menu's gear and confirm Settings appears to its left with
    an arrow pointing to the gear. The card border must stop beneath the tab
    strip in both active and inactive windows. Verify General has only the
    shortcut toggle and modifier selector, and Voice only the model and API key.
    Turn shortcuts off and back on, including across a restart, and confirm the
    modifier choice returns. Verify the key preview and that Focus contains only
    spotlight size and outside opacity. Check all tabs, Escape/outside-click
    dismissal, logo import,
    and focus while interacting with the popover. The settings popover must
    also stay absent from the shared Demo Stage.

Record the macOS version and meeting app when a manual result depends on
window-server or capture-framework behavior.


## Source widget regression check

The source controller is a borderless native window. Its full content and window
frame must both measure 360 × 128 points, with no padding for a painted shadow.
The window server supplies the shadow outside those bounds. Verify Tab/arrows and
Return, Option–number source selection, live/pause cues, pin and hover menus,
Command-W, Command-M, Command-Control-C restore, and dragging from the footer.
Tests cover key/main eligibility, Close/Minimize validation, exact bounds, native
footer hit testing, and 1:1 pointer movement. A window screenshot should include
only the visible widget and must have no detached title-bar line.
