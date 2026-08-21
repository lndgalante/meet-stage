# BetterDemos architecture

BetterDemos deliberately keeps platform integration at the edges and moves
deterministic policy into plain Swift values. This makes capture behavior easy
to follow while keeping the parts that do not require macOS services testable.

## Ownership boundaries

- `MeetStageApp`, `ControlView`, and `StageView` own SwiftUI composition only.
  AppKit window mutations live in `WindowConfigurator`.
- `CaptureManager` is the main-actor coordinator. It owns observable state,
  source discovery, capture tasks, cursor policy, and the active `SCStream`.
- `ShortcutAssignmentPolicy` is a pure reconciliation function. It knows
  nothing about ScreenCaptureKit, UserDefaults, SwiftUI, or Carbon.
- `ShortcutPreferencesStore` is the persistence boundary. Its legacy keys and
  Codable property names are compatibility contracts.
- `GlobalHotKeyManager` owns Carbon resources and reports registration failures
  instead of changing capture state itself.
- `SampleBufferRenderer` is the only cross-thread rendering bridge. Its lock
  protects renderer state; `StageVideoView` performs layer work on the main
  queue.
- `AnnotationSession` owns normalized temporary ink shared by the selected
  source overlay and `StageView`. `CaptureManager` owns annotation lifecycle,
  persistence, and source-switch cleanup. Annotation intent is independent from
  the active overlay so it can remain armed through idle, paused, switching, and
  source-focus changes. The source overlay is non-activating and only exists while
  the selected source app is frontmost, preventing drawing mode from changing
  BetterDemos' window order or intercepting another app.
- `PresentationPreferences` defines the typed appearance choices shared by
  settings, source overlays, and the Demo Stage. `CaptureManager` persists the
  selected values and snapshots them into each click or keystroke presentation.

## Capture lifecycle

The user-visible state follows this flow:

```text
idle -> switching -> capturing
  |         ^            |
  |         |            v
  |         +--------- paused
  +------> failed <------+
  |
  +------> permissionRequired
```

Selecting a source does not mark it live. `CaptureManager` waits for a complete
ScreenCaptureKit frame before publishing the new selected window. Selection and
render generations reject stale asynchronous work after a stop or rapid source
change. Repeating the current selection while capturing pauses it without
discarding the selected window; repeating it while paused re-enters `switching`
and waits for a fresh first frame. Keep this first-frame invariant when changing
capture orchestration.

## Shortcut invariants

- Only Option+1 through Option+9 are supported.
- A saved pin reserves its slot even when its window is unavailable.
- An ambiguous saved identity never guesses between matching windows.
- Automatic assignments remain stable while their windows stay eligible.
- Explicitly excluded identities are not automatically reassigned.
- A resolved pin follows the same window ID if its title changes, then persists
  the refreshed identity.

Change these rules in `ShortcutAssignmentPolicy` and update its tests in the
same commit. Do not spread shortcut branches through `CaptureManager` or views.

## Verification strategy

`swift test` exercises pure shortcut reconciliation, preference compatibility,
and geometry calculations. ScreenCaptureKit streams, Carbon hotkeys, permission
prompts, and window-server behavior require the packaged app and are verified
manually with the checklist in `README.md`.

The `build-app.sh` and `dev-app.sh` entry points share
`scripts/build-and-package.sh`. The helper derives the signing identifier from
`Resources/Info.plist`; keep that metadata stable so macOS preserves Screen
Recording consent.
