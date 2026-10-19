# BetterMeets testing guide

BetterMeets keeps deterministic decisions in plain Swift and treats macOS
framework integration as an edge. Tests should follow the same boundary: cover
policies, geometry, persistence, state transitions, and AppKit configuration in
automation; verify privacy prompts and live window-server behavior with the
packaged app.

## Test layers

| Layer | Examples | Expected coverage |
| --- | --- | --- |
| Pure policy and geometry | shortcut reconciliation, capture selection and frame generations, window eligibility, auto-zoom camera and styled-frame transforms, normalized coordinates, stage sizing and workspace fitting, script following, teleprompter island layout, row breaking, and content | Every branch and boundary value |
| Persistence | presentation settings, shortcut pins and exclusions, corrupt or legacy data | Defaults, round trips, normalization, and invalid input |
| Main-actor models | annotation fading, spotlight state, armed presentation effects | State changes and cancellation-sensitive behavior |
| AppKit integration | overlay window levels, event-monitor ownership, native workspace configuration, workspace notifications | Configuration and callback translation that can run without privacy consent |
| Live macOS integration | ScreenCaptureKit, global mouse monitoring, Accessibility permission, Carbon hotkeys, meeting-app window capture, microphone and on-device speech recognition, Automation and browser scripting, borrowing the screen, and the window overlay over other apps' windows | Manual packaged-app verification |

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
   With an Apple Development certificate, or a self-signed "BetterMeets
   Development" code-signing certificate in the login keychain, which debug
   packaging picks up automatically, rebuild twice and confirm access
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
11. The main window has no title bar. It contains a full-height vertical source
    selector with the window's close, minimize, and zoom buttons centered in its top
    row and, beside it, a column with the header card, the stage, and a rounded demo
    panel. With no window chosen, the demo panel is hidden and the setup guidance
    fills the column below the header; choosing a window brings it back, and Clear
    Stage hides it again. The header card shows the app icon, name, state badge, and
    window title on the leading edge, and on the trailing edge the five effect
    toggles, Pause Stage, and Clear Stage; at narrow widths Pause and Clear drop
    their labels first. Drag the window by the source title, the header card's empty
    space, the rail's top row, and the gutters, and double-click each to confirm it
    follows System Settings › Desktop & Dock, including Fill. Hover the window
    buttons to see their glyphs, and confirm they stay in the rail without jumping
    while you drag a window edge, and keep working after resizing, full screen, and
    Stage Only. With the controls visible, share BetterMeets on its own in a meeting
    app and check that any sharing indicator macOS adds beside the buttons shows
    whole.
    The compact feature widget follows the selected source with the demo button
    (once the app has a demo), Pause Stage, Auto Polish, Spotlight, Annotations,
    Click Highlights, Keystrokes (with a permission badge while Accessibility is
    missing), and More with Clear Stage, Show BetterMeets, and Settings; it is
    shorter while the app has no demo. Check source selection, thumbnails,
    unavailable pins, hover/Space previews, context menus, Up/Down/Return, and
    Option–number shortcuts.
12. Toggle Stage Only from View or Control–Command–S. Confirm the sidebar, header
    card, demo panel, and window buttons disappear while capture continues. Escape
    and the same shortcut restore controls. Share BetterMeets in a meeting app and
    confirm that visible workspace controls appear only when the workspace is shown.
    The separate feature widget stays available beside the source in Stage Only.
    Move and resize the source, including near screen edges and on another display.
    Check right/left gutter placement, onscreen fallback, source switching,
    settings, and hiding when the source closes or any other app becomes frontmost.
    In particular, returning to BetterMeets must hide the widget over its workspace
    and Stage Only view. Show Source Tools must activate the source app, with the
    widget reappearing beside it. Its buttons and settings should preserve source
    focus.
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
    Reduce Motion, keyboard focus, and VoiceOver labels. The header card's controls
    and source list must remain readable and reachable at minimum window size.

Record the macOS version and meeting app when a manual result depends on
window-server or capture-framework behavior.

## Real-time demo checks

Demo tests run entirely against fakes. `FakeApp` implements `DemoDriving` as a
small screen graph, such as a Subtis-style movie search, and `ScriptedModel`
returns scripted tool decisions, a fixed script draft, and fixed ideas. No test calls a paid
API, takes a screenshot, listens to the microphone, or posts input to another
app: test sessions pass `opensWindows: false`, which never starts the listener,
and pacing tests feed words through the DEBUG-only
`SpeechListener.simulateHearing`. `FakeApp` screens can scroll: a screen with a
viewport moves its elements by its scroll position, clips their frames as
Chromium does when the engine is Chromium, and performs `AXScrollToVisible` the
way each engine does; elements can be sticky, and a screen can lose its
elements' identity across a scroll. A `FakeApp` can also show a spinner for a set
number of looks, keep showing the screen a click left for a set number of looks,
as an app slow to respond does, mark a label as borrowed, as an icon-only button's
is, give an element help text, put an element in the screen's dialog, say what
Accessibility's press and stand-ins delivered (sent, read back, or uncertain),
and have a stand-in deliver nothing and hand its commit back before the real key
goes out. The
demo suites contain 414 tests: 398 in the twenty-four
`MeetStageTests` demo and teleprompter suites, including
`DemoPanelContentTests` (52), `DemoSessionTests` (37), `DemoScoutTests` (36),
`BrowserScriptingTests` (30), `DemoReplayTests` (27), `IslandContentTests` (23),
`DemoInputRouteTests` (22), `DemoScreenLeaseTests` (20), `DemoFramingReplayTests` (19),
`DemoMatchingTests` (18), `DemoWindowOverlayTests` (16), `DemoModelClientTests` (14),
`DemoNoticeTests` (12), `IslandLayoutTests` (11), `ScoutCompactionTests` (10),
`ScoutObservationTests` (8), `AXSnapshotBuilderTests` (5), `ScoutCoverageTests` (3),
and `DemoTimingsTests` (2), and 16 in `DemoActionPolicyTests`. The full suite has
545 tests (524 in `MeetStageTests` and 21 in `MeetStageCoreTests`), with demos driven only by these
fakes, and no test sends an Apple Event to another app, runs a script in a real
browser, or moves the real pointer:

| Suite | Coverage |
| --- | --- |
| `DemoScoutTests` | Closing a separate window a click opened, leaving that click out, and building on; strips under 48 points across never counting as a window the demo opened; recording a search, a result, and highlights from what was on screen, with step titles and the start label capped at 32 characters; asking again about an unlisted element instead of inventing it, and reporting a blocked request; approval before typing text the presenter didn't write; an approval covering only the question the presenter answered; an app the presenter always allows answering an ordinary question without stopping and recording the approval, but still stopping for an unknown site; a dialog's button judged by that dialog's own text, never the page's; resolving a click on text inside a link to the link; never clicking destructive controls; refusing to repeat an ineffective action and stopping when stuck; keeping dispatched and dropping undispatched actions after an interruption; which route a click or key with no visible effect retries (the page's click, then a real click; the real key; nothing after real input or nothing to do) and what a retry that worked records; a settled look standing in for the next turn's only while the presenter did nothing since it began and the app's windows and frame are unchanged, saving a look on each turn after an action; settling waiting out a spinner the action started, never one already showing, and stopping at its cap; an icon button's borrowed label answering the unlabelled-control question, feeding denials, and keeping an approval saved for it unnamed; the scout clicking an icon button by its borrowed label without asking; a build's timings counting its turns, model calls, reused looks, each input's route, and the driver's waits for a pause; an unlisted element, typing into a button, and an address that can't open each asked again about the same look and facts with what was wrong, spending no turn and never counting toward the stuck limit while every reply is paid for; only one such retry per turn, after which the reply is rejected and spends the turn; denials stopping the build on their own after three in a row, never counting toward the stuck limit; a change Claude calls a wrong turn counting toward the stuck limit, with its verdict and cleaned reason kept on the record and the step still in the demo; facts reading `expected: … / observed: …`, with the expectation kept on the record, and Claude's cleaned target notes on clicked fields, buttons and a highlight's first target; a detour that came back to where it began left out of the demo, with every record kept for compiling again without pruning, unless the finish cites it; the first finish turned back once, with a fact, when an outline beat has no step, without counting toward the stuck limit; a finish turned back only once per build, and never on the last turn; a route that committed and delivered nothing handing the record back, so a pause before the real key drops it and one that goes on keeps it; a correction answered in prose rejecting the reply it corrected and spending the turn; a scroll or key Accessibility read back counting as done, never sent again, and never counting as stuck; input that may already have acted never sent again; while building, Add, Save, switch-named buttons, switches, a control whose help text creates, and an approved dialog button never sent again; a click the app shows late getting the effect window and a fresh look before any retry; a window that opened, the presenter's or not, stopping the retry; a retry that can't reach its target ending the retries, not the build |
| `ScoutCompactionTests` | Keeping only the retry of an ineffective action; dropping rejected, never-dispatched, and unobserved records and toggles switched back; turning a scroll into a reveal hint; scrolls joined into one hint keeping the real wheel any of them needed; cutting clicks that went somewhere and came back to the screen they left, while keeping them all without pruning, a round trip that never comes back, one the finish cites, and records saved before screens were recorded; keeping round trips that typed, toggled, clicked a switch-named button, needed approval, scrolled a target in, showed something, or held a contaminated click; cutting a lone click that showed nothing, never typing or a key; a wrong turn letting a round trip's screens match by their signatures only when those name an address or a selected item, never on its own; each compiled action saying whether it changed the screen; keeping a lone click that showed nothing when the finish cites it |
| `DemoReplayTests` | One in-order replay with highlights; resuming without repeating an action; not re-clicking a toggle already in its recorded state; recognizing another step's screen; skipping a missing highlight live; healing a renamed control and keeping the heal after a check; healing sending the target's recorded note and the healed target keeping it; returning to the start page in the same tab without a model; in an always-allowed app, a covered question the step's approval no longer matches passing, and an unknown site still stopping it; a control that ignores Accessibility's press clicked for real while building and on every replay; in a page that runs scripts, a press with no effect retried with the page's own click before a real one, testing starting from the route that worked (a real click where page scripts can't run) while playing keeps a real click; a key Accessibility carries out in an app's own views staying in the background; a key or a scroll Accessibility did with nothing to show retried once with real input, recorded on the step or reveal hint, and replayed straight with it; a real key with no effect never retried; a step waiting out a spinner the last step started, never one already there, and going on after half the gate's time; a demo saved when an icon button had no label still playing once the button borrows one; a replay's timings counting each step it ran and the route of each input; testing clicking a press that showed nothing once more, with the page's own click or else a real one, and keeping that route once the test passes, while playing presses once; a second click that shows nothing never followed by a third, and no route kept; an app too slow to show the first click getting it twice at most; checkboxes, switch-named buttons, Save, Add, and search buttons, approved steps, and steps that didn't change the screen or were built before never clicked again; going back to the start in the background clicking a silent Close button once more, never an anchor already selected, and the return before playing never; a new engine taking its first look as the last step's, so a spinner already there never holds it up; a test step handed back before its real key resuming at that step; testing never clicking again after a click that may already have acted |
| `DemoMatchingTests` | Stable and data labels; container-scoped label matching; ambiguity without a container unless one match is clearly nearest; data rows by visual order, and only near where they were recorded; unlabelled icon buttons found where they were and only inside their container; refusing a target crowded by look-alikes when it's recorded; reading order by visual rows; captions matched by their words and values by position; count badges that keep a control's identity and generated IDs that are ignored; identifiers over labels; screen signatures before and after confirmation; fingerprints that ignore words and timing but not actions or app version; an icon button saved unlabelled still found once it borrows a label, and new builds recording that label; a control's own label outranking the same words another borrows, the borrowing control recorded by position; signatures leaving borrowed labels out; a target's note never changing its identity, equality, hash, match, or the fingerprint, saved without a key when there's none, and demos saved before notes loading without one |
| `AXSnapshotBuilderTests` | Walking web content, naming rows from their text, and never exposing field values; the viewport a node in a page or a scroll area records, and none for window chrome; a dialog's own text kept for the policy, long lines included, and none for a dialog the limits cut off; a control with no label borrowing its help text, then an image's description (before its title), then its title element's text, asking for the title element only when nothing else names it, never replacing its own title, and never passing a borrowed label to the row around it; visible spinners, unfinished progress bars, and busy elements counted, ignoring finished bars and ones scrolled or placed out of view, and never listed |
| `DemoFramingTests` | Scrolling only a target its viewport cuts, never one in full view, outside any page or list, next to the browser's toolbar, or in two panes; a reveal first, then one exact scroll for a highlight only when the reveal moved nothing and its frame runs past the edge, never for one that only touches it; one exact scroll back for targets another's centering pushed out; a tall target's heading brought in, a low top scrolled in once, and a top in the upper half left there; exact scrolls that leave a margin and never push a target's top out; highlights kept inside the page, clear of its edge, the toolbar, and a sticky header; measuring a scroll from edges the viewport didn't clip, without a sticky header hiding it, and finding that header; an approved unnamed icon never clicked again while building |
| `DemoFramingReplayTests` | A section cut by the fold scrolled fully into view in the background before its highlight; the highlight taken once the scroll settled; a section taller than the view showing its top, in the background; a highlight starting below a sticky header; a sticky header, a sticky banner, the hero at the top, and the footer at the end never getting a real scroll; a heading and a cut button both shown; the last highlight cleared before scrolling; a scrolled-in highlight staying up a moment when its line was already said; targets in full view never scrolled, in a browser or a native list; a native control outside any scroll area highlighted in place; an exact scroll for a highlight past the edge, but not a click, when the app ignores scrolling into view; a target whose identity a scroll lost found again; scrolling for a step left out of the demo counted for the next; a resumed presentation keeping track of the scrolled page; a demo built before framing still finding a target by position after a highlight scrolled; building and replaying ending on the same scroll and highlight without a relocation; a later highlight recorded where an earlier one's scroll left it; building scrolling a cut button in before clicking it, without counting the scroll as the click's effect, and retrying a framed icon with a real click |
| `DemoModelClientTests` | Scout request shape (auto tool choice, strict schemas for all but finish and blocked, with no nested object but the highlight beats, fallbacks, stable bytes for caching); strict tools the API can't compile sent again without strict and kept that way, while any other bad request still fails; reading the tool call after thinking blocks and computing cost; prose without a tool call, refusals, and overload retries; script requests that list every step and accept only a complete answer; a start label in both answers, required by both tool schemas, with a missing one still finishing; billing each fallback attempt at its own model's rates; the tokens a reply and a failed call report, every fallback attempt added up, and thinking tokens only when the response itemizes them; every scout tool carrying `previous` with its five verdicts and a flat `previousReason`, actions carrying `expect`, and clicks, typing and highlight beats carrying `target`; decoding those, with a missing or unknown verdict as none; the executed facts sitting inside the untrusted block, where text spelling out the tag can't close it; a correction changing only the request's last block; `relocate` sending the recorded note quoted inside the untrusted block, and nothing when there's none; `finish` alone carrying `coverage` entries of a beat and its steps, decoded only from a finish, with a finish that has none leaving the beats unjudged; the system prompt telling Claude to act on BetterMeets' own verdicts in the facts, which authorize nothing, and that a first finish may come back once |
| `ScoutCoverageTests` | Every outline beat needing a step the demo keeps, a beat cited only by a step left out having none, the correction naming each beat that has none, and nothing judged when the reply didn't say; a request to show something needing a highlight; recognizing requests to show something in English, Spanish, Portuguese, French, German, Italian, Dutch, Japanese, Chinese, and Korean, and not ones that only do something or merely contain “show” or “tour” |
| `ScoutObservationTests` | The observed summary from two looks: a page change, a dialog or sheet opening and closing by its title or heading (or unnamed), the selected tab, option or row from and to, switches that flipped, new headings other than a dialog's title, the focused field, and elements added and removed without numeric text, as one capped line, and “the screen changed in place” when nothing names the change; target notes kept to one line of at most 120 characters without words holding a digit or an @, angle brackets, or straight quotes; expectations and reasons cut to their word limits; counting turns without change, rejections, and wrong turns toward the stuck limit and denials apart; drafts saved before expectations and verdicts loading; rows named by their place, and tabs, headings, dialogs, and fields whose labels read as data by their place or kind, never quoted |
| `DemoTimingsTests` | A run adding up its turns' model and settle time, model calls, tokens, waits for a pause, reused looks, and routes by name, `none` for nothing to do, into one summary line; a turn's line holding only numbers and route names, in milliseconds |
| `DemoSessionTests` | Build, return to start, test, ready, and play, then restore after relaunch, keeping the script written during the test run without undoing the result, with the compiled demo keeping the draft it came from; a click the test run had to click again keeping the route that worked once the test passes; playing from the wrong screen going back to the start first; Previous Step going back to the start, quietly replaying the actions before it, and presenting it again; continuing a paused test run where it stopped and still ending tested; stopping a build and offering to keep building; several demos per app (open one, start another, cancel back, delete one); a new demo's request surviving a relaunch, with Cancel going back to the demo before it; ideas from the app's own features in the request field with Claude access; editing a line keeping the demo tested and timing the step to the new line; renaming keeping the phase and **Tested** across a relaunch; Claude's start label landing unless the presenter edited it meanwhile; demos saved without a start label still loading with the same fingerprint; the start label falling back to the first clause of the start description (“the Scheduled page”); Claude access asked once, on first open, for every app, before touching any; Start Over and Play Again showing the opening line at once, not the closing line they leave; Previous Step keeping its step's line when the app can't get back to the start by itself, then catching up to it; going back again while catching up counting from the step it goes back to; a resume continuing to catch up quietly, with a line skipped meanwhile still said at the step; the session following the stage pausing and resuming; a build that finishes in the background leaving a ready notice without bringing BetterMeets forward, until playing ends it; building, testing, and going back to the start driving in the background, playing in front, and every run ending it; a step waiting for a pause showing in the panel only while a run is actuating, and a browser's tip showing once, until the next run, never again for that browser; a tip a notice covered offered again by the next run and remembered only once it shows; keys pausing a build or test only in the demo window itself, any key in its app while playing, and clicks counting by the window under them; no notice for a build that finishes while BetterMeets is active, even after switching away; Always Allow answering the question, building on, the next build in the app not asking, and the app staying trusted across a relaunch until removed, with approved steps kept; a build pausing before its next action while the Mac sleeps, raising no notice, waiting a moment after the wake, then going on by itself to a tested demo; a test paused by a switch to another user staying paused while the displays sleep after it, saying so, then going on from its step; a return to the start interrupted by sleep going again after the wake, then testing; a build the presenter paused staying paused through sleep and wake; presenting carrying on while the Mac sleeps; displays that wake to the lock screen leaving a build paused while secure input is on and going on once it ends, and secure input that never ends leaving an ordinary pause |
| `DemoPanelContentTests` | What the demo panel shows in every state, from composing through building, approval (with Always Allow in App only for questions trust covers), a blocked request, going back to the start, not at the start, ready, testing, presenting, paused, off track, and finished: glyph, headline, subline, primary action and its role, secondaries, transport enablement, and body; waiting for a pause (an hourglass and the waiting subline after the progress, with its shorter forms and help tag) and a browser tip in place of the ready facts, below a notice or a moved step; VoiceOver announcements on phase changes only; short titles for narrow widths; the Demo menu's first item and the floating demo button in each phase; library row status; and how many grid columns and steps fit each width |
| `DemoInputRouteTests` | Which routes each input tries, in order: presenting keeping Accessibility then real input in front; building in a page with JavaScript on (or not yet probed) scripting the page before borrowing the screen; pointer steps going straight to a real click; JavaScript off still opening addresses in the background; no scripting without Automation; native apps using Accessibility, with Return trying the field's confirm; browser chrome and unscriptable pages never getting page scripts or confirm; the drive mode for every phase; page roles mapped onto the policy's kinds; only Tab, Shift-Tab, Escape, Page Up, and Page Down going through page scripts, arrows always getting the real key; the tip a step's own access calls for, Automation turned down at the prompt included; the page's own click running only on controls the policy allows outright; each browser's tip and where its setting lives; in an app's own views, Escape, Up, Down, Page Up, Page Down, and scrolling trying Accessibility before borrowing the screen, never in a page or while presenting; typing trying the field's selected text after its value (and after a page script in a page), only in the background; a step's recorded route trimming its routes (the page's click falling to a real click without page scripts, real clicks, keys, and wheels going straight to them, presenting keeping real input); Up and Down staying inside a list; scroll-bar values converted from points, kept inside 0…1, and none at the edge; steps saved with `usesPointer` loading as needing a real click; reveal hints without a route saving the same bytes, so fingerprints hold; a dialog's button other than a dismissal falling to the real click instead of the page's |
| `DemoScreenLeaseTests` | Going at once while the person is away and giving their app the front back; waiting until they pause, counting again when they carry on, and adding up the time waited; input, lost focus, or another app taking the front before the commit putting everything back and trying again at the next pause, and nothing retried after the commit or for a step's own failure; the retry limit; cancelling while waiting without bringing anything forward; the pointer put back only when the step moved it and the person isn't moving it; leaving an app the person switched to alone; a window already in front neither raised nor put back, and another window of the same app given back; input while the window comes forward, and a raise that lands late still put back, at once and inside the borrowed moment while the person keeps typing; never starting while an app takes a password; giving up with `noPause`; a window that never gets focus, or an app that's gone; the demo's own posted input never making the next step wait; one step at a time |
| `BrowserScriptingTests` | Reading scripting definitions (Dia-like without bounds, Chrome-like with bounds, Safari through an include, no dialect, malformed); include path safety; matching windows by bounds, then title, then z-order, and failing closed on ambiguity; page addresses and arrival; error mapping and Automation permission; the `1+1` probe calling JavaScript off only when the browser says so; object specifiers and events built without sending; reply parsing; JSON escaping of every parameter; result decoding; and the fixed page script in JavaScriptCore against fake pages: refusing the wrong page, typing exactly at the point, refusing sensitive fields before reading them, click event order and label guard, implicit submission, scroll units, and Tab order |
| `DemoWindowOverlayTests` | The badge's corner, width, and too-small case; normalized points in the window; Quartz-to-AppKit frames on several displays; reading window-list entries; hiding when the window is closed, reused by another app, off screen, transparent, or empty; staying just above the window and over its sheets, but under another window of the same app in front of it; panel configuration and accessibility; badge states, hover, a click that doesn't take focus, and a VoiceOver press; pointer clamping and ripple expiry; following and hiding on a test-owned window; suspension during a borrowed moment and a detach while suspended |
| `ScriptFollowerTests` | Following a line read aloud word by word, including partial words; tolerating misheard words and swallowed endings; not jumping ahead on an ad-lib that shares one word with a later sentence; never moving backwards on a repeated word; Skip marking the line said; the last three words heard, starting empty on each new line and following revisions that change words without adding any; a line shown again counting as a new showing; words that change nothing on screen not redrawing the teleprompter |
| `PresenterPacingTests` | A line always getting at least the time it takes to say it; Follow my voice on by default, falling back to the timer without a listening microphone, and Skip ending a timed hold early; short words matched exactly and no jump without the words it skips; following the voice, a line holding with no timer until it's said; a step without a line moving on by itself after a short beat; a line said in your own words, then a pause, moving on, while a short aside doesn't count; “next” read as a word of the line not counting as a command |
| `IslandContentTests` | What the teleprompter island shows in every state: compact or expanded; the band's glyph, place, and Next, with Wrap up or Last step on the last step; the line's word style and dimming; the meter; the status, by priority; and four slots that never move: Play alone in ready, Go to Start as the primary when not at the start, Pause Demo between three disabled slots while going back, Resume Demo with Next Step when paused, Try Again with Skip Step beside it when a target is missing, and Play Again with Start Over disabled at the end; catching up after Previous Step; Done with a check only without a closing line |
| `IslandLayoutTests` | The island's frames on a notched display, with an auto-hidden menu bar, and on an external display without a notch; width and depth across text sizes 16 to 48; every size from 40 to 48 making the same largest island; row heights in the rounded script font; the collapsed, compact, and expanded shapes and the shoulders' path; whole-pixel frames; event-to-AppKit point conversion; the chrome at rest |
| `DemoNoticeTests` | What the demo notice says: a ready demo's title with Tested or Not tested, its steps (1 step, 4 steps), and its app, and the VoiceOver announcement; Build paused, Test waiting, and Test stopped with their titles and details; no notice for phases the presenter started or that need nothing. Whether it shows: nothing while BetterMeets is active, a new announcement replacing it in place, a phase without one hiding it, switching to BetterMeets hiding it, and a notice put away not returning until a new run. Where it hangs: from the notch and 300 points wider, below the menu bar at 440 points without a notch, and as a card 8 points below the teleprompter, as wide as its body |
| `ScriptRowsTests` | Breaking a line into rows at the column's width; a word wider than a row splitting into pieces that keep its index; an empty line as one row; a reading position that keeps a row above, only moves forward, and starts over when reset; a top fade only over a row already read |
| `LevelHistoryTests` | The meter's decibel scale; one level per twentieth of a second of audio, whatever the buffer size; drops releasing softly; reset |
| `DemoActionPolicyTests` | Ordinary navigation; destructive buttons denied and destructive navigation needing approval; localized destructive buttons; dialog buttons other than dismissals needing approval; data rows judged by their details; typing rules, including denied line breaks and tabs; allowed page hosts, matched exactly or as subdomains rather than as substrings; each question's kind and words; which kinds an always-allowed app answers, and denials staying denials; destructive words only at a word start (“Presets”, “Mistakes”), with prefixes, identifiers, and German compounds still caught; tabs, and links in plural or past forms, opening without asking while imperative links and menu items ask; a dialog's own text deciding only whether trust can answer |

`ZZViewSnapshots` renders the demo panel's states to PNGs for design review, at
real panel widths in Dark and Light, and the teleprompter island's states (18a
to 18m: ready, listening, timed, no line, paused, off track, going back,
finished, mic unavailable, compact, not at the start, no notch, and the largest
and smallest text) under a drawn menu bar and notch, at the island's width plus
164 points, and the demo notice (20a to 20f: ready, test stopped, build paused,
ready without a notch, under the expanded teleprompter, and a test waiting with a
two-line detail) the same way, plus a test waiting for a pause (13b) and a ready
demo with a browser tip (13c). It draws only when `SNAPSHOT_DIR` is set
(`SNAPSHOT_WIDTHS` picks the widths, each the window width minus 100) and
otherwise passes without drawing.

Live end-to-end validation of the pipeline is ongoing. A 10-step Ledger
demo has been tested and played live once. Voice following, the teleprompter
island (growing out of the notch, docking on each display, stepping aside for a
demo's clicks and scrolls, and its exclusion from screen sharing), switching
between several demos of one app (the library list, New Demo, renaming, and
deleting), the demo panel's composer, status band, and step grid, ideas from the app's own features, the
one-time Claude access question, closing a stray window during a build, Previous
Step and Start Over, the stage glow, the eight-slot floating widget, the
header card, Accessibility's stand-ins for keys and scrolling, typing through a
field's selected text, the page's own click as a build's retry, reusing a settled
look for the next turn, waiting on spinners, labels borrowed from help text,
images, and title elements, pausing while the Mac sleeps or is switched to
another user, the per-turn timings log, pruning detours and silent clicks, the
finish's coverage check, and testing's second click have not yet been validated live, and results from the previous
planner do not carry over. Until the checklist
below passes, treat real-time demos as not fully verified in real apps. Use a
demo account and an API key, and record the macOS version and each app's
version.

1. **Subtis in Dia and in Zen.** Ask for a search for “The Matrix” on Subtis,
   and stay in BetterMeets while it builds. Steps should appear live, with dashed
   outline beats ahead. With Allow JavaScript from Apple Events on in Dia, the
   browser must stay in the background for the whole build and test run,
   Return after the search included; with it off, and in Zen, it comes forward
   only at a pause, for well under a second, after which BetterMeets is active
   again (check 20). On the stage, the virtual cursor glides to each target and
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
9. **Teleprompter.** Play a tested demo: the teleprompter grows out of the
   camera notch without taking focus, on the display with the camera (the
   built-in display, also when an external display is main). Beside the camera
   it shows the position and step title and **Next** with the next step's title;
   below, the opening line, then each step's line, with **Listening** while it
   waits for your voice and a countdown during timed holds. Pause and resume:
   the opening line must not play again. During **Test Again** it is a compact
   strip as tall as the menu bar. Change the text size: it docks again at the
   new size, still centered on the camera; from 40 to 48 points it keeps its
   size and only the text changes. Hide and show it with its menu, the
   demo panel's **Teleprompter** toggle, and ⌃⌘N: it folds into the notch and
   grows back out. It can't be dragged or resized, and there is no **Move Under
   Camera**. Its buttons and menu must work on the first click without
   activating BetterMeets or taking the app's keystrokes, and VoiceOver must
   read them as Start Over, Previous Step, Pause Demo (or Play, Resume Demo, Try
   Again, or Play Again), and Next Line, with the same names as the demo panel.
   Share the BetterMeets window in Google Meet and confirm from another
   participant's view that the island isn't shown; then share the entire screen
   and record whether macOS hides it. Then run the island checks below.
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
    another app: when the demo is ready, BetterMeets stays in the background and
    a black notice grows out of the notch on the display under the pointer
    (below the menu bar without a notch), with the app's icon, the demo's title,
    “Tested · N steps · App”, **Open BetterMeets**, and Dismiss. It stays until
    acted on: **Open BetterMeets** brings BetterMeets forward and folds it away,
    Dismiss folds it away and it doesn't come back, and switching to BetterMeets
    any other way (Dock, ⌘-Tab) folds it too. An approval, a test waiting at the
    start, or a stopped test run shows Build paused, Test waiting, or Test
    stopped instead; when the test then carries on, that notice folds away, and
    if the run ends ready a Demo ready notice grows again. Put a Build paused
    notice away, choose **Keep Building**, switch back, and touch the app again:
    the notice returns. With Stage Only on, **Open BetterMeets** on Build paused
    shows the controls. With the teleprompter up, the notice is a card under it;
    **Larger Text** and **Smaller Text** from the island's options keep the card
    8 points below it and as wide as its body, and hiding the teleprompter moves
    the notice into the notch once the island has folded. Under the status pill,
    an attention card has no badge of its own. Press ⌘H on BetterMeets before a
    build finishes: the notice shows and BetterMeets stays hidden. Hovering
    Dismiss shows its help tag. With VoiceOver, the notice is announced as it
    appears, once.
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
    `demo.allowsAIControl.v2`, then open BetterMeets and choose a window of an app
    with no saved demos (or choose New Demo): the demo panel asks once, before
    Claude touches any app. **Not Now** hides it for good; **Build Demo**
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
18. **Sections below the fold.** In Dia, open a long landing page and scroll so
    a section such as “Key Features” starts in the lower third of the window and
    runs below the fold. Ask for a demo that highlights that section. While
    building, the page scrolls the whole section into view with the browser in
    the background (Chromium centers it), and only then does the highlight
    appear, never cut by the bottom edge or drawn over the toolbar. Test and
    play the demo from the same start: the page scrolls the same way and the
    highlight lands on the same region. Repeat with a section taller than the
    window: the page scrolls past it and back until its heading sits near the
    middle, all in the background, and the highlight runs from its top to just
    above the bottom edge, below a sticky header if the site has one. Highlight
    a heading together with a button cut by the fold: both end up inside, after
    one brief trip to the front. Highlight the hero at the top of the page, a
    sticky header while scrolled down, and the footer at the end of the page:
    nothing scrolls, Dia never comes to the front, and the pointer stays put.
    When one highlight follows another, the earlier one disappears before the
    page scrolls. Present with voice following and a short line on a cut
    section: the highlight stays up at least a moment after it appears. Pause
    after that highlight, then resume: a target found by position after it is
    still found. Click a button half below the fold: it scrolls in before the
    click. Repeat once in Chrome and in Safari (which
    stops a section at the edge instead of centering it; the highlight still
    stays inside), and in Finder or Notes with a row half cut by its list. A
    demo built before this change should still play, scrolling cut highlights
    in and still finding the targets after them. Log the before and after
    frames in Dia once, to confirm `AXScrollToVisible` centers and how long a
    smooth-scrolling page takes to settle. The Dock and the teleprompter can
    still cover part of the presenter's own view of the window; what must be
    right is the captured window.
19. **Always Allow.** In Dia, ask to “search a movie on subtis.io” without
    naming one. The approval to type the title Claude picked offers **Skip**,
    **Always Allow in Dia**, and **Allow**; choose **Always Allow in Dia**: the
    build goes on, Settings › Demos lists Dia with its icon under **Always
    allowed**, and a second such build doesn't ask. A cookie banner's Accept,
    or an add-item dialog's Save, passes without asking only when the dialog's
    own text sounds harmless. Opening a site the request doesn't name, Return in
    a chat or comment field, a menu item such as Delete, and OK in a “Delete this
    …?” dialog still ask, with only Skip and Allow. Links such as
    **Transfers** or **Approved** and tabs such as **Deleted** no longer ask,
    and buttons such as **Presets** are no longer refused. Remove Dia in
    Settings › Demos: the next build asks again, and the tested demo still plays.

20. **Keep working while it builds.** Build and test in Dia with Allow
    JavaScript from Apple Events on (in Dia's Developer menu; View › Developer in
    Chrome) while typing in TextEdit: the build never takes the screen, TextEdit
    keeps every keystroke, the badge sits over Dia's window buttons, and the
    demo's arrow moves inside Dia while the real pointer stays put. The first
    Build in a browser shows macOS's Automation question while BetterMeets is in
    front; Don't Allow falls back to borrowing the screen, and the ready demo
    shows the Automation tip once. Turn the JavaScript setting off and build
    again: the panel and the badge say **Waiting for a pause** while you type,
    the step goes once you stop for 1.5 seconds, and TextEdit, its window, and
    the pointer come back where they were; the ready demo shows the JavaScript
    tip once, and not after the next build. Type again just as the window comes
    forward: it goes back to TextEdit and the step runs at the next pause, never
    twice. Build in Ledger Wallet while typing in another app: clicks
    Accessibility can't do and key steps wait for a pause the same way. Move and
    resize the driven window, minimize it, switch Spaces, and cover it with
    another app's window: the badge and arrow follow it, hide with it, and stay
    under the covering window, never above everything. Hover the badge with
    BetterMeets in the background: it shows **BetterMeets is building** (or
    testing, or going back to the start); click it: BetterMeets comes forward.
    Click inside the driven window yourself: the build pauses as before. Open a
    second Dia window over most of the driven one (not the exact same frame,
    which Accessibility can't tell apart), and type an address and a search
    there while it builds: the build keeps going,
    the badge and arrow stay under your window, web steps stay in the
    background, and a window you open with File › New Window stays open. Stop
    typing partway through a password in a Keychain prompt: no step borrows the
    screen until the prompt closes. Keep typing in TextEdit with JavaScript off
    through eight borrowed tries: the build pauses with **This step needs Dia in
    front for a moment…**. Play:
    no badge, no waiting, and the app comes to the front. Share the stage in a
    meeting: the badge and arrow never appear in the captured window.
21. **Keys, scrolling, and typing without the screen.** While typing in TextEdit,
    build in Finder (list view) a demo that selects a file with Down, scrolls the
    list with Page Down, and opens and closes a sheet or dialog with Escape:
    Finder never comes forward and nothing waits for a pause; Down on the last
    row and Page Down at the end do nothing and still don't borrow the screen. Do
    the same in Notes or Mail's message list and in a Settings-like sheet whose
    Cancel button Escape presses. With a second Finder window in front holding
    focus, Escape and Down borrow the screen for the demo window instead of
    acting on yours. Build in an app whose list ignores Accessibility's selection
    or scroll bar: the build borrows the screen for the real ↓ key (or real
    scrolling) once, never also after a selection or bar that did move. For a
    sheet that ignores Accessibility's cancel, the panel shows “Trying the real
    esc key”, the build borrows the screen for it once, and the test run borrows
    for that step straight away, once. Tab, Shift-Tab, Left, and Right in a
    native app still borrow. In an Electron app (Slack, Notion, or VS Code) with
    a search or text field that ignores its Accessibility value, typing lands in
    the background through the field's selected text, replacing what was there,
    and the clipboard is unchanged; a password field still never takes typing
    that way. In Dia with Allow JavaScript from Apple Events on, a control whose
    press does nothing (a popup that closes while its window isn't focused) is
    retried with the page's own click in the background before any real click,
    and the test run does the same; with the setting off, the test run borrows
    for a real click. Play every one of these demos: keys, clicks, and scrolling
    bring the app forward and use real input, as before. In Accessibility
    Inspector, confirm each list or scroll area used lists `AXSelectedRows` or a
    vertical scroll bar whose value is settable.
22. **Spinners and icon-only controls.** In Accessibility Inspector, find an
    icon-only toolbar button with only a tooltip (`AXHelp`), say in Mail or
    Preview, and a checkbox whose caption is separate text (`AXTitleUIElement`)
    in an app's Settings. Build a demo that clicks both: the build never stops
    for “Click an unlabelled control?”, the step list and facts name them by the
    tooltip and caption, and Test Again finds them. A demo built and tested
    before this change that clicks such a button, with its unlabelled question
    approved, still passes Test Again and plays without asking again. A
    destructive tooltip (“Delete”) is still never clicked. Build in a site whose
    search shows a spinner before its results (or one throttled in Dia's
    developer tools): the step after the search waits until the spinner goes,
    while building and in the test run, and in Play a spinner that never stops
    holds a step no longer than half its wait. In Accessibility Inspector, check
    whether an idle app keeps a stopped `AXBusyIndicator` or a finished
    `AXProgressIndicator` listed; with one there, steps never wait on it. In a
    window with a large tree (Mail with a long list), a build's turns after an
    action go from **Looking at the screen** to **Deciding what's next** almost
    at once while you touch nothing, and take a fresh look, visibly longer,
    after you click or type outside BetterMeets or move the window.
23. **Sleep and switching users.** Start a build in Dia with a long request,
    then put the displays to sleep (`pmset displaysleepnow` in Terminal). In
    another Terminal, stream the `demos` and `demo-timings` categories
    (Debugging AI requests, below): no Anthropic request or step is logged
    while the displays are dark. With **Require password after screen saver
    begins or display is turned off** set to Immediately, wake the Mac and wait
    at the lock screen for ten seconds before signing in: nothing is logged
    while the lock screen shows (if a step or request appears there, the lock
    screen's password field didn't hold secure input on this macOS, so note it).
    After signing in the panel says **Paused while your Mac sleeps. The build
    goes on once it wakes.**, no notice hangs from the notch, and about two
    seconds later the build carries on from the current screen without
    repeating the step it was on. Turn on Terminal's **Secure Keyboard Entry**,
    sleep and wake again: after two minutes the build reads **Build paused.**
    and waits for Resume. Do the
    same during **Test Again**, and while it is **Going to the start** before a
    test; the test goes on from the step it paused at. With Fast User Switching
    on, switch to another user mid-build and back: the reason reads **Paused
    while you’re switched to another user…** and it goes on once you're back.
    Pause a build yourself, sleep and wake: it stays paused. Play a demo and let
    the displays sleep: the presentation isn't paused by it. Lock the screen
    without letting the displays sleep and note what the build does: macOS
    doesn't announce the lock publicly, so it keeps going, and record whether
    any step borrowed the screen while locked.
24. **Timings log.** Stream `category == "demo-timings"` while building, testing,
    and playing. Each build turn logs one `build turn=N action=…` line with
    `model=`, `in=`/`out=`/`cacheRead=` (and `think=` when the API itemizes it),
    `walk=`, `nodes=`, `reused=`, `settle=`, `polls=`, `pauseWait=`, and
    `routes=`; the turns after an action you didn't touch show `reused=true`, a
    step that borrowed the screen shows a nonzero `pauseWait=` and
    `borrowedScreen` among its routes, and every build ends with one `build ended
    turns=…` line whose route counts match the turns. Test runs and plays log
    `test step=…` or `play step=…` lines with an outcome, then `test ended` or
    `play ended`. Search the lines for the request, typed text, a step title, a
    label, and the page's address: none appear, and Console shows the lines
    without `<private>`.
25. **Expect, then check.** In Dia, build “Open settings and show the theme
    option” on a site whose settings sit behind an icon-only gear. Pause after
    three or four steps and print the draft:
    `defaults export com.lndgalante.bettermeets - | python3 -c 'import json,
    plistlib, sys; [print(json.dumps(json.loads(d), indent=1,
    ensure_ascii=False)) for d in plistlib.load(sys.stdin.buffer)["demo.library.v2"]]'`.
    Each action's `fact` reads `→ expected: … / observed: …`, and the
    observation matches what happened on screen (the page, a dialog's title,
    the tab it moved to, a new heading, how many elements came and went); its
    `expected` holds Claude's words, earlier actions carry a `judgement`
    that fits what you saw, and the first locator of each click, typing, and
    highlight has a `note` describing the control's look and place with no
    digits, names, or addresses. Resume, then ask in a new build for something
    only a destructive control does (“delete my account”): it stops with
    **Stopped because Claude kept choosing actions BetterMeets won’t do.**, never
    with “didn’t get the demo anywhere”. In the `demos` log, a reply that named an
    unlisted element logs “asking again about the same screen” and a second
    request whose `cacheRead=` isn't zero, and that turn's `demo-timings` line
    shows `calls=2`. Finally, change the gear's tooltip or the
    window's width enough to move it, run **Test Again**, and confirm the
    `relocate` request finds it; note whether Claude's verdicts (`wrong_turn`
    after a click that opened the wrong panel) ever disagree with the screen.
26. **Detours, coverage, and second clicks.** In Ledger, build “Show the
    balance of my first account” and, if Claude doesn't wander by itself, approve
    nothing and watch the grid: when it opens another tab or page and comes back
    to the screen it left before highlighting, those steps leave the grid, the
    finished demo has none of them, and the exported draft (the command in check
    25) still lists them under `compiledFrom.records`, each action with a
    `screen`. A tab Claude opened and showed something on stays. Build a request
    whose outline has a beat Claude skips, or ask to show something and stop it
    from highlighting anything: the first finish comes back with a `rejected
    finish:` fact, Claude takes at least one more turn, and a second finish ends
    the build even if the gap remains. Then, in an Electron app or a page with a
    control that ignores Accessibility's press while the window is in the
    background (a menu or a popover trigger), build a demo that clicks it with
    the window in front, so the build records Accessibility, then **Test Again**
    with the window in the background: after about a second the panel reads
    “Step N of M: Trying another click on …” (or “Trying a real click on …”), the
    control opens once, the test passes, and the exported demo's step now has
    `"route" : "pageScript"` (or `"pointer"`). Confirm a Save, Add, or Search
    button and a switch are never clicked twice, even when the app is slow, that
    a slow-loading page's link gets at most two clicks, and that **Play** still
    presses each step once with the app in front. While building, with the
    window in the background, ask Claude to add one item in a web app whose Add
    button answers slowly (throttle the network in the developer tools): one
    item appears, never two, and the build never shows “Trying another click on
    Add”. Click a toolbar button that opens a separate window (Mail's New
    Message) while you type in another app: one window opens and BetterMeets
    never clicks again. In a page with a modal dialog, have Claude click its
    Continue: the build asks first, and after Allow the click goes out as a
    borrowed real click, not the page's. Export the draft (check 25): a fact for
    a click that selected a row reads `row N selected`, never the row's text.
27. **Text views and keys Accessibility reads back.** In Notes or TextEdit,
    open a document several screens long and build “Scroll to the end of this
    note and show the last paragraph” with the window in the background: each
    scroll moves the text once (count the paragraphs that pass), the panel never
    says “Trying real scrolling”, the facts read `scrolled down → more content
    is visible`, and the build doesn't stop as stuck. Test it: the text ends
    where the build left it. Do the same with Page Down. In a list or table,
    Down moves the selection one row, never two.

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

### Teleprompter island

The island's layout and content are unit-tested, but how it docks, morphs, and
steps aside depends on the window server. With `./dev-app.sh`, check:

1. **Notched built-in display.** The island grows from the notch with no
   overhang, its band merges with the notch, and the menus and status items it
   covered reappear after Hide.
2. **First click.** With Safari in front, the first click on **Pause Demo**
   acts, and typing afterwards still goes to Safari. The options menu and the
   island's context menu both open.
3. **Replay safety.** With Safari maximized, play a demo with a click on the
   address bar and a scroll under the island: both steps pass, and the island
   blinks out and back.
4. **⌃⌘N while folding.** With BetterMeets in front, press ⌃⌘N twice quickly:
   the island grows back from where it was and stays, with no stray hide.
5. **Notices.** With the island showing, the notice for a test run that finishes
   in the background slides out as a card 8 points below it. Hide the island
   while the notice is up: the notice moves up into the notch, and back below
   the island when it shows again.
6. **Displays.** With the lid closed and an external display, the island hangs
   below that display's menu bar. With an external display as main and the lid
   open, it stays on the built-in display. Also check an auto-hidden menu bar,
   a full-screen source app, Mission Control and swiping between Spaces, Stage
   Manager, unplugging a display mid-demo, and changing the display scale: the
   island always docks at the camera.
7. **Whole-screen share in Meet.** Expect the island to be visible, as the
   caption in Settings › Demos warns; sharing the BetterMeets window should hide
   it.
8. **Accessibility.** VoiceOver reads Teleprompter, then the place, Next,
   Current line, the status, and the controls. With Reduce Motion the island
   fades instead of growing, its rows snap, and the meter stays flat. Increase
   Contrast raises the faint text and adds an edge on the sides and bottom.

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

For where each build turn and replay step spends its time, stream
`category == "demo-timings"` instead (both together with
`category IN {"demos", "demo-timings"}`).

The log contains request metadata (model, stop reason, tool name, latency,
estimated cost, token counts, and, on failure, status, error type, and request
ID) plus
pauses, heals, and focus-check failures. Script requests appear with the tool
`write_script`; a failed rewrite logs `Script rewrite failed` and keeps the
existing lines. Idea requests appear with the tool `suggest_demos`; a failure
logs `Demo ideas failed` and leaves only the two fixed ideas. Speech recognition logs errors that stop it, failed speech-model
downloads, and restarts after the audio input changes, never what it heard. The log never contains response bodies, keys, prompts, or
screenshots. `DemoModelClientTests` covers response parsing,
refusals, and retries without calling the live API; error-body parsing and
redaction in `DemoRequestFailure` have no dedicated tests yet.
