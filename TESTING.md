# BetterMeets testing guide

BetterMeets keeps deterministic decisions in plain Swift and treats macOS
framework integration as an edge. Tests should follow the same boundary: cover
policies, geometry, persistence, state transitions, and AppKit configuration in
automation; verify privacy prompts and live window-server behavior with the
packaged app.

## Test layers

| Layer | Examples | Expected coverage |
| --- | --- | --- |
| Pure policy and geometry | shortcut reconciliation, capture selection and frame generations, window eligibility, auto-zoom camera and styled-frame transforms, normalized coordinates, stage sizing and workspace fitting, script following | Every branch and boundary value |
| Persistence | presentation settings, shortcut pins and exclusions, corrupt or legacy data | Defaults, round trips, normalization, and invalid input |
| Main-actor models | annotation fading, spotlight state, armed presentation effects | State changes and cancellation-sensitive behavior |
| AppKit integration | overlay window levels, event-monitor ownership, native workspace configuration, workspace notifications | Configuration and callback translation that can run without privacy consent |
| Live macOS integration | ScreenCaptureKit, global mouse monitoring, Accessibility permission, Carbon hotkeys, meeting-app window capture, microphone and on-device speech recognition | Manual packaged-app verification |

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
    source status above the preview, and a bottom demo composer. The compact feature widget follows the selected
    source, with demo playback and presentation tools. Check source selection, thumbnails, unavailable pins,
    hover/Space previews, context menus, Up/Down/Return, and Option–number shortcuts.
12. Toggle Stage Only from View or Control–Command–S. Confirm the sidebar, status
    strip, and toolbar disappear while capture continues. Escape and the same
    shortcut restore controls. Share BetterMeets in a meeting app and confirm
    that visible workspace controls appear only when the workspace is shown.
    The separate feature widget stays available beside the source in Stage Only.
    Move and resize the source, including near screen edges and on another display.
    Check right/left gutter placement, onscreen fallback, source switching, settings,
    and hiding when the source closes or any other app becomes frontmost.
    In particular, returning to BetterMeets must hide the widget over its workspace
    and Stage Only view. Show Source Tools must activate the source app, with the
    widget reappearing beside it. Its buttons and settings should preserve source focus.
13. Resize to the minimum and maximize/full-screen the workspace. Switch between
    landscape and portrait sources: content must fit without stretching or
    cropping, and the workspace must not resize. Close/reopen and relaunch to
    verify size and position restoration.
14. Settings has General, Stage, Focus, Draw, Clicks, and Keys. The gear anchors
    its popover; Escape/outside-click dismisses it. Verify no Voice tab remains and no microphone prompt appears
    until a demo first becomes ready with Follow my voice on. Demo Setup owns the API-key
    field and selected-window AI consent. Existing settings
    saved to the removed tab should fall back to General.
15. Check Light and Dark appearances, Reduce Transparency, Increase Contrast,
    Reduce Motion, keyboard focus, and VoiceOver labels. The six tool rows and
    source list must remain readable and reachable at minimum window size.

Record the macOS version and meeting app when a manual result depends on
window-server or capture-framework behavior.

## Real-time demo checks

Demo tests run entirely against fakes. `FakeApp` implements `DemoDriving` as a
small screen graph, such as a Subtis-style movie search, and `ScriptedModel`
returns scripted tool decisions and a fixed script draft. No test calls a paid
API, takes a screenshot, listens to the microphone, or posts input to another
app: test sessions pass `opensWindows: false`, which never starts the listener,
and pacing tests feed words through the DEBUG-only
`SpeechListener.simulateHearing`. The demo suites contain 66 tests: 57 in the
nine `MeetStageTests` demo suites, including `ScriptFollowerTests` (5) and
`PresenterPacingTests` (6), and 9 in `DemoActionPolicyTests`. The full suite of
192 tests passes, with demos driven only by these fakes:

| Suite | Coverage |
| --- | --- |
| `DemoScoutTests` | Recording a search, a result, and highlights from what was on screen; rejecting unlisted elements and reporting a blocked request; approval before typing text the presenter didn't write; an approval covering only the question the presenter answered; resolving a click on text inside a link to the link; never clicking destructive controls; refusing to repeat an ineffective action and stopping when stuck; keeping dispatched and dropping undispatched actions after an interruption |
| `ScoutCompactionTests` | Keeping only the retry of an ineffective action; dropping rejected, never-dispatched, and unobserved records and toggles switched back; turning a scroll into a reveal hint |
| `DemoReplayTests` | One in-order replay with highlights; resuming without repeating an action; not re-clicking a toggle already in its recorded state; recognizing another step's screen; skipping a missing highlight live; healing a renamed control and keeping the heal after a check; returning to the start page in the same tab without a model |
| `DemoMatchingTests` | Stable and data labels; container-scoped label matching; ambiguity without a container unless one match is clearly nearest; data rows by visual order, and only near where they were recorded; unlabelled icon buttons found where they were and only inside their container; refusing a target crowded by look-alikes when it's recorded; reading order by visual rows; captions matched by their words and values by position; count badges that keep a control's identity and generated IDs that are ignored; identifiers over labels; screen signatures before and after confirmation; fingerprints that ignore words and timing but not actions or app version |
| `AXSnapshotBuilderTests` | Walking web content, naming rows from their text, and never exposing field values |
| `DemoModelClientTests` | Scout request shape (auto tool choice, strict schemas, fallbacks, stable bytes for caching); reading the tool call after thinking blocks and computing cost; prose without a tool call, refusals, and overload retries; script requests that list every step and accept only a complete answer; billing each fallback attempt at its own model's rates |
| `DemoSessionTests` | Build, return to start, check, ready, and play, then restore after relaunch, keeping the script written during the check without undoing the check; continuing a paused check where it stopped and still ending checked; stopping a build and offering to keep building; per-app consent before touching the app; migrating v1 prompts while leaving v1 data untouched |
| `ScriptFollowerTests` | Following a line read aloud word by word, including partial words; tolerating misheard words and swallowed endings; not jumping ahead on an ad-lib that shares one word with a later sentence; never moving backwards on a repeated word; Skip marking the line said |
| `PresenterPacingTests` | A line always getting at least the time it takes to say it; Follow my voice on by default, falling back to the timer without a listening microphone, and Skip ending a timed hold early; short words matched exactly and no jump without the words it skips; following the voice, a line holding with no timer until it's said; a step without a line moving on after “next” and a pause; “next” read as a word of the line not counting as a command |
| `DemoActionPolicyTests` | Ordinary navigation; destructive buttons denied and destructive navigation needing approval; localized destructive buttons; dialog buttons other than dismissals needing approval; data rows judged by their details; typing rules, including denied line breaks and tabs; allowed page hosts, matched exactly or as subdomains rather than as substrings |

Live end-to-end validation of the new pipeline is ongoing. A 10-step Ledger
demo has been checked and played live once; voice following and the
notes panel's exclusion from screen sharing have not yet been validated live,
and results from the previous planner do not carry over. Until the checklist
below passes, treat real-time demos as not fully verified in real apps. Use a
demo account and an API key, and record the macOS version and each app's
version.

1. **Subtis in Dia and in Zen.** Ask for a search for “The Matrix” on Subtis,
   and stay in BetterMeets while it builds. Steps should appear live, with dashed
   outline beats ahead. The browser must stay in the background, except for a
   brief trip to the front for Return after the search, after which BetterMeets
   is active again. On the stage, the virtual cursor glides to each target and
   each click ripples. While playing, typing must appear character by character
   on the stage, Return must follow only the search, and the result must open in
   the same tab. After building, the browser goes Back to the start URL and the
   check ends with **Checked**. Play at 2× and 1×. In Zen, if the page isn't
   exposed, the strip must show the `accessibility.force_disabled` guidance
   instead of acting.
2. **Ledger.** Ask to open Transactions, open the first transaction's details,
   and show discreet mode. The first row must be found by position, not by its
   amount or date. If the build turns discreet mode on, it must turn it back off
   before finishing, and Return to Start must restore the start item and toggles,
   leaving discreet mode as it was before the build.
3. **Blocked request.** In Dia, ask to make the theme blue. The build must stop
   with a reason and the closest real alternative without changing any setting.
   **Show … Instead** returns to the start and rebuilds with the alternative;
   **Edit Request** returns to the composer.
4. **Presenter input.** During a build, a check, and a presentation, click
   inside the source window: each pauses with the mouse-or-keyboard message, and
   continuing does not repeat a dispatched action. A check paused this way must
   continue where it stopped and still end with **Checked**. Clicking or
   scrolling in BetterMeets, the meeting app, or another app, or bringing another
   app to the front, must not pause. Pause Demo and Pause Stage stay separate.
5. **Return to start.** After a demo finishes, **Return to Start** reaches the
   start without an AI request; in a browser it uses the Back button without
   bringing the browser forward. Move the app elsewhere by hand and press
   **Play Demo**: the strip shows **Not at the start**, then returns to ready
   once you reach the start by hand. The floating widget offers Return to Start
   while the strip shows **Not at the start**.
6. **Wrong-screen recovery.** Pause a checked demo, open a later step's screen
   by hand, and continue: the strip offers **Continue from Step N**. Hide a
   highlighted element: a live presentation skips that highlight with a notice
   and keeps going. Rename a clicked control: **Check Again** relocates it or
   reports it missing, while a live presentation stops at that step instead of
   relocating it.
7. **Approvals and policy.** Ask to type text that isn't in the request, or to
   open a site the request doesn't name: the build pauses with **Allow** and
   **Skip**. A request that needs a Delete or Send button must highlight it, not
   click it. A confirming button in a dialog asks first; Cancel or Close doesn't.
8. **Script writing.** After a build, the strip shows **Writing the script…**
   while the check runs, and the check still ends with **Checked**. In
   **Presenter Script…**, choose **Rewrite Script** with each tone
   (Conversational, Concise, Technical), with and without audience notes: each
   rewrite gives an opening line, a line and a two-to-four-word title for every
   step, and a closing line, and the demo stays **Checked**. Start a rewrite,
   then change one step in **Edit Steps…** while Claude writes: that step keeps
   your edit and the others take the new lines. Rewrite offline: the reason
   appears in the Script sheet and the lines stay.
9. **Presenter notes.** Play a checked demo: the notes panel opens without
   taking focus and shows the opening line, then each step's line with the next
   step's title and a progress bar during timed holds. Pause and continue: the
   opening line must not play again. Change the text size,
   move the panel, then hide and show it with the strip's speech-bubble button
   and ⌃⌘N; it returns where it was. Share the BetterMeets window in Google Meet
   and confirm from another participant's view that the panel isn't shown; then
   share the entire screen and record whether macOS hides it.
10. **Follow my voice.** With it on (the default), finish a build: macOS asks
    for the microphone when the demo becomes ready, not on Play. The strip
    caption reads “N steps · paced by your voice”, the options and Demo menus
    have no Speed, and Demo Setup shows Speed disabled with an explanation.
    Present while Google Meet uses the same microphone; spoken words dim, the
    next word is highlighted, and each step moves on a beat after its line is
    said. Stay silent on one line: the demo keeps waiting, with no timer. On a
    step without a line, the notes and strip show “Say ‘next’ to continue”;
    say “next” and pause: the demo moves on. Read a line that contains “next”
    as a word: the demo follows the line and doesn't skip it. Let Meet adjust
    the microphone mid-line, and connect AirPods mid-demo: listening continues
    and the demo doesn't advance on its own. **Skip** in the panel and ⌃⌘→
    (**Next Line**) both move on. With the microphone denied, the demo plays on
    its timers. Turn Follow my voice off: playback is timed again, Speed returns
    to the menus and Demo Setup, the caption shows an estimated length, ⌃⌘→
    ends a timed hold, and at 2× lines still get their full speaking time. The
    other participants must still hear you, and listening must stop when the
    demo finishes.

Also confirm, in any app: steps never act after a source switch or capture
pause; recovery buttons are disabled while the source isn't live; **Use N Steps**
checks a partial build; quitting mid-build reopens with **Keep Building**;
**Edit Steps…** keeps **Checked** after changing words or holds but clears it
after removing an action, which also removes later steps; an app update, or
resizing a checked demo's window by enough to change its 100-point size step,
shows **Not checked**. In Demo Setup, Return in the API-key field saves the key.

For a demo spotlight or circle, pause, bring the source app to the front, and
compare it with the stage: the same region must be highlighted on both, and the
highlight must remain while paused. Switch away from the source and back; its
overlay must hide and then return without losing the cue. Return to the start or
clear the stage and check that it disappears. Check that a demo spotlight replaces an enabled manual spotlight
temporarily, then restores the manual effect without changing its setting. Key
badges also appear over the source; magnification is a stage camera effect.

Open **Presenter Script…**, inspect the opening line, each step's script, and
the closing line, and use **Copy Script**.
`Demos/ledger-transactions-script.txt` holds reference narration written for an
earlier Ledger demo; new builds generate their own scripts.

For app scoping, switch from an app with a demo to one without a demo. Only the
new app's composer should appear, without the previous app's steps or errors.
Switch back and verify its steps and script return. Build demos for both apps,
relaunch, and confirm both restore. **New Demo…** must clear only the selected
app. Repeat source switching in Stage Only, and verify pausing capture
preserves the selected app's demo while disabling playback.

### Debugging AI requests

On an HTTP failure, the demo strip shows Anthropic’s error message. **Copy Details**
copies the operation (`scout` or `relocate`), model, HTTP status, error type,
request ID, and that message, with API keys redacted. Use the request ID when
investigating with Anthropic. A 400 alone does not distinguish invalid request
content from an account spending limit; read the provider’s reason before
changing the request.

To watch requests in Terminal:

```bash
/usr/bin/log stream --level info --style compact --predicate 'subsystem == "com.lndgalante.bettermeets" AND category == "demos"'
```

The log contains request metadata (model, stop reason, tool name, latency,
estimated cost, and, on failure, status, error type, and request ID) plus
pauses, heals, and focus-check failures. Script requests appear with the tool
`write_script`; a failed rewrite logs `Script rewrite failed` and keeps the
existing lines. Speech recognition logs errors that stop it, failed speech-model
downloads, and restarts after the audio input changes, never what it heard. The log never contains response bodies, keys, prompts, or
screenshots. `DemoModelClientTests` covers response parsing,
refusals, and retries without calling the live API; error-body parsing and
redaction in `DemoRequestFailure` have no dedicated tests yet.
