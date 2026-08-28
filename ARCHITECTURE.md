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
- `WindowCoordinateGeometry` is the canonical coordinate-conversion boundary
  for every presentation effect. `SourceOverlayGeometry` and
  `SourceOverlayFrameTracker` own Quartz-to-AppKit conversion and live overlay
  alignment; effect-specific modules must not reach through one another for
  window geometry.
- `GlobalLocalEventMonitor` owns the paired AppKit monitor lifecycle used by
  pointer-based effects. Domain-specific initializers copy `NSEvent` data into
  Sendable click or pointer values before returning to the main actor. Pointer
  bursts are latest-value coalesced to display cadence, and `CaptureManager`
  shares one pointer monitor between Auto Polish and Spotlight.
- `GlobalHotKeyManager` owns Carbon resources and reports registration failures
  instead of changing capture state itself.
- `SampleBufferRenderer` is the only cross-thread rendering bridge. Its lock
  protects renderer state; `StageVideoView` performs layer work on the main
  queue. Capture dimensions retain smaller sources and cap the longest edge at
  2560 pixels so 4K/5K windows do not consume bandwidth the shared stage cannot
  usefully expose.
- `WorkspaceMonitor` translates AppKit lifecycle notifications into focus and
  source-list events while `WorkspaceObservationBag` owns the notification
  tokens.
- `AnnotationSession` owns normalized temporary ink shared by the selected
  source overlay and `StageView`. `AnnotationShapeRecognizer` is the pure,
  pixel-space policy that conservatively turns closed strokes into semantic
  circles or rectangles at pointer-up. `CaptureManager` owns annotation
  lifecycle, persistence, and source-switch cleanup. Annotation intent is
  independent from the active overlay so it can remain armed through idle,
  paused, switching, and source-focus changes. The source overlay is
  non-activating and only exists while the selected source app is frontmost,
  preventing drawing mode from changing BetterMeets' window order or
  intercepting another app.
- `ClickHighlights`, `KeystrokeHighlights`, and `SpotlightEffect` each own one
  presentation effect from domain value through platform monitor or overlay and
  SwiftUI rendering. `ControlSettingsPreviews` owns preview-only rendering; it
  does not mutate preferences directly.
- `PresentationPreferences` defines the typed appearance choices shared by
  settings, source overlays, and the Demo Stage. `CaptureManager` persists the
  selected values and snapshots them into each click or keystroke presentation.
- `AutoPresentationSession` owns transient pointer and camera state.
  `AutoZoomCameraPolicy` starts from explicit clicks and uses a normalized safe
  zone so routine pointer movement does not make the camera chase the presenter.
  `CaptureManager+AutoPresentation` owns the global read-only mouse monitors,
  source-coordinate mapping, capture-cursor visibility, and preference updates.
  It must never synthesize source pointer, click, or keyboard input; its
  monitors are strictly observational. Manual spotlight and annotation tools
  cancel any automatic zoom. Demo Mode is the one subsystem allowed to actuate
  the source app, and it does so through its own charter (below), never through
  this extension.
- Demo Mode (`CaptureManager+DemoMode`, `DemoModeSession`, and the `Demo*`
  modules) is the deliberate, separately chartered exception to the
  no-synthesized-input rule: while it is armed and the selected source is
  focused, it transcribes the presenter's narration on device
  (`DemoSpeechTranscriber`, macOS Speech framework), matches spoken control
  names against an index of the source window's controls, and either highlights
  a control or clicks it. The decision layer is pure and testable —
  `DemoText`/`DemoLabelMatcher` (tokenizing and fuzzy matching),
  `DemoIntentPolicy` (verb-versus-reference classification and the contextual
  cue gate that prevents incidental mentions from firing), and `DemoCommandGate`
  (per-target debounce). The platform edges are isolated: `DemoSpeechListening`
  (live transcription), `AccessibilityElementIndexer` (bounded off-main AX-tree
  walk, with the Chromium/Electron enhancement attributes), `DemoTextRecognizer`
  (Vision text recognition over an on-demand captured frame as a fallback for
  sparse AX trees), and `DemoActionExecutor` (the *only* place BetterMeets posts
  synthesized events — a visible cursor glide plus click, gated on Accessibility
  trust). Highlights dual-render like every other effect (source overlay plus
  Demo Stage); the caption HUD renders only on the presenter's non-captured
  overlay. Clicking is opt-out via the `Highlight only` voice-actions setting.
  Actuation requires Accessibility trust; the microphone is a hard requirement
  re-gated against live authorization at launch, exactly like keystroke
  highlighting.
- `StageFrameLayout` preserves the source aspect ratio inside configurable
  padding. `StageFrameBackdrop` and `StageView` own the visual composition:
  backdrop, blur, rounded source surface, layered shadow, auto-zoom transform,
  and a hotspot-correct 3× mirror of the active macOS system cursor. These
  effects exist only in the Demo Stage and never modify the selected source
  window.
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
compatibility, presentation and annotation policies, auto-zoom and frame
geometry, and AppKit window interaction. ScreenCaptureKit streams, mouse event
monitoring, Carbon hotkeys, permission prompts, and end-to-end window-server
behavior require the packaged app and are
verified manually with the checklist in `README.md`.

See [TESTING.md](TESTING.md) for the test-layer map, contributor conventions,
and the manual verification matrix for platform-only behavior.

`.github/workflows/ci.yml` enforces strict Swift formatting, validates metadata
and shell syntax, runs the complete test suite with warnings as errors, and
compiles an optimized build on every push and pull request.

The `build-app.sh` and `dev-app.sh` entry points share
`scripts/build-and-package.sh`. The helper derives the signing identifier from
`Resources/Info.plist`; keep that metadata stable so macOS preserves Screen
Recording consent. Local builds use a stable ad-hoc designated requirement.
Developer ID builds enable the hardened runtime and trusted timestamp, then
`scripts/notarize-app.sh` performs submission, stapling, and Gatekeeper checks.
