# BetterMeets architecture

BetterMeets deliberately keeps platform integration at the edges and moves
deterministic policy into plain Swift values. This makes capture behavior easy
to follow while keeping the parts that do not require macOS services testable.

## Ownership boundaries

- `MeetStageApp`, `ControlView`, and `StageView` own SwiftUI composition only.
  AppKit window mutations live in `WindowConfigurator`.
- `CaptureManager` is the main-actor coordinator. Its root file owns observable
  state and dependencies; responsibility-focused extensions own discovery,
  commands, lifecycle, presentation integration, and stream callbacks. The
  coordinator remains internal to the executable target.
- `WindowSourceDiscovery` owns ScreenCaptureKit enumeration and thumbnails.
  `WindowDiscoveryPolicy` contains the platform-independent picker eligibility
  rules and is tested without requiring screen-recording permission.
- `ShortcutAssignmentPolicy` is a pure reconciliation function. It knows
  nothing about ScreenCaptureKit, UserDefaults, SwiftUI, or Carbon.
- `ShortcutPreferencesStore` is the persistence boundary. Its legacy keys and
  Codable property names are compatibility contracts.
- `PresentationPreferencesStore` is the typed persistence boundary for drawing,
  click, and keystroke settings. Views and capture orchestration must not read
  or write its raw `UserDefaults` keys directly.
- `GlobalHotKeyManager` owns Carbon resources and reports registration failures
  instead of changing capture state itself.
- `SampleBufferRenderer` is the only cross-thread rendering bridge. Its lock
  protects renderer state; `StageVideoView` performs layer work on the main
  queue.
- `WorkspaceMonitor` translates AppKit lifecycle notifications into focus and
  source-list events while `WorkspaceObservationBag` owns the notification
  tokens.
- `AnnotationSession` owns normalized temporary ink shared by the selected
  source overlay and `StageView`. `CaptureManager` owns annotation lifecycle,
  persistence, and source-switch cleanup. Annotation intent is independent from
  the active overlay so it can remain armed through idle, paused, switching, and
  source-focus changes. The source overlay is non-activating and only exists while
  the selected source app is frontmost, preventing drawing mode from changing
  BetterMeets' window order or intercepting another app.
- `PresentationPreferences` defines the typed appearance choices shared by
  settings, source overlays, and the Demo Stage. `CaptureManager` persists the
  selected values and snapshots them into each click or keystroke presentation.
- `AppLog` owns unified-log categories. Recoverable background failures are
  logged with privacy annotations; user-actionable capture failures also move
  `CaptureState` to `.failed` so the Demo Stage explains what happened.

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

`swift test` exercises source eligibility, shortcut reconciliation, preference
compatibility, presentation and annotation policies, geometry calculations,
and AppKit window interaction. ScreenCaptureKit streams, Carbon hotkeys,
permission prompts, and end-to-end window-server behavior require the packaged
app and are verified manually with the checklist in `README.md`.

`.github/workflows/ci.yml` enforces strict Swift formatting, validates metadata
and shell syntax, runs the complete test suite with warnings as errors, and
compiles an optimized build on every push and pull request.

The `build-app.sh` and `dev-app.sh` entry points share
`scripts/build-and-package.sh`. The helper derives the signing identifier from
`Resources/Info.plist`; keep that metadata stable so macOS preserves Screen
Recording consent. Local builds use a stable ad-hoc designated requirement.
Developer ID builds enable the hardened runtime and trusted timestamp, then
`scripts/notarize-app.sh` performs submission, stapling, and Gatekeeper checks.
