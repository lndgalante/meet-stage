# BetterMeets testing guide

BetterMeets keeps deterministic decisions in plain Swift and treats macOS
framework integration as an edge. Tests should follow the same boundary: cover
policies, geometry, persistence, state transitions, and AppKit configuration in
automation; verify privacy prompts and live window-server behavior with the
packaged app.

## Test layers

| Layer | Examples | Expected coverage |
| --- | --- | --- |
| Pure policy and geometry | shortcut reconciliation, capture selection and frame generations, window eligibility, auto-zoom camera and styled-frame transforms, normalized coordinates, stage sizing and workspace fitting | Every branch and boundary value |
| Persistence | presentation settings, shortcut pins and exclusions, corrupt or legacy data | Defaults, round trips, normalization, and invalid input |
| Main-actor models | annotation fading, spotlight state, armed presentation effects | State changes and cancellation-sensitive behavior |
| AppKit integration | overlay window levels, event-monitor ownership, native workspace configuration, workspace notifications | Configuration and callback translation that can run without privacy consent |
| Live macOS integration | ScreenCaptureKit, global mouse monitoring, Accessibility permission, Carbon hotkeys, meeting-app window capture | Manual packaged-app verification |

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
same App Intents, resources, entitlements, and signing boundaries.

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
   opening a system dialog. The sidebar's Allow Access button requests access.
   Verify access can be granted and recovered by restarting the packaged app.
   With an Apple Development certificate, rebuild twice and confirm access
   persists. Packaging a release must leave the running debug bundle unchanged.
2. Selecting, switching, pausing, and resuming windows never publishes a source
   as live before its first complete frame.
3. Closing, minimizing, hiding, restoring, and renaming a source preserves the
   documented shortcut behavior.
4. Slots 1 through 9 use the modifier selected in Settings and report conflicts
   without changing capture state. Disabled must unregister every global slot.
5. The workspace remains draggable and resizable, preserves the selected
   source aspect ratio within the stage, and is capturable by the target meeting app.
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
9. In Settings → Stage, verify each backdrop and logo selection update the stage. The
   source stays aspect-correct and never reveals empty video while zoomed.
10. Turn on Reduce Motion and confirm zoom is restrained, cursor travel does not
    animate, and all controls remain usable. Spotlight and Draw cancel the
    current auto zoom and continue to take input precedence.
11. The main window contains six tools, a vertical source selector, the stage,
    and a bottom status strip. The compact feature widget follows the selected
    source, with six icons and no voice control. Check source selection, thumbnails, unavailable pins,
    hover/Space previews, context menus, Up/Down/Return, and Option–number shortcuts.
12. Toggle Stage Only from View or Control–Command–S. Confirm the sidebar, status
    strip, and toolbar disappear while capture continues. Escape and the same
    shortcut restore controls. Share BetterMeets in a meeting app and confirm
    that visible workspace controls appear only when the workspace is shown.
    The separate feature widget stays available beside the source in Stage Only.
    Move and resize the source, including near screen edges and on another display.
    Check right/left gutter placement, onscreen fallback, source switching, settings,
    and hiding when the source closes or an unrelated app becomes frontmost.
13. Resize to the minimum and maximize/full-screen the workspace. Switch between
    landscape and portrait sources: content must fit without stretching or
    cropping, and the workspace must not resize. Close/reopen and relaunch to
    verify size and position restoration.
14. Settings has General, Stage, Focus, Draw, Clicks, and Keys. The gear anchors
    its popover; Escape/outside-click dismisses it. Verify no Voice tab, model
    selector, API-key input, or microphone prompt remains. Existing settings
    saved to the removed tab should fall back to General.
15. Check Light and Dark appearances, Reduce Transparency, Increase Contrast,
    Reduce Motion, keyboard focus, and VoiceOver labels. The six tool rows and
    source list must remain readable and reachable at minimum window size.

Record the macOS version and meeting app when a manual result depends on
window-server or capture-framework behavior.
