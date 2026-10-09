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
11. The main window contains a full-height vertical source selector and, beside
    it, the stage above a rounded demo panel. The window toolbar shows the app
    icon, name, state badge, and window title on the leading edge, and on the
    trailing edge the five effect toggles in one capsule and Pause Stage and
    Clear Stage sharing a second capsule, with nothing between the toolbar
    and the stage. The compact feature widget follows the selected source with
    the demo button (once the app has a demo), Pause Stage, Auto Polish,
    Spotlight, Annotations, Click Highlights, Keystrokes (with a permission
    badge while Accessibility is missing), and More with Clear Stage, Show
    BetterMeets, and Settings; it is shorter while the app has no demo. Check source selection,
    thumbnails, unavailable pins, hover/Space previews, context menus,
    Up/Down/Return, and Option–number shortcuts.
12. Toggle Stage Only from View or Control–Command–S. Confirm the sidebar, demo
    panel, and toolbar disappear while capture continues. Escape and the same
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
14. Settings has General, Auto Polish, Spotlight, Annotations, Click Highlights,
    Keystrokes, and Demos. Verify no Voice tab remains and no microphone prompt appears
    until a demo first becomes ready with Follow my voice on. Settings › Demos owns the
    API-key field and the Claude access checkbox, and **Demo Settings…** in the
    demo panel's **Pacing** menu opens it. Existing settings
    saved to the removed tab should fall back to General.
15. Check Light and Dark appearances, Reduce Transparency, Increase Contrast,
    Reduce Motion, keyboard focus, and VoiceOver labels. The toolbar items and
    source list must remain readable and reachable at minimum window size.

Record the macOS version and meeting app when a manual result depends on
window-server or capture-framework behavior.

## Real-time demo checks

Demo tests run entirely against fakes. `FakeApp` implements `DemoDriving` as a
small screen graph, such as a Subtis-style movie search, and `ScriptedModel`
returns scripted tool decisions, a fixed script draft, and fixed ideas. No test calls a paid
API, takes a screenshot, listens to the microphone, or posts input to another
app: test sessions pass `opensWindows: false`, which never starts the listener,
and pacing tests feed words through the DEBUG-only
`SpeechListener.simulateHearing`. The demo suites contain 128 tests: 119 in the
ten `MeetStageTests` demo suites, including `DemoPanelContentTests` (49),
`DemoScoutTests` (10), `DemoSessionTests` (14), `ScriptFollowerTests` (5), and
`PresenterPacingTests` (8), and 9 in `DemoActionPolicyTests`. The full suite has
255 tests (241 in `MeetStageTests` and 14 in `MeetStageCoreTests`), with demos
driven only by these fakes:

| Suite | Coverage |
| --- | --- |
| `DemoScoutTests` | Closing a separate window a click opened, leaving that click out, and building on; recording a search, a result, and highlights from what was on screen, with step titles and the start label capped at 32 characters; rejecting unlisted elements and reporting a blocked request; approval before typing text the presenter didn't write; an approval covering only the question the presenter answered; resolving a click on text inside a link to the link; never clicking destructive controls; refusing to repeat an ineffective action and stopping when stuck; keeping dispatched and dropping undispatched actions after an interruption |
| `ScoutCompactionTests` | Keeping only the retry of an ineffective action; dropping rejected, never-dispatched, and unobserved records and toggles switched back; turning a scroll into a reveal hint |
| `DemoReplayTests` | One in-order replay with highlights; resuming without repeating an action; not re-clicking a toggle already in its recorded state; recognizing another step's screen; skipping a missing highlight live; healing a renamed control and keeping the heal after a check; returning to the start page in the same tab without a model |
| `DemoMatchingTests` | Stable and data labels; container-scoped label matching; ambiguity without a container unless one match is clearly nearest; data rows by visual order, and only near where they were recorded; unlabelled icon buttons found where they were and only inside their container; refusing a target crowded by look-alikes when it's recorded; reading order by visual rows; captions matched by their words and values by position; count badges that keep a control's identity and generated IDs that are ignored; identifiers over labels; screen signatures before and after confirmation; fingerprints that ignore words and timing but not actions or app version |
| `AXSnapshotBuilderTests` | Walking web content, naming rows from their text, and never exposing field values |
| `DemoModelClientTests` | Scout request shape (auto tool choice, strict schemas, fallbacks, stable bytes for caching); reading the tool call after thinking blocks and computing cost; prose without a tool call, refusals, and overload retries; script requests that list every step and accept only a complete answer; a start label in both answers, required by both tool schemas, with a missing one still finishing; billing each fallback attempt at its own model's rates |
| `DemoSessionTests` | Build, return to start, test, ready, and play, then restore after relaunch, keeping the script written during the test run without undoing the result; playing from the wrong screen going back to the start first; Previous Step going back to the start, quietly replaying the actions before it, and presenting it again; continuing a paused test run where it stopped and still ending tested; stopping a build and offering to keep building; several demos per app (open one, start another, cancel back, delete one); a new demo's request surviving a relaunch, with Cancel going back to the demo before it; ideas from the app's own features in the request field with Claude access; editing a line keeping the demo tested and timing the step to the new line; renaming keeping the phase and **Tested** across a relaunch; Claude's start label landing unless the presenter edited it meanwhile; demos saved without a start label still loading with the same fingerprint; the start label falling back to the first clause of the start description (“the Scheduled page”); Claude access asked once, on first open, for every app, before touching any |
| `DemoPanelContentTests` | What the demo panel shows in every state, from composing through building, approval, a blocked request, going back to the start, not at the start, ready, testing, presenting, paused, off track, and finished: glyph, headline, subline, primary action and its role, secondaries, transport enablement, and body; VoiceOver announcements on phase changes only; short titles for narrow widths; the Demo menu's first item and the floating demo button in each phase; library row status; and how many grid columns and steps fit each width |
| `ScriptFollowerTests` | Following a line read aloud word by word, including partial words; tolerating misheard words and swallowed endings; not jumping ahead on an ad-lib that shares one word with a later sentence; never moving backwards on a repeated word; Skip marking the line said |
| `PresenterPacingTests` | A line always getting at least the time it takes to say it; Follow my voice on by default, falling back to the timer without a listening microphone, and Skip ending a timed hold early; short words matched exactly and no jump without the words it skips; following the voice, a line holding with no timer until it's said; a step without a line moving on by itself after a short beat; a line said in your own words, then a pause, moving on, while a short aside doesn't count; “next” read as a word of the line not counting as a command |
| `DemoActionPolicyTests` | Ordinary navigation; destructive buttons denied and destructive navigation needing approval; localized destructive buttons; dialog buttons other than dismissals needing approval; data rows judged by their details; typing rules, including denied line breaks and tabs; allowed page hosts, matched exactly or as subdomains rather than as substrings |

`ZZViewSnapshots` renders the demo panel's states to PNGs for design review, at
real panel widths in Dark and Light. It draws only when `SNAPSHOT_DIR` is set
(`SNAPSHOT_WIDTHS` picks the widths, each the window width minus 100) and
otherwise passes without drawing.

Live end-to-end validation of the pipeline is ongoing. A 10-step Ledger
demo has been tested and played live once. Voice following, the teleprompter's
placement under the camera and its exclusion from screen sharing, switching
between several demos of one app (the library list, New Demo, renaming, and
deleting), the demo panel's composer, status band, and step grid, ideas from the app's own features, the
one-time Claude access question, closing a stray window during a build, Previous
Step and Start Over, the stage glow, the eight-slot floating widget, and the
window toolbar have not yet been validated live, and results from the previous
planner do not carry over. Until the checklist
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
   test run ends with **Tested**. Play at 2× and 1×. In Zen, if the page isn't
   exposed, the demo panel must show the `accessibility.force_disabled` guidance
   instead of acting.
2. **Ledger.** Ask to open Transactions, open the first transaction's details,
   and show discreet mode. The first row must be found by position, not by its
   amount or date. If the build turns discreet mode on, it must turn it back off
   before finishing, and Go to Start must restore the start item and toggles,
   leaving discreet mode as it was before the build.
3. **Blocked request.** In Dia, ask to make the theme blue. The build must stop
   with a reason and the closest real alternative without changing any setting.
   The subline names the alternative; **Build Alternative** returns to the
   start and rebuilds with it, and **Edit Request** returns to the composer.
4. **Presenter input.** During a build, a test run, and a presentation, click
   inside the source window: each pauses with the mouse-or-keyboard message, and
   resuming does not repeat a dispatched action. A test run paused this way must
   resume where it stopped and still end with **Tested**. Clicking or
   scrolling in BetterMeets, the meeting app, or another app, or bringing another
   app to the front, must not pause. Pause Demo and Pause Stage stay separate.
5. **Go to Start.** After a demo finishes, **Go to Start** (in the open demo's
   right-click menu or the Demo menu) reaches the start without an AI request; in a browser it uses the Back button without
   bringing the browser forward. Move the app elsewhere by hand and press
   **Play**: BetterMeets goes back to the start, then plays from the top. Where
   it can't return on its own, the demo panel shows **Not at the start** with
   **I’m There**, then returns to ready once you reach the start by hand. The
   floating widget offers **Go to Start** while the demo panel shows **Not at the
   start**.
6. **Wrong-screen recovery.** Pause a tested demo, open a later step's screen
   by hand, and resume: the demo panel offers **Continue from Step N**. Hide a
   highlighted element: a live presentation skips that highlight with a notice
   and keeps going. Rename a clicked control: **Test Again** relocates it or
   reports it missing, while a live presentation stops at that step instead of
   relocating it.
7. **Approvals and policy.** Ask to type text that isn't in the request, or to
   open a site the request doesn't name: the build pauses with **Allow** and
   **Skip**. A request that needs a Delete or Send button must highlight it, not
   click it. A confirming button in a dialog asks first; Cancel or Close doesn't.
8. **Script writing.** After a build, the demo panel shows **Writing lines…**
   while the test run plays, and it still ends with **Tested**. In
   **Edit Demo…**, choose **Rewrite Lines** with each tone
   (Conversational, Concise, Technical), with and without audience notes: each
   rewrite gives an opening line, a line and a distinct title of two to four
   words (at most 20 characters) for every step, including navigation steps, a
   closing line, and a short **Starts on** label, and the demo stays **Tested**. Start a rewrite, then change one step's line in the same
   sheet while Claude writes: that line keeps your edit and the others take the
   new lines. Rewrite offline: the reason appears in the sheet and the lines
   stay.
9. **Teleprompter.** Play a tested demo: the teleprompter opens without taking
   focus, centered just below the menu bar on the display with the camera
   (the built-in display, also when an external display is main), and shows
   the opening line, then each step's line with the next step's title, a
   **Listening** label while it waits for your voice, and a progress bar during
   timed holds. Pause and resume: the opening line must not play again.
   Change the text size, drag the panel, then hide and show it with the demo panel's
   **Teleprompter** toggle and ⌃⌘N; it returns where it was, and **Move Under
   Camera** puts it back. Its Pause, Next Line, and Play buttons and its menu
   must work without activating BetterMeets, and VoiceOver must read them as
   Start Over, Previous Step, Pause Demo (or Play, Resume Demo, Try Again, or Play
   Again), and Next Line. Share the BetterMeets window in
   Google Meet and confirm from another participant's view that the panel isn't
   shown; then share the entire screen and record whether macOS hides it.
10. **Follow my voice.** With it on (the default), finish a build: macOS asks
    for the microphone when the demo becomes ready, not on Play. While
    presenting, the demo panel's headline shows a waveform beside **Step N of M**,
    the Pacing and Demo menus have no Speed, and Settings › Demos shows Speed
    disabled with an explanation. Present while Google Meet uses the same
    microphone; spoken words dim, the next word is highlighted, and each step
    moves on a beat after its line is said. Say a line in your own words and
    pause: the demo moves on; a short aside doesn't. Stay silent on one line:
    the demo keeps waiting, with no timer. A step without a line moves on after
    a short beat. Say “next” and pause: the demo moves on. Read a line that
    contains “next” as a word: the demo follows the line and doesn't skip it.
    Let Meet adjust the microphone mid-line, and connect AirPods mid-demo:
    listening continues and the demo doesn't advance on its own. **Next Line**
    in the teleprompter and the demo panel, ⌃⌘→, and a presentation remote (Right
    Arrow, Page Down, or Space while BetterMeets is in front) all move on. With
    the microphone denied, the demo plays on its timers. Turn Follow my voice
    off: playback is timed again, Speed returns to the menus and Settings ›
    Demos, ⌃⌘→ ends a timed hold, and at 2× lines still get their full speaking
    time. The other participants must still hear you, and listening must stop
    when the demo finishes.
11. **Several demos.** Build two demos in one app. Each appears in the library
    list under **App Demos** with its status glyph (green seal when tested,
    dashed circle when not, orange pause circle while paused or while a build
    is paused, accent play while presenting); switch between them by clicking,
    with ↑ and ↓ while the list has focus, and with **Demo › Open Demo**, where
    the open one has a checkmark. Long titles are cut in the list and shown in
    full as the ready headline and the row's help tag. While a demo plays, the
    other rows are dimmed and can't be selected. **+ New Demo** (or ⌥⌘N) adds a
    selected **New demo** row and an empty request field and keeps both demos;
    **Cancel** on that row, Escape in the field, **−**, or selecting a saved demo
    returns to the demo that was open. Return on a built row renames it in place
    (Escape cancels, an empty name reverts) and a tested demo stays **Tested**;
    **Demo › Rename Demo…** does the same. **−**, Delete, right-click **Delete
    Demo…**, and **Demo › Delete Demo…** ask first and remove only that demo,
    and deleting the open demo opens the newest remaining one. Double-click,
    right-click **Edit Demo…**, **Edit Demo…** in the action bar, and **Demo ›
    Edit Demo…** open the sheet. In Stage Only, the Demo menu's **Edit Demo…**,
    **Rename Demo…**, and **Delete Demo…** are disabled. Use **Edit Request** on
    a paused third build: only that draft goes. Relaunch: the app reopens the
    demo it last had open. Start a new demo, type a request, and relaunch or
    switch apps and back: the request field reopens with your draft, and
    **Cancel** on the **New demo** row returns to the demo that was open before
    **New Demo**. Open another demo while **Rewrite Lines** is writing: the new
    lines land on the demo they were written for.
12. **Away from BetterMeets.** Start a build or **Test Again**, then switch to
    another app: when the demo is ready, BetterMeets comes to the front, or a
    notice with **Open BetterMeets** appears over that app. An approval or a
    stopped test run also shows a notice.
13. **Ideas.** With Claude access on and a key saved, open the request field
    for a live window: **Quick tour** and **Main flow** show at
    once, three **Finding ideas…** placeholders follow, then three sparkles
    ideas named after features the window really shows; hovering one shows its
    request, and choosing one fills the field without building. Switch to
    another app and back: the same ideas return without a new request (watch
    the log), and in a browser a different site gets its own. **More Ideas**
    asks again. At the minimum window width, Claude's ideas drop from the end
    and **More Ideas** stays; the row never scrolls. With Claude access off, only the two fixed ideas show.
14. **One-time Claude access.** Reset `demo.consentAnswered` and
    `demo.allowsAIControl.v2`, then open BetterMeets: the demo panel asks once,
    before any app is touched. **Not Now** hides it for good; **Build Demo**
    then asks again with **Allow and Build**. **Allow** turns on the Settings ›
    Demos checkbox and applies to every app, with no further question in a
    second app.
15. **Stray windows.** Ask for a demo whose obvious path opens a separate
    window (such as a preferences or new-document window): BetterMeets closes
    that window, the step doesn't appear in the demo, and the build continues
    another way, without a second real click. After three such windows, or a
    window without a close button, the build pauses with “… opened a new
    window. Close it and come back to … to resume.”
16. **Previous Step and Start Over.** While presenting, press **Previous Step**
    in the demo panel's transport, the teleprompter, the Demo menu, ⌃⌘←, Left
    Arrow, or Page Up: the
    teleprompter shows that step's line at once, the app goes back to the
    start, the earlier actions replay quickly without highlights or lines, and
    the step is presented again. Previous Step is disabled on the first step in
    the teleprompter. **Start Over** goes back to the start and plays from the
    opening line, also from the end of the demo.
17. **Demo panel.** At the minimum window width, the default size, and full
    screen, step a demo through every state. The panel stays 168 points tall
    while ready, building, testing, presenting, paused, off track, and
    finished, so Play, Pause, and Resume never move the stage; composing grows
    only for a request of two or three lines. The primary action stays at the
    trailing edge; at the minimum width the secondaries fold into a split
    button (**Continue from Step N** reads **From Step N**) while the transport
    and the primary stay. A long reason ends in **More**, which opens the full,
    selectable text. A demo with more steps than fit ends in **N more steps**,
    which opens **All N Steps**, and while presenting past the visible steps the
    current step takes that cell. With more demos than the list shows, the open
    demo stays in view. With VoiceOver, phase changes are announced and step
    changes aren't. Check Light, Dark, Increase Contrast, Reduce Motion, and an
    inactive window, where the primary turns grey but stays the largest control.

Also confirm, in any app: steps never act after a source switch or capture
pause; recovery buttons are disabled while the source isn't live; **Use N Steps**
tests a partial build; quitting mid-build reopens with **Resume Build**;
**Edit Demo…** keeps **Tested** after changing words, timing each edited step to
its new line, but clears it after removing an action, which also removes later
steps; an app update, or resizing a tested demo's window by enough to change its
100-point size step, shows **Not tested**. Without a key, **Build Demo** shows the
inline key row, **Save and Build** continues to the consent row while Claude
access is off, and **Allow and Build** turns on Claude access and builds. In Settings › Demos,
Return in the API-key field saves the key. In the composer, a **Try** idea
fills the request field without building, and the field's edge glows while it has
focus. While a build, a test run, or a return to the start drives the app, the
stage's edge glows and turns; with Reduce Motion it holds still, and Stage Only
never shows it.

For a demo spotlight or circle, pause, bring the source app to the front, and
compare it with the stage: the same region must be highlighted on both, and the
highlight must remain while paused. Switch away from the source and back; its
overlay must hide and then return without losing the cue. Return to the start or
clear the stage and check that it disappears. Check that a demo spotlight replaces an enabled manual spotlight
temporarily, then restores the manual effect without changing its setting. Key
badges also appear over the source; magnification is a stage camera effect.

Open **Edit Demo…** (or click a step in the step grid to open it there), inspect the
opening line, each step's line, and the closing line, and use **Copy Script**.
`Demos/ledger-transactions-script.txt` holds reference narration written for an
earlier Ledger demo; new builds generate their own scripts.

For app scoping, switch from an app with a demo to one without a demo. Only the
new app's composer should appear, without the previous app's steps or errors.
Switch back and verify its steps and script return. Build demos for both apps,
relaunch, and confirm both restore. **New Demo** must keep the selected app's
saved demos and leave the other app's alone. Repeat source switching in Stage Only, and verify pausing capture
preserves the selected app's demo while disabling playback.

### Debugging AI requests

On an HTTP failure, the demo panel shows Anthropic’s error message. **Copy Details**
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
existing lines. Idea requests appear with the tool `suggest_demos`; a failure
logs `Demo ideas failed` and leaves only the two fixed ideas. Speech recognition logs errors that stop it, failed speech-model
downloads, and restarts after the audio input changes, never what it heard. The log never contains response bodies, keys, prompts, or
screenshots. `DemoModelClientTests` covers response parsing,
refusals, and retries without calling the live API; error-body parsing and
redaction in `DemoRequestFailure` have no dedicated tests yet.
