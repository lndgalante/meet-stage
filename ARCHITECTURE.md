# BetterMeets architecture

BetterMeets deliberately keeps platform integration at the edges and moves
deterministic policy into plain Swift values. This makes capture behavior easy
to follow while keeping the parts that do not require macOS services testable.

## Ownership boundaries

- `MeetStageCore` is a framework-free SwiftPM target for capture-frame validation,
  exact-window focus checks, the real-time demo action policy, and bounded
  asynchronous work.
- `MeetStageApp` owns scenes and commands; the workspace window has a hidden
  title bar. `WorkspaceView` composes it: the full-height vertical `ControlView`
  rail, topped by a header-height row for the window buttons, then a column with
  the `StageHeader` card, `StageView`, and the `DemoBarView` panel, which shows
  only while `DemoSession.selectedSource` is set; the rail, the header, and the
  demo panel share the `workspacePanel()` treatment. `StageHeader` holds the app
  on stage, its state, and its window title on the leading edge, then the five
  effect toggles, Pause Stage, and Clear Stage. `BetterMeetsWindowState` shares
  Stage Only state with menus, Dock actions, and App Intents.
  `WindowConfigurator` applies AppKit-only window behavior once the hosting view
  joins a window; it never changes geometry on source updates. Its
  `WindowButtonsPlacement` moves AppKit's title bar view, narrowed to the close,
  minimize, and zoom buttons, into the rail's top row, and puts it back whenever
  AppKit lays the title bar out again (on resize, after full screen): right
  away, before the window draws, and again on the next run-loop turn, because
  AppKit ignores a move made during its own layout pass. It hides the buttons
  while full screen animates them. `WindowDragArea` stands in for the title bar
  behind the gutters, the header card, and the rail's top row, and over the
  source title: dragging moves the window, and a double-click zooms, fills,
  minimizes, or does nothing, as System Settings asks.
- `StageView` renders content without owning or creating windows. The workspace
  fits it into available space without cropping. Stage Only removes control
  surfaces and the window buttons; Escape restores them. Window resizing, full
  screen, and frame restoration remain available.
- `CaptureManager` is the main-actor coordinator. Its root file owns observable
  state and dependencies; responsibility-focused extensions own discovery,
  commands, lifecycle, presentation integration, and stream callbacks. The
  coordinator remains internal to the executable target.
- `WindowSourceDiscovery` owns ScreenCaptureKit enumeration and thumbnails.
  `WindowThumbnailLoader` is an injected service that keeps at most four
  screenshot requests in flight and returns results to the main-actor
  coordinator. `StageLogoStore` is a separate injected persistence service.
  `WindowDiscoveryPolicy` contains the platform-independent picker eligibility
  rules and is tested without requiring screen-recording permission.
- `ShortcutAssignmentPolicy` is a pure reconciliation function. It knows
  nothing about ScreenCaptureKit, UserDefaults, SwiftUI, or Carbon.
- `ShortcutPreferencesStore` is the persistence boundary. Its legacy keys and
  Codable property names are compatibility contracts.
- `PresentationPreferencesStore` is the typed persistence boundary for drawing,
  click, and keystroke settings. Views and capture orchestration must not read
  or write its raw `UserDefaults` keys directly. Large assets never live in
  defaults: legacy logo data migrates to a normalized Application Support file,
  leaving only a storage-version marker.
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
  protects renderer state; the display renderer consumes sample buffers directly
  on ScreenCaptureKit's serial callback queue, while `StageVideoView` receives
  only lightweight geometry and animation work on the main queue. Capture
  dimensions retain smaller sources and cap the longest edge at 2560 pixels so
  4K/5K windows do not consume bandwidth the shared stage cannot usefully expose.
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
  cancel any automatic zoom. Only `DemoDriver` acts on another app, through
  Accessibility actions and, as a fallback, `DemoInputSynthesizer`'s pointer,
  scroll, and keyboard events; manual presentation effects remain observational.
- `StageFrameLayout` preserves the source aspect ratio inside configurable
  padding. `StageFrameBackdrop` and `StageView` own the visual composition:
  backdrop, blur, rounded source surface, layered shadow, auto-zoom transform,
  and a hotspot-correct 2× mirror of the active macOS system cursor. These
  effects exist only in the Demo Stage and never modify the selected source
  window.
- `AppLog` owns unified-log categories. Recoverable background failures are
  logged with privacy annotations; user-actionable capture failures also move
  `CaptureState` to `.failed` so the Demo Stage explains what happened.

## Capture lifecycle

`WorkspaceView` also installs `StageActionsPresenter`, which owns an independent
nonactivating panel beside the selected source. `StageActionsPlacement` fits it
to the source's screen. The panel tracks moves and resizes, hides for unavailable
sources or any foreground app other than the source, including BetterMeets.
`StageActionsView` is its only layout: the demo button (once the app has a
demo), Pause Stage, then Auto Polish, Spotlight, Annotations, Click Highlights,
and Keystrokes, and a More menu holding Clear Stage, Show BetterMeets, and
Settings. The panel takes its content's fitting height as the demo button comes
and goes; `StageActionsMetrics.panelHeight` (eight 30-point slots, nine 6-point
gaps, two dividers, and 10-point insets: 316 points) is the full size. Stage Only
does not remove the installer, so the floating tools stay available while the
workspace is shared.

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
ScreenCaptureKit frame before publishing the new selected window. Source changes
retire the old stream, drain its serial callback queue, and create a new stream;
the callback stream identity plus selection and render generations reject stale
asynchronous work after a stop or rapid source change. Repeating the current
selection while capturing pauses it without discarding the selected window;
repeating it while paused re-enters `switching` and waits for a fresh first
frame. Keep this first-frame invariant when changing capture orchestration.

## Shortcut invariants

- Source slots use 1 through 9 with the presenter-selected global modifier:
  Command–Option, Control–Command, Command–Shift, or Disabled.
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
geometry, capture-frame generation acceptance, AppKit window interaction, and,
against fakes, real-time demo logic, script following, and the teleprompter
island's layout and content. ScreenCaptureKit
streams, mouse event monitoring, speech recognition,
Carbon hotkeys, permission prompts, and end-to-end window-server behavior
require the packaged app and are verified manually with the checklist in
`README.md`.

See [TESTING.md](TESTING.md) for the test-layer map, contributor conventions,
and the manual verification matrix for platform-only behavior.

`.github/workflows/ci.yml` enforces strict Swift formatting, validates metadata
and shell syntax, runs the complete test suite with warnings as errors and
coverage reporting with dedicated floors for capture-safety policy and the app
target, compiles an optimized build, then packages and verifies the signed app
bundle, embedded Sparkle framework, and resources, including the audio-input
entitlement and `NSMicrophoneUsageDescription` that Follow my voice needs, on
every push and pull request.

The `build-app.sh` and `dev-app.sh` entry points share
`scripts/build-and-package.sh`. The helper derives the signing identifier from
`Resources/Info.plist`; keep that metadata stable so macOS preserves Screen
Recording consent. Local builds use a stable ad-hoc designated requirement and
a development-only library-validation exception so the teamless ad-hoc process
can load the embedded Sparkle framework. Developer ID builds retain library
validation, enable the hardened runtime and trusted timestamp, then
`scripts/notarize-app.sh` performs submission, records the notarization log,
staples, and runs Gatekeeper checks. Public builds inject the HTTPS Sparkle feed
and EdDSA public key at packaging time; local builds leave updating inert.

## Real-time demos

`DemoSession` owns the selected app's open `RealTimeDemo` and every `DemoPhase` transition:
`composing`, `scouting`, `scoutPaused` (stop, presenter input, focus loss during
a foreground fallback, relaunch, leaving scope, needs approval, blocked with the
closest alternative, limits, and errors), `returning`, `needsStart`, `ready`,
`running` and `paused` in `verify` or `present` mode, `offTrack` (wrong screen, target not found, or
blocked), and `finished`. A run ID, task cancellation, and the bound source
reject late work after a pause, source change, or new run. The interface calls
a verify run a test run (Tested, Test Again); the code keeps the check names
(`checkAgain`, `isChecked`, `DemoStatus.checked`). `DemoLibrary` stores any
number of demos per app under `demo.library.v2`, matched to the app by bundle
ID or app name, and encodes each entry separately so one unreadable demo never
drops the others. `demo.selection.v2` maps each app to the demo it last had
open, or to `"new"` while it is writing a new demo, so a relaunch or source
change reopens the request field with the typed draft; without either, the
app's newest demo opens. `savedDemos` lists the selected app's demos, which
`DemoLibraryList` shows as a native `List`; `openDemo(_:)` switches to one,
`newDemo()` closes the open demo into an empty request field without deleting
anything, `cancelNewDemo()` (Cancel on the New demo row, or Escape) reopens the
demo that was open before New Demo, `renameDemo(to:)` retitles the open built
demo without leaving its phase (titles aren't in the fingerprint, so it stays
tested), and `deleteDemo(_:)` removes one after the panel's confirmation.
Loading a demo cancels pending work, including a start check still waiting on
the app. Editing a paused build's request (`editRequest()`) removes only that
draft, and a build that stopped before capturing its
start is dropped when the presenter leaves it or when it loads. Prompt drafts
live in `demo.prompts.v2` and are saved only while no demo is open. The Edit
Demo sheet closes when the source or the open demo changes. A failed Keychain
save is reported inside the inline key row. v1 outlines can't replay, so a one-time
migration copies their prompts into drafts and leaves the v1 key untouched for
older builds. Capture selection and state changes update the session even in
Stage Only mode. The selected app decides which demo appears; live capture
separately gates building and playback. App switches cancel work, clear cues,
close sheets, and restore the destination app's selected demo at its first
step; a saved draft reopens as an interrupted build.

Claude access is one setting for every app (`allowsAI`, stored as
`demo.allowsAIControl.v2`). `asksForConsent` shows the consent row while
composing until the presenter answers once (`consentAnswered`, stored as
`demo.consentAnswered`), and again when Build needs access that is still off.
`allowClaude()` turns access on, records the answer, finds ideas, and resumes a
waiting build; `cancelBuildSetup()` (Not Now) records the answer. `build()` asks
for setup inline through `buildSetup`: `.key` when no API key is stored, then
`.consent` while access is off. `saveKey` resumes the build. After Build or Test Again,
phase changes are announced until the demo is ready or presenting. On each,
`DemoNoticeContent.make(phase:demo:isChecked:)` says what the phase calls for (a
ready demo; a build paused for anything but the presenter; a test waiting at the
start; a test stopped), and the pure `DemoNoticeState.update(to:isActive:)` decides
whether `DemoNoticeController` (`DemoNotice.swift`) shows it, replaces what it
says, or hides it: nothing while BetterMeets is active, and nothing the presenter
already put away (Open BetterMeets, Dismiss, or switching to BetterMeets) while
the phase still calls for that same notice; a phase that doesn't (a resumed
build, a retried test) forgets it, as Build and Test Again do. The session keeps
`demoNoticeState` even without windows, and `isAppActive` is a test hook.
BetterMeets never activates itself: only the notice's Open BetterMeets button
reaches `openFromDemoNotice()`, which calls the `bringForward` test hook
(`BetterMeetsWindowActions.showStage()`, first leaving Stage Only for an
attention notice so its panel is there); Dismiss and switching to BetterMeets
reach `dismissDemoNotice()`. While the notice is up, the demo panel's own
VoiceOver announcement for that phase change stays quiet. While presenting, a
local key monitor turns Left Arrow and Page Up (presentation remotes) into
`previousStep()`, and, while the demo plays, Right
Arrow, Page Down, and Space into `skipLine`, except while a text field has focus.

`previousStep()` and `startOver()` work while presenting (playing, paused, or off
track) or finished; Start Over also works when ready. Steps change the app, so
both go back to the start through `returnToStart(then: .play)` with a
`rewindTarget`. Start Over plays from the opening line and, like Play Again at
the end, shows it at once. Previous Step shows the target step's line at once,
then runs the engine with `Options.rewindTo`: steps before the target replay
their actions only, skipping highlights and lines, with
0.15 seconds between them, and the target step is presented normally.
`rewindTarget` stays set until a run reaches it, so the target's line stays up
while the app isn't at the start, a resume or a retry keeps catching up quietly,
Previous Step counts from the target rather than from where the replay is, and
reaching it shows its line afresh, discarding anything heard or skipped while
catching up.

`findIdeas(again:)` asks for demo ideas while the request field shows, Claude
access is on, a key is saved, and the source is live. It reads a ready snapshot,
returns cached ideas for the app and web host (`demo.ideas.v1`) unless asked
again, and otherwise sends one screenshot and the encoded element list through
`DemoModelClient.ideas`, publishing `isFindingIdeas` while it waits. Building
cancels a pending request, and a failure is only logged.

`DemoBarView` is the panel's shell, 168 points tall in every phase but
`composing`, which grows with the request up to 200. `DemoLibraryList` holds the
app's demos with inline rename, the row context menus, Delete, and the
New Demo and − bar; the detail stacks `DemoStatusBand` (glyph, headline, subline,
More and Copy Details, and `BandActions`, whose `ViewThatFits` ladder folds
secondaries into a split-button primary), `DemoStepGrid` (three rows, column-major,
never scrolling; `StepGridLayout` sizes it and `StepOverflowPopover` lists steps
that don't fit), and `DemoActionBar` (Edit Demo…, Test Again, Writing lines…, the
Teleprompter toggle, and `PacingMenu`), or `DemoComposer` while composing.
`DemoPanelContent.make(_:)` is a pure mapping from `DemoPanelInputs`, read from
the session at once, to everything those views show: glyph, headline, subline,
transport, secondaries, primary, body, step cells, bar actions, and the open
row's `LibraryRowStatus`; `announcement(from:to:)` gives the VoiceOver
announcement for a phase change. `PanelActionID` names each action once (title,
menu title, short title, symbol, role, and help), and `perform(on:)` is the one
place it runs. `DemoCommands` and the floating widget take their first action
from `PanelActionID.menuPrimary(in:)` and `floatingPrimary(in:)`, and the
teleprompter's `IslandContent` takes its controls from `DemoPanelContent`. Edit
Demo, Rename, and Delete open the panel's sheet, field, or dialog, so the Demo
menu sets
`DemoSession.panelRequest` and `DemoBarView` consumes it; those items are
disabled in Stage Only, where the panel isn't on screen.

`DemoDriving` is the seam between demo logic and the app. `DemoDriver`
implements it; tests drive the scout, replay engine, and session through
`FakeApp` and `ScriptedModel`, without network access or synthesized input.

### Accessibility and matching

`AccessibilityService` is an actor on its own serial queue and the only owner of
live `AXUIElement`s. It returns Sendable `AXSnapshot`s and generation-scoped
`ElementHandle`s, so an element from an older snapshot can't be acted on, and
performs the background actions: `AXPress`, focusing and setting a field's
value, `AXScrollToVisible`, and app-level and system-wide hit tests.
`AXSnapshotBuilder` walks the window chrome under a capped budget, then web
areas largest first, within a 2.5-second deadline. It synthesizes labels for
rows, cells, headings, and unlabelled links from descendant text, and records a
field's text length but never its value. A node in a web area or scroll area
also records its viewport, the part of that area inside the window; nodes
outside scrolling content have none. `isVisible` stays a center test. `AppEngine.detect` classifies native,
Electron, Chromium, Gecko, and WebKit apps from the bundle. Electron and
Chromium get `AXManualAccessibility`, and Chromium falls back to
`AXEnhancedUserInterface`; `readySnapshot` waits up to four seconds for loaded
web content before reporting that the page isn't exposed. `DemoSceneEncoder`
lists up to 200 visible elements as `id role "label" x,y,w,h [flags]
in:container` lines with 0–999 coordinates. `AccessibilityService.follow` finds
elements of a recent snapshot (the last three are kept) in a later one by
identity (`CFEqual`), which survives scrolling where positions don't.

`DemoMatching` holds the deterministic replay rules. `LabelStability` separates
labels that name UI from data such as amounts, dates, and names in rows. Its
match key drops a trailing count badge, so “Inbox 3” and “Inbox (12)” name the
same control, and it discards generated identifiers (React's `:r…:`, `«r…»`,
and `_r_` forms, Radix, Headless UI, MUI, React Aria, Ember, Angular Material
and CDK, and long hex or numeric runs).
`DemoLocatorFactory` turns a node into a `DemoElementLocator` (role, stable
identifier, stable label or visual index within its container) and keeps it only
when `DemoLocatorMatcher` finds the same node again. A locator that resolves by
position alone is also refused when another element of the same role in its
container sits within 30 points, so replay never has to guess. The matcher
applies ordered rules without weights: identifier, stable label scoped to its
container, visual order inside real lists and tables (`AXTable`, `AXList`,
`AXOutline`, `AXGrid`, `AXBrowser`), then position. A data element found by
visual index must lie within 0.35 of the window diagonal of its recorded
position. Position-only matches (unlabelled icons, text values) stay inside the
recorded container, must sit within 18 points (controls) or 14 points (text) of
the recorded center, and must be less than half as far as the next candidate.
A text caption whose words changed may be matched only by data-like text in
that spot, never by another caption. Reading order groups elements into visual
rows (vertical centers within half the smaller height), top to bottom, each row
left to right. The matcher returns a result only when exactly one element
qualifies; for labelled elements the recorded rectangle is only a tiebreaker.
`ScreenSignatures` capture the URL host and path, selected items, headings, and
dialog state; only the URL is enforced until a check confirms the rest. Step
gates ignore headings, which can sit below the fold; headings still count when
recognizing another step's screen or the start.
`ScoutCompaction` drops rejected, undispatched, and unobserved records,
ineffective attempts that were retried, and toggles switched back with nothing
shown between, then turns scrolls into reveal hints for the next step.

### Building

`DemoScout` builds a demo by operating the app. Each turn takes a ready snapshot
and a window screenshot, asks the model for exactly one tool call, and requires
the chosen element ID to be listed and to yield a reproducible locator. A click
on text or an icon inside a link or button resolves to that control. It then
evaluates `DemoActionPolicy`, records a pending step, performs it through the
driver, waits until two consecutive snapshots agree, and records a
code-generated fact such as `#3 clicked tab “Transactions” → screen changed`.
The model sees the request, its turn-1 outline, these facts, and the current
window; it never sees its own earlier prose. A record becomes `unobserved` at
the commit boundary and then `changed`, `noEffect`, or `contaminated`, so an
interrupted build keeps dispatched actions and drops undispatched ones.
Repeating an action that just had no effect is rejected, and so is finishing
while a privacy, theme, or similar switch is left flipped. A build stops after 24
turns, 40 compacted steps, 240 seconds, $2 of estimated spend (including failed
calls), or three turns without change. When an action opens another standard
window of the app, `DemoDriver.closeWindows` closes the windows opened since the
turn's baseline with their close buttons through
`AccessibilityService.closeWindows`; the record becomes `rejected` with a fact
telling Claude it opened a separate window that BetterMeets closed, and the
build continues, up to three times per build. A window without a close button,
a fourth window, or the demo window itself closing pauses the build as leaving
scope. A click that changed nothing is retried once with a real pointer click,
except when it opened a window.
Before a highlight is shown, and before a click or typing once the policy
allows it, the scout frames the target (below). It records the step's locators
and screen signature from the screen before framing, which is what replay
resolves them on, and records how far framing moved the content
(`DemoStep.framing`). Later highlights in the same turn are followed through
earlier ones' scrolling and recorded where it left them, each saved as soon as
it's framed, a fact notes a highlight that was scrolled into view, and a
click's effect is judged against the framed screen, so the scroll never counts
as what the click did; its real-click retry and a checkbox's recorded state look
for the target where framing moved it. A step left out of the demo after its
framing scrolled (rejected, never dispatched, or dropped by compaction) keeps
that scroll on a record compaction leaves out, and compaction adds it to the
next step on the same page as `DemoStep.priorFraming`.
Policy questions stop it with a `PendingApproval` that the presenter allows or
skips. The start point records the screen signature, the full start URL for
browsers, a selected start anchor for other apps, and visible toggles; `finish`
adds the start description, which start checks and the model read, and a short
`label` that reads after "Starts on". Demos without a label fall back to
`RealTimeDemo.startLabel`, the first clause of the description. Recorded step
titles and the label are capped at 32 characters.

`DemoModelClient` calls the Messages API over raw HTTPS. Scout turns use
`claude-opus-5-5` with automatic tool choice and parallel tool use disabled,
strict tool schemas, server-side fallbacks (`fallbacks: default` behind the
`server-side-fallback-2026-07-01` beta header), and prompt caching on the system
prompt and request block. Effort starts at medium and retries at low after a
`max_tokens` stop. The scout gives prose without a tool call one corrective
retry, then treats it as `blocked`. Relocation uses `claude-haiku-5-5` with a
forced strict tool, and so do ideas: `suggest_demos` returns three label and
request pairs built on the core features the window shows, never paying,
sending, deleting, signing in or out, or changing account settings. Labels are
capped at 24 characters, requests at 240, and requests with control characters
are dropped. Window content is wrapped in `<untrusted_window_content>`.
Timeouts, lost connections, and 408, 429, 500, 502–504, and 529 responses retry
up to twice, honoring `retry-after` up to 20 seconds. Requests share an
ephemeral URLSession with cookies and caching disabled and redirects rejected.
Spend is computed from reported token usage, billing each server-side fallback
attempt at its own model's rates; a failed scout call throws `DemoModelFailure`
with what it cost, so the scout still counts it. Script writing, described
below, uses the same transport.

### Input

`DemoDriver` drives the source app in the background, so BetterMeets stays
active and the presenter watches the stage. It binds every input to the
captured window and reports scope violations. A click aims at the target's
visible center, hit-tests within the app, stops when another interactive
control of the app sits on top, re-checks the policy's denials against the
element actually hit, glides the stage's `DemoPointer` there, commits, and
performs `AXPress`; `CaptureManager.showStageClick` draws a stage-only ripple. Typing
skips a field that already holds the text, focuses it, and sets its value
through Accessibility: all at once while building and checking, and character
by character while presenting so it reads as typing on the stage. It accepts the
settled value when it equals the text or only appends a completion, then
commits before an optional Return. Scrolling performs `AXScrollToVisible` on the
target or, for a recorded scroll, on the next element past the fold;
`scrollBy` scrolls by an exact distance with precise (pixel) wheel events.

Input that macOS delivers only to the frontmost app runs in a foreground
fallback: key steps, Return after typing, ⌘L navigation, wheel and exact scrolling, and
clicks or typing that a control refuses through Accessibility. The driver
yields activation to the source app, raises its window, waits until
`SourceWindowFocusValidator` reports exact focus, checks that the app is still
frontmost before each event, and reactivates BetterMeets afterwards if it was
active. Fallback clicks move the real pointer and must hit the source process
in a system-wide hit test, so the teleprompter steps aside for them and for
wheel scrolls under it (`DemoInputObstruction`). `DemoInputSynthesizer` posts
these events from a private event source with explicit modifier flags and an
event tag, so
presenter-held keys never mix in and the presenter-input monitor ignores
BetterMeets' own events. Keyboard events go to the source process with
`postToPid`. Fallback typing switches to an ASCII-capable input source when
needed, selects the field's text, types it while the field keeps focus, and
verifies the value. Return goes only to the field the step typed into. Browser
navigation presses a layout-aware ⌘L, waits until a text field outside the web
area has focus, types the URL, confirms the host is in the field, and presses
Return in the same tab. Text with line breaks, tabs, or control characters is
never typed.

### Framing

`DemoFramer` shows a target whole before it's highlighted or acted on, with the
same rules while building, testing, and presenting, so a replay's page lines up
with the one its later steps were recorded on; `DemoFraming` is its pure
planner. A target counts as cut when its frame touches or crosses its
viewport's edge (within 1.5 points): Chromium clips frames to the viewport, so a
section running past the fold ends exactly at it, and one wholly past it is a
one-point strip there, both with their center in view. Targets outside any web
or scroll area, mixed with the browser's toolbar, or in two different panes are
never scrolled. The first scroll is `AXScrollToVisible` on the target at the
cut edge, in the background; Chromium and Gecko center a target that isn't
wholly in view, WebKit and AppKit stop it at the edge, and every engine leaves
one wholly in view where it is. So a target that only touches the edge (a
sticky header, the top of the page, its footer) stays put when that scroll
moves nothing, and only a frame known to run past the edge (WebKit, AppKit)
gets one exact `scrollBy` instead. When centering one target of a highlight
pushes another past the opposite edge, one exact `scrollBy` brings the group
back. Both bring the app forward briefly; clicks and typing never get one. For
a highlight taller than the viewport, the target's first descendant, usually
its heading, is scrolled in next when its top is cut, and a top below the
middle of the view is scrolled into view once; a top in the upper half is left
there. The last highlight is cleared before the first scroll. Framing makes at
most four scrolls, each followed by a 250-millisecond wait, then looks until
two in a row agree on where the followed elements sit (at most 1.5 seconds),
following them from look to look by identity and, when a look loses one,
matching its description from before the scroll where the scroll moved it; the
highlight's rectangle and the action's element come from that settled look.
The movement is measured from target edges the viewport didn't clip, or else
from the most common movement of labelled elements that appear once in both
looks. Page content across the target near the top of the view that stayed put
while the content moved is a sticky header. A highlight is drawn from the union
of its targets kept inside their viewport, and below such a header, by 10
points (16 for a circle), so it never runs past the page's edge or over the
toolbar. Framing runs only after the policy allows a step and never presses
anything.

### Replay and verification

`DemoReplayEngine` replays steps in `verify` or `present` mode. Each step waits
for its recorded screen, loaded web content, and unique, visible targets; after
an action it also waits for two consecutive snapshots to agree, so a screen
still redrawing isn't matched. A step's recorded scroll replays first, up to
once per scroll turn the scout took, whenever a target is missing or matched by
position, since such targets were recorded after that scroll. An off-screen
target is revealed with `AXScrollToVisible`, then the scroll wheel, and recorded
scrolls replay the same way. After the policy check, a step with targets is
framed and its highlight, click, or typing uses the framed screen. The engine
keeps a drift, how much higher the content sits than when the remaining steps
were recorded: each step adds what its framing moved minus its recorded
`framing` (all of it for steps built before framing), and a highlight skipped
live or while catching up subtracts its recorded `framing`, as each step does its
`priorFraming`. Targets are matched where the drift puts them, then where they
were recorded, and the drift resets when the page's address changes. A resumed
presentation is a new engine, which takes the drift over from the previous run.
A highlight whose target framing lost fails a test run and is skipped live.
Presenting, a highlight that had to be scrolled into view stays up at least 1.2
seconds, since its line showed before the scrolling. The gate allows 10 seconds after navigation or a
submitted search, 4 for actions, and 3 for highlights. The policy is evaluated
again against the live element. A step's approval applies only to the exact
question the presenter approved (`approvedReason`); steps approved before
questions were stored keep their approval. A checkbox already in its recorded
post-click state is not clicked again. When a target is missing on the right screen, `relocate` may heal it, and
the healed locator must find the element again on a fresh snapshot; healing
needs Claude access and a saved key, and sends one screenshot and the element
list. Present mode never heals actions; it may heal a highlight, skips one it
still can't find, and afterwards suggests a test run. If the live screen matches
another step's confirmed signature, the run reports `wrongScreen` so the
presenter can continue from that step. Verify holds are capped at 0.3 seconds
after actions and 0.6 for highlights; present holds divide by playback speed,
which defaults to 2×, is saved in UserDefaults, and matters only when the hold
is timed (voice following off or unavailable), but a step with a line never
holds for less than its `DemoStep.speakingTime` plus 0.4 seconds, so speed
shortens pauses and silent steps, never the time a line takes to say.

`returnToStart` never calls a model: browsers press their Back button, in the
background, until the start URL shows, and open it in the same tab only if that
fails; other apps close unexpected dialogs with their Close or Cancel button or
Escape, click the recorded start anchor, and restore start toggles, each anchor
and toggle click subject to the policy. `readiness` then compares the start
signature, toggles, and the first action's target. While in `needsStart`, the
session polls for up to two minutes so a presenter can reach the start by hand.
A verify run from the first step records the start screen as it finds it.
Continuing a paused check reuses the same engine, which keeps the steps that
already passed. Only a pass in which every step passed folds heals into the
steps, confirms the start and step signatures (keeping only evidence that held
in both runs), and saves the check; otherwise the demo stays unchecked.
`DemoFingerprint` hashes the start, every app-changing action and reveal hint,
the app version, the window size class, and the window size in 100-point steps
(`DemoAppInfo.windowBucket`, width and height each rounded to the nearest 100
points). Scripts, titles,
holds, and highlights are excluded, so word and timing edits and script
rewrites keep `DemoStatus.checked` valid while app updates, resizing into
another step, or action changes invalidate it. A passing check is saved only
while the live demo has the same steps; `finishVerification` merges what the
check learned (confirmed screen signatures, healed targets, and the start
signature) onto the live demo, keeping any script written meanwhile.

The cursor advances at each action's commit boundary (the press or mouse-down,
completed typing, the key press, or the URL's Return) before yielding, so
pausing or cancelling never repeats a dispatched action. While BetterMeets
drives the app, `DemoSession` watches mouse-down, key-down, and scroll events,
ignores events delivered to BetterMeets' own windows and tagged synthetic
events, and pauses only for clicks or scrolls whose window under the pointer is
the source window (or, without one, that land in the source frame while the
source app is frontmost) and for keys while the source app is frontmost. Focus
changes never pause a demo, and input to other apps, including the meeting,
is ignored.

Each step's `script` is its read-aloud presenter line; script writing gives
every step one, with a short transition for navigation steps. Holds come from
`DemoStep.hold(for:action:)`: speaking at about 150 words per minute
(`DemoStep.wordsPerSecond`, 2.5) plus 0.8 seconds, bounded to 1.5–20 seconds;
a step without a line holds 0.4 seconds after an action and 1.6 for a
highlight. There is no manual timing: editing a line or rewriting the script
recomputes the step's hold from its new line.
`DemoEditorView` (Edit Demo) edits the title, the start label, the
opening line, each step's title and line, and the closing line, offers the
tone, audience notes, and Rewrite Lines, and copies the whole script. It saves
through `updateDemo(_:base:)`, which applies only the fields that differ from
the copy the sheet opened with, so a rewrite that lands meanwhile survives on
untouched lines; when a rewrite finishes while the sheet is open, it takes the
new lines for everything not edited in the sheet. Targets and actions can't be
retyped, and removing an action removes every later step.

### Script and teleprompter

`DemoSession.writeScript` runs when a build finishes or **Use N Steps** is
chosen, alongside the automatic return and check, and again on **Rewrite
Lines**. Its `ScriptRequest` carries the request, app name, start description,
outline, each step's kind, target display name, title, current line, and
whether it navigates, plus the tone, audience notes and `ScriptLanguage`
(also sent with each scout turn and ideas request; `.automatic` asks for the
request's language). `DemoModelClient`
sends it to `claude-opus-5-5` as text only, with low effort, a strict
`write_script` tool under automatic tool choice with parallel tool use
disabled, and server-side fallbacks. The prompt asks for a line on every step,
distinct titles of two to four words, and a start label. `decodeScript`
accepts only an answer with one entry per step, collapses whitespace, and caps
titles and the label at 32 characters and lines at 300. `applyScript` merges
the draft onto its own demo by step ID: the open demo, or, when the presenter
opened another one meanwhile, the copy in `DemoLibrary`, which it saves there.
Steps removed meanwhile stay removed, and it replaces only steps whose title,
line, and hold are unchanged since the request, so lines edited meanwhile keep
their edits. It sets `openingScript`, `closingScript`, and the start label
unless they were edited meanwhile, recomputes holds for the replaced lines, and
saves a new revision. A failure is logged, published
as `scriptError` for the Edit Demo sheet, and leaves the existing lines. Only
words change, so the check's fingerprint is unaffected.

`PresenterPrompter` holds the line being presented (opening, step, or closing),
its `ScriptFollower`, the heading, the next step's title, the position,
timed-hold progress, the last three words heard (`heardTail`), and `showCount`,
which every `show` bumps so a line shown again reads from its start, and persists
`demo.followsVoice` (on by default) and `demo.notesFontSize` (16–48 points, 26
by default). The replay engine's
`opening` hook shows and holds the opening line before step 1 only when Play
starts from the top (`startsFromTop`), never on a resume, `onStep` shows each
step's line, and finishing shows the closing line or clears the prompter when
there is none. The `hold` hook routes present-mode holds through
`PresenterPrompter.hold`, which re-checks every 100 ms whether it is following
the voice (`isFollowingVoice`: `followsVoice` and `SpeechListener.wantsToListen`,
which stays true while the listener starts, listens, or reconnects). Following
the voice, a hold has no timer: it ends 0.35 seconds after `ScriptFollower`
reports a non-empty line said; once its `coverage` reaches `gistCoverage` (0.6),
something was heard since the line appeared, and `naturalPause` (1.1 seconds)
has passed since `SpeechListener.lastHeard`; or once “next” was heard and 0.6
seconds pass with no new words. A step without a line moves on after
`silentStepBeat` (0.8 seconds). `heard()` publishes the follower and
`heardTail` only when they change, so a recognizer re-sending words doesn't
redraw the island; it refreshes `heardTail` on every result, since a revision
can change words without adding any, and records the command only when the
newest word normalizes to one of `nextWords` (next, siguiente, suivant, weiter, avanti,
proximo, seguinte) and the follower didn't
advance on it, so “next” read as a word of the line doesn't count, and any
later word cancels it. Otherwise the hold waits for its timed `seconds`.
`skipLine` (Next Line in the teleprompter or demo panel, ⌃⌘→, or Right Arrow, Page
Down, or Space in BetterMeets while a presentation plays) marks the line said and
ends either kind of hold.

`TeleprompterController` (`TeleprompterIsland.swift`) owns one `IslandPanel`
(`IslandPanel.swift`, shared with the demo notice): a borderless,
nonactivating `NSPanel` subclass that can take clicks and menus without becoming
main, which `IslandPanel.make(title:rootView:)` puts three levels above `mainMenu` (over the menu bar and its status items,
under other apps' menus, Spotlight, and notifications), joining all Spaces and
full-screen apps, stationary, ignoring the window cycle, with no shadow and
`sharingType = .none`. It sets `canHide = false`, so hiding BetterMeets leaves
it and showing it never unhides BetterMeets, and shows help tags while
BetterMeets is inactive. It never constrains its frame, so it can sit over the
menu bar; its hosting view accepts the first click and never sizes the panel;
and it is shown with `orderFrontRegardless`, so BetterMeets never activates. It
can't be moved or resized, and on first use it deletes the frame the old panel
autosaved. `IslandScreen.camera()` picks the built-in display, else the primary,
never `NSScreen.main`, which follows the key window. `IslandLayout.make` is
pure: from the display's frame, visible frame, safe-area top, and the auxiliary
areas beside the notch, plus the text size and the measured row height, it
derives the notch; where the island hangs (from `frame.maxY`, centered on the
notch, or from `visibleFrame.maxY` without one); the band beside the camera (as
tall as the menu bar, or the notch when the menu bar hides, and 28 points
without a notch); the expanded size (`clamp(16·s + 84, 460, 700)` wide and
`band + 6 + viewport + 48` tall); the compact width (the notch plus 224); the
row advance; the viewport (about 2.6 rows, at most 150 points); how many rows
stay above the one being read; and the meter's width. Frames are rounded to the
backing scale. `IslandShape` puts Textream's concave shoulders on an
`UnevenRoundedRectangle` with continuous bottom corners, animatable through both
radii, and `IslandShapeState` gives the collapsed (the notch itself), compact,
and expanded outlines. `IslandType` makes the rounded `NSFont` that rows are
measured in.

The controller measures again on every show and text-size change and on
`didChangeScreenParametersNotification`, which also docks the panel again at
once. It watches the session's phase, line, and text size, and reacts a run-loop
turn later, once they're set. `IslandMode.make(phase:line:)` expands the island
while there's a line the demo can present (ready, not at the start or going back
before playing, presenting, paused, or off track) and whenever the demo is
finished; otherwise it is compact. `IslandChrome` is the `@Observable` state the
controller moves and `TeleprompterIslandView` draws: the layout, the shape, and
the content's mode, size, and opacity. A move sets the frame to the union of the
current and target shapes, fades the content out, animates the shape with
`completionCriteria: .logicallyComplete`, then fits the frame to the shape and
fades in the content for the new mode; the content's mode and layout change only
while it's hidden. Every text size from 40 points up makes the largest island, so
a new size there leaves the shape alone: the content fades out and back in at the
new layout, and a move already under way rests in the newest layout. Showing
starts from the collapsed shape, and hiding ends
there with `orderOut`; without a notch the panel also fades, and with Reduce
Motion it only fades. Every move bumps a `transition` token, so the completion
of a move a newer one overtook does nothing, and ⌃⌘N during a hide keeps the
island.

`IslandContent.make(IslandInputs(session:))` is a pure mapping, tested like
`DemoPanelContent`, from the phase, the prompter, the listener's state, and the
panel's own `DemoPanelContent` (built with `DemoSession.stagePaused`, so the two
never disagree) to what the island shows: the band's glyph, position, place, and
Next; the body (the line with its word style and dimming, no line, or the
finished message); the meter; the status, by priority (off track, paused, going
back or catching up, not at the start, not live, finished, mic unavailable,
moving on, preparing, the countdown, words heard, then the ready notice or
pacing); the four slots; and the options menu's extras. `IslandContent.slots`
keeps Start Over, Previous Step, the panel's primary, and Next Line or Next Step
in fixed places, disabled when the panel has no transport; off track, Skip Step
takes the fourth place and the other secondaries go to the menu.
`PanelAction.islandSymbol` gives a glyph to the few actions the panel shows as
text. `ScriptRows` breaks `ScriptFollower.displayWords` into rows greedily with
the `IslandType` font's measurements, splitting a word wider than a row into
pieces that keep its index, and `ScriptRows.top` keeps the row being read
`anchor` rows from the top, never moving back until the line, size, width, or
weight changes or the line is shown again (`PresenterPrompter.showCount`).
`ScriptRowsView` draws one `Text` per row, offsets the rows, fades the bottom
edge while rows go on below it, and fades the top edge only over a row already
read (`ScriptRows.fadesTop`). With voice off the rows follow the hold inside one
`TimelineView` that pauses without one, so they keep their place when the hold
ends; the footer's VoiceOver label and value tick through a timed hold the same
way. The meter reads `SpeechListener.levels` in its own view, so only it redraws
twenty times a second. `TeleprompterIslandView` builds the panel's
`DemoPanelContent`, which reads the app's windows and hashes the demo, only when
the session changes, and hands it to the island view, which redraws for each
word heard.

Real pointer input must reach the source app, so `DemoDriving` carries an
`inputObstruction` (`DemoInputObstruction`, declared in `DemoDriver.swift`),
which `DemoSession` sets, when it opens windows, to a `DemoInputObstructions`
that asks the teleprompter and then the demo notice. `DemoDriver`
asks it to step aside before a fallback click's system-wide hit test and around
a wheel scroll. When the point is within 8 points of the panel, `stepAside(at:)`
orders it out, waits 32 ms for the window server, and returns a restore that
brings it back 250 ms after the input, fading in over 0.2 seconds (at once with
Reduce Motion); overlapping inputs nest, and a Hide meanwhile isn't undone. The
panel never toggles `ignoresMouseEvents`.
`docked` (a `DockedIsland`: the frame and the body's width between the
shoulders) is where the island rests for the session's current phase and line,
even mid-morph, and counts whenever the island is shown, even while it has
stepped aside for a demo input. `DemoNoticeController` reads it through a closure
the session gives it, and `onDockedChange` fires when it changes (shown, a new
size or text size, displays changed), or once the panel has folded away after a
Hide, so the session redocks the notice. `DemoNoticeLayout.make(screen:island:)`
is pure: with the island on the same display, a card 8 points below it, exactly
as wide as its body, with 8 points of headroom in its window to slide out from
under it unclipped; otherwise, from `IslandScreen`'s `notch`,
`band`, `islandTop`, and `islandMidX` (which `IslandLayout.make` uses too), an
island hanging where the teleprompter would, `clamp(notch + 300, 440, 520)`
wide, or 440 without a notch. The notice picks the display under the pointer
and stays on it while it's up; `DemoNoticeView.height(of:in:)` measures its
content at that width. Like the teleprompter, it grows from the notch shape to
its own (`smooth(0.4)`, then the content fades in) and folds back, or fades
without a notch or with Reduce Motion; new content in the same layout
cross-fades and morphs, and a new layout (the teleprompter shown, hidden, or
resized, or displays changed) fades out and back in there, and new content restores the
alpha of a move it overtook. A transition token makes the completion of an
overtaken move do nothing. The panel and frame math are shared with the
teleprompter (`IslandShapeState.notch`, `CGRect.hanging`, `CGSize.covering`).
The notice is never at rest while a demo acts, but a run can start while it
folds, so its `stepAside(at:)` ends the fold at once for an input under it. It posts an
`announcementRequested` notification as it appears, and an activation observer
puts it away when BetterMeets becomes active. `DemoSession` mirrors
`DemoDriving.isStagePaused` in `stagePaused` when it's created and on every
`sourceDidChange()`. It exposes `teleprompterVisible`, `toggleTeleprompter()`,
`showTeleprompter()` (which shows the line first, so the island grows straight
to the size that shows it), and `hideTeleprompter()`; entering present mode
opens the teleprompter when `opensTeleprompter` (stored as `demo.opensNotes`) is
on, which is the default.

When a demo becomes ready with voice following on, `SpeechListener.prepare`
asks for the microphone and installs the on-device model through
`AssetInventory` without listening. The listener runs only while
`DemoSession.updateListening` sees a present-mode run, playing or paused, with
voice following on, in a session that opens windows (test sessions pass
`opensWindows: false` and never use the microphone), and stops when the demo
finishes. `requestStart` sets `wantsToListen` at once and starts asynchronously
under a request token that `stop()` bumps, so a start overtaken by a stop never
turns the microphone on. It requests microphone
access, then uses `SpeechTranscriber` with volatile and fast results in the
script's dominant language (`NLLanguageRecognizer`, for scripts of at least six
words), falling back to the supported equivalent of the current locale and then
en-US, and biases `SpeechAnalyzer` toward up to 100 words from the script. An
`AVAudioEngine` input tap converts buffers to the analyzer's format off the
main actor, and `LevelMeter` turns the same audio into one level per twentieth
of a second, whatever the buffer size, on a decibel scale (−55 dBFS is 0 and
−12 dBFS is 1) so ordinary speech doesn't pin the bars. `LevelHistory`, observed
apart from the listener's published `state`, keeps the last 64 levels for the
island's meter, letting drops fall softly, and resets when listening stops. An
`AVAudioEngineConfigurationChange` (a new input device, or another app
reconfiguring the microphone) restarts listening, at most once every 2 seconds,
without clearing `wantsToListen`, so a hold keeps waiting for the voice. Denied
microphone access, unavailable recognition, a start that throws, or a results
stream that ends clears it and marks the listener unavailable, so holds fall
back to timers. Recognized words stay in memory (the last 400 finalized words
plus the current partial result) and are never written or sent. A DEBUG-only
`simulateHearing` sets `wantsToListen` and feeds words through the same path,
for tests; `simulateListening(levels:)`, `simulateState(_:)`, and
`PresenterPrompter.simulateHold(seconds:elapsed:)` set up the island's states
for snapshots. `PresenterPrompter`
feeds the follower only words heard since the line appeared, and words a
recognizer re-sends are ignored. `ScriptFollower` normalizes words, drops
fillers, and aligns the last six heard words against the next 14 words of the
line, looking a few words back for repeats. It only moves forward; a jump of
more than two words needs newly heard words matching the words it skips, and
longer jumps need more of them. Words of four letters or fewer must match
exactly, longer words may be partial or slightly misheard, and numbers are
skipped. A line counts as said when nothing is left, or when at least three
quarters are said and only its last word, or two short ones, remain. Separately,
`coverage` is the share of the line's key words (four letters or more, not in
`commonWords`) heard in any order, counting a compound said as two words, so a
paraphrase can finish a line without moving the highlight.

### Cues

`DemoCue` is transient rendering state, separate from persisted manual tool
preferences. `DemoEffectLayer` and the existing camera/click/keystroke
primitives render it on the stage. `DemoPointerLayer` draws the system arrow
gliding to each target (without animation under Reduce Motion) while the real
cursor stays with the presenter. Pausing demo playback retains the cue;
resetting or changing capture clears it and the pointer. Stage Only hides the
demo panel, while the floating source widget keeps playback controls available.
`DemoDrivingGlow` overlays the workspace stage with `DemoGlow`, an angular
multi-hue edge that turns while the phase is `scouting`, `returning`, or a
`verify` run, and holds still under Reduce Motion; it ignores hits, is hidden from
accessibility, and isn't drawn in Stage Only. The request field reuses
`DemoGlow`, without turning, as its focus ring.

`SourceEffectPresenter` hosts both manual spotlights and demo overlays in
click-through, nonactivating panels. Demo spotlights, circles, and keystroke
labels use the same cue over the source window while the source app is in
front. Focus loss hides the source overlay without discarding the cue. Demo
magnification remains a stage camera effect; clicks act on the source's
original layout.
