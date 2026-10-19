# BetterMeets security and distribution model

BetterMeets is a directly distributed macOS utility. It does not enable App
Sandbox because it combines ScreenCaptureKit window capture with global mouse
and keyboard observation. Reassess sandbox feasibility before App Store distribution.

The hardened runtime is enabled for packaged builds. Certificate-signed releases
retain library validation. Local ad-hoc packages disable library validation so a
teamless build can load the embedded Sparkle framework. The shipping entitlement
file contains `com.apple.security.device.audio-input`, which the hardened
runtime requires for Follow my voice to hear the microphone, and
`com.apple.security.automation.apple-events`, which it requires for demos to
script browsers with Apple Events; the development file adds the
library-validation exception. Neither grants input-synthesis capabilities, and
Info.plist explains Apple Events in `NSAppleEventsUsageDescription`. CI asserts that the release app carries the audio-input
entitlement and `NSMicrophoneUsageDescription`.

## Permissions and capture

- Screen Recording is checked without prompting at launch and requested through
  the sidebar's Allow Access action.
- Keystroke highlighting requests Accessibility when the user enables it.
- Real-time demos use Accessibility to read the selected window and to operate
  it in the background, without bringing the app to the front: clicks use the
  element's press action, typing sets a field's value or, for a field that
  ignores it, selects the field's text and replaces the selection (never in a
  secure field, never through the clipboard), and scrolling asks an element to
  scroll into view or sets a native scroll area's scroll bar. In the app's own
  views, outside any page, Escape (the element's or sheet's cancel action, or
  the window's cancel button, whose label the policy's denials judge first like
  a click's), Up and Down in a list, and Page Up and Page Down use Accessibility
  too, only in the demo window or a sheet on it, and only through actions an
  element lists and attributes it reports settable. Every input is bound to the
  selected source window and its process. Before a click, BetterMeets hit-tests the target
  within the app, stops when another of the app's controls covers it, and
  re-checks the policy's denials against the element actually there, by its
  title, description, or else help text. Another of
  the app's document windows over the target, like one the person is using,
  doesn't stop a background press, which reaches the element itself, and pages
  and focus are read only from the demo window. Other key steps,
  Return after typing, browser navigation, controls that refuse Accessibility
  actions, and keys and scrolling Accessibility can't do bring the source app
  forward briefly; once Accessibility did a key or a scroll, the real one is
  never sent as well, except for a build's one retry when Accessibility read
  nothing back (Escape's cancel) and the screen showed no change. A scroll bar
  or list selection Accessibility read back as moved counts as done, and input
  that may have acted (Accessibility timed out, or a page script failed after
  touching the page) is never sent again by another route, while building or
  testing. While building, a click that showed nothing is tried on the next
  route only once 1.2 seconds have passed and a fresh look still shows nothing,
  never once a window of the app opened, and never for a switch, a control
  whose words save, submit, or add, or a click the presenter approved. While testing, and going back to the start in the background, a click
  that should change the screen and showed nothing within 1.2 seconds is clicked
  once more on the next route (the page's own click, else a borrowed real one),
  never twice, never on a switch, a control whose words save, submit, add,
  search, or go on, or an approved step, and only after finding the target again
  and checking the policy and the hit test again; playing never does. While building and testing, that happens only at a pause: BetterMeets
  waits until the person has left the keyboard and pointer alone for 1.5
  seconds, brings the window forward with public activation and Accessibility
  (`kAXRaiseAction`, `kAXFrontmostAttribute`), and afterwards warps the pointer
  back unless the person moved it and gives the front back to their app unless
  they switched elsewhere. Input from the person before the step's irreversible
  point puts things back and retries the step at the next pause; input after it
  can't be taken back, and keys typed during that moment reach the source app.
  A pause never counts while an app has secure keyboard entry on
  (`IsSecureEventInputEnabled()`, as when the person stops partway through a
  password), so the rest of a password can't go to a page in the demo window.
  When the person comes back while the window is still coming forward,
  BetterMeets waits for it to arrive and gives their app the front back at once.
  After eight interrupted tries the run pauses and says so.
  To tell pauses apart, BetterMeets watches keyboard and pointer events only
  while a step waits or runs, keeping only whether each was a key or the pointer
  and when, never which key or where, and reads the system's idle time; nothing
  is stored or logged. While presenting, the app comes forward at once. Either
  way the fallback requires exact focus on the source window, stops if the app
  loses the front, and asks for BetterMeets to become active again afterwards if
  it was. Fallback clicks are hit-tested system-wide and must hit the source
  process, and the policy's denials are checked again against the element the
  system hit test finds right before the click, since the wait for a pause has
  no end. Keyboard events
  are posted only to the source process, so a focus change cannot send
  keystrokes to the meeting app, and Return goes only to the field the step
  typed into. Synthetic events come from a private event source with explicit
  modifier flags and an identifying tag. Pointer travel and typing can be
  cancelled; a posted mouse-down always gets its mouse-up and every key-down its
  key-up. Text with line breaks, tabs, or control characters is never typed.
  Browser navigation accepts only HTTP/HTTPS URLs without embedded credentials
  and types them into the same tab's address bar after confirming that the
  address bar, not the page, has focus.
- A build or test run pauses while the Mac's displays sleep or the person is
  switched to another user, so no screenshot, Claude request, or action happens
  while nobody can see the Mac, and the screen is never borrowed then. Only
  `NSWorkspace`'s documented sleep, wake, and session notifications are used.
  macOS has no public notification for the screen locking, so a locked screen
  whose displays are still awake doesn't pause a run; the lease still waits for
  the person to pause and never starts while secure keyboard entry is on.
  Displays can also wake to the lock screen, which posts nothing either, so a
  paused run waits while secure keyboard entry is on
  (`IsSecureEventInputEnabled()`, which the lock screen's password field
  holds), and after two minutes of it stays paused for the presenter instead.
  The run goes on by itself about two seconds after that ends, from a fresh
  look, and only if this pause stopped it; presenting is never paused this way.
- While building and testing in a browser whose scripting supports it (Dia,
  Chrome, and other Chromium browsers with `execute javascript`, and Safari),
  BetterMeets drives the tab through Apple Events, which need the Automation
  permission for that browser. macOS asks once, when Build or Test starts with
  BetterMeets in front; events never prompt by themselves, and a denied
  permission falls back to the steps above and shows where to allow it.
  Opening an address sets the demo tab's URL property, only for HTTP/HTTPS
  addresses without credentials. Web steps run JavaScript in the tab only when
  the person has turned on the browser's Allow JavaScript from Apple Events.
  That setting is the browser's own and is a trade-off: while it's on, any app
  the person lets control that browser can run scripts in their tabs, with
  their signed-in sessions. BetterMeets runs only one fixed script, built into
  the app, whose only inputs (the step, a point as fractions of the page, typed
  text, and the expected page) are JSON-encoded, never JavaScript from saved
  demos or the model. Before running it, BetterMeets matches the captured window
  to the browser's window and requires its tab's address to match the page
  Accessibility reads in that window (scheme, host, port, and path), and the
  script checks the page's address again before it acts. It refuses password,
  payment, and one-time-code fields before reading them, never uses a field's
  value as a label, and reads back only the typed field's value to confirm it;
  page results are untrusted data, used only to decide the next route, and
  never logged or sent. A page click or page typing, including a build's retry
  of a press that changed nothing, aims at the target again
  and goes ahead only while Accessibility finds the target itself at the point.
  A page click then reads the control there and clicks it only if
  `DemoActionPolicy` allows it outright: a control it would ask about (a risky
  link or menu item, a dialog button, judged as one when a dialog, sheet, or
  alert is among the target's Accessibility ancestors, an unlabelled control)
  falls to the real click, and a denied one stops the step. It clicks only while that control is
  still there, and every step keeps the same `DemoActionPolicy` checks as
  Accessibility input. The `1+1` probe treats JavaScript as off only when the
  browser says so. Events time out after five seconds, and a step
  that may have run is never sent again. Script events are synthetic, so page
  actions that need a real gesture (file pickers, pop-ups, clipboard, full
  screen) don't happen, and the build sees that nothing changed.
- While building and testing, the window BetterMeets drives carries a badge and
  the demo's arrow in two nonactivating panels with `sharingType = .none`; the
  stage captures only the window itself, so neither appears there.
- When a build action opens another standard window of the source app,
  BetterMeets closes that window with its own close button through
  Accessibility, leaves the action out of the demo, and keeps building, at most
  three times per build; a window without a close button, a fourth one, or the
  demo window closing pauses the build until the presenter closes it. A window
  that appears after the person's own click, scroll, or key outside BetterMeets
  since BetterMeets last looked (or a second before) may be theirs, so it is
  left open and never counted against the demo. Focus changes never pause
  demos. A click or scroll on the source window pauses building, test runs, and
  playback, and so does a key: while playing, any key with the source app
  frontmost; while building and testing, only a key with the source window
  itself focused, so the person can keep using the app's other windows. Input
  to BetterMeets' own windows and to other apps, including the meeting, does not.
- VoiceMode remains removed. The microphone is used only by **Follow my
  voice**, which is on by default and listens only while a demo is presenting
  (playing or paused), stopping when the demo finishes. BetterMeets requests
  microphone access, and macOS may download the speech model once, when a demo
  becomes ready, before anything is presented; Info.plist declares microphone
  and speech-recognition purpose strings. If access is denied or recognition is
  unavailable or stops, holds use their timers; a microphone reconnect keeps
  waiting for the presenter's voice. Starts are token-guarded, so a start
  overtaken by a stop (say, after the demo finishes) never turns the microphone
  on, and test sessions never use it. Speech is transcribed on the Mac with
  Apple's on-device `SpeechTranscriber` in the script's language, detected on
  the Mac with NaturalLanguage (the system language, then US English, when it
  isn't supported). Audio and recognized text stay in memory, are never written
  to disk or logged, and are never sent to Anthropic or any other service.
- Anthropic keys use the former voice-mode Keychain service; no key data is
  read until a build starts, a script is rewritten, demo ideas are requested, or
  a moved target needs relocating. A key that Keychain can't save reports the failure inside the
  demo panel's inline key row.
- Only the selected source window is captured. Stream identity and frame
  generations prevent retired sources from publishing under a new selection.
- Stage Only hides the source list, header card, demo panel, and window buttons.
  Restoring controls during window sharing makes them visible to the audience.
  Native window chrome remains subject to the meeting app's capture behavior.
- The source-following tool widget is an independent panel, not a child of the
  source or workspace. It is visible when sharing an entire display.
- The teleprompter is also a separate window, docked at the camera notch. It sets
  `sharingType = .none`, asking macOS to keep it out of screen sharing, but
  macOS may not honor that for whole-display shares. Settings › Demos tells
  presenters to share the BetterMeets window, not the whole screen, to keep
  their lines private. Exclusion has not yet been confirmed in a live meeting
  share, so check before relying on it.

## Data handling

Ordinary capture and manual effects stay local. Building a demo, finding demo
ideas, and relocating moved targets all require Claude access (**See and operate
the selected window while building** in Settings › Demos,
`demo.allowsAIControl.v2`), one setting for every app. The demo panel asks for it
once, the first time a window is chosen, explaining what is sent; **Not Now**
records the answer (`demo.consentAnswered`), and Build asks again with **Allow
and Build** only while access is off.
Each build turn then sends Anthropic the request, the app's name and engine, a
browser start page's host and path, the scout's outline and code-generated facts
about earlier actions (each with what Claude said it expected and a summary of
what visibly changed, built from the two looks around it, which quotes the
window's labels and titles that name controls, never a row's), a JPEG of the selected window (at most 1024 pixels on its
longest edge), and the visible Accessibility elements' roles, labels, positions,
and states. A control with no title or description is labelled by its help
text, an image inside it, or the element that titles it. The element list
includes a text field's length, never its value; secure fields are flagged and
never read. Spinners and progress bars only tell the build to keep waiting and
are never sent. Test runs and playing resolve targets
locally whenever they can. While Claude access is on and a key is saved, if a
target moved on the right screen during a test run, or a highlighted control
moved during a presentation (actions are never relocated live), Claude Haiku
receives the step title, a target description, the note Claude wrote about the
target while building (when the step has one), one screenshot of the window,
and the element list to find it again. That note says what the target looks
like and where it sits; before storing it, code keeps one line of at most 120
characters and drops every word holding a digit or an @ (amounts, dates,
counts, addresses, handles), angle brackets, and straight quotes. It is sent
quoted inside the untrusted block and never used to identify, match,
fingerprint, or judge a target. Settings › Demos and the inline consent
row both say that playing or testing sends a screenshot only for this. While the
request field shows, the source is live, and a key is saved, Claude Haiku also
receives one screenshot and the element list (labels included) of the selected
window to suggest three demo ideas; the ideas are cached in UserDefaults
(`demo.ideas.v1`) per app and web host, so each app or site is read once unless
the presenter asks for more. After a build (or **Use N Steps**), and on
**Rewrite Lines**, Claude Opus receives a text-only script request: the
request, the app's name, the start description, the outline, each step's kind,
target name, title, and current line, and the chosen tone and audience notes,
with no screenshot or element list. Apart from relocation, playing a tested
demo sends nothing, and disabling Claude access stops a build and prevents
relocation, idea, and new script requests. The network session is ephemeral, rejects redirects so the key is
never forwarded, and does not log response bodies. The `demo-timings` log
lines are public but hold only durations, counts, token numbers, route names,
and action kinds (click, type, press), never labels, typed text, addresses,
step titles, or other window content. Keychain stores API keys; an ANTHROPIC_API_KEY environment
override is available for development.

UserDefaults stores any number of demos per app under `demo.library.v2`, and
which one each app last had open under `demo.selection.v2`. Each demo keeps the
request, title, outline, scripts (including the opening and closing lines),
holds, element locators (with Claude's note on each target), approved policy
questions, typed text, opened addresses, screen signatures, the full start URL,
the test result's date and fingerprint, and the build's action log (with what
Claude expected of each action, its verdict on it, what was observed, which
quotes only labels that name controls and gives rows and data-like labels by
position or kind, the screen each turn began on as a one-way hash, and which
steps its finish said show each beat) and estimated spend, which a compiled demo keeps so it can be compiled again
without pruning. Prompt drafts, cached demo
ideas, Claude access and whether it was answered, the bundle IDs of always-allowed apps
(`demo.alwaysAllowedApps`), the bundle IDs of browsers whose background tip a
ready demo showed (`demo.browserTipsShown`), playback preferences, the script tone and audience notes, and teleprompter
and Follow my voice settings are stored separately. Locators keep a label only
when it names a control; rows, cells, and data-like text such as amounts,
dates, and names are stored by position, and field values are never used as labels. No
screenshot is persisted by demos. Migration copies v1 prompts into drafts and
leaves the v1 library key untouched.

AI output is treated as untrusted. The model may act only on element IDs from
the current list, each of which must be found again uniquely before use, and
the recorded outcome comes from observing the app, not from the model.
Claude's verdict on its last action is a hint: a wrong turn counts toward the
stuck limit, but which steps a demo keeps follows what was observed, and a wrong
turn only lets a round trip's screens match by their signatures, never cuts a
step by itself. The steps Claude's finish says cover its outline can keep a
detour in the demo and turn one finish back; they never allow an action.
Screenshots, labels, page content, and the facts about earlier actions, which
quote them, are marked as untrusted content in requests, and text there that
spells out the marker loses its angle bracket, so it can't close the block;
only the presenter's request and approvals can authorize actions. The prompt
tells Claude to act on the verdicts BetterMeets writes into its own numbered
facts (rejected, rejected finish, no visible change, Presenter declined), which
can only turn an action or a finish back, and says no verdict authorizes
anything. `DemoActionPolicy`
in MeetStageCore enforces fail-closed rules in code while building and again
against the live element before every replayed action, so editing saved data
cannot turn a denied action into an allowed one:

- Controls whose label, help text, identifier, or placeholder sounds
  destructive (delete, send, pay, transfer, sign out, publish, and similar,
  matched at the start of a word, with a leading “un” or “re” still counting,
  in English and several other languages, and anywhere in a word in German,
  which joins verbs to prefixes) are never clicked; demos highlight them
  instead. Identifiers such as `btnDelete` are split into words first. Menu
  items that sound destructive and links that name a destructive action
  (“Delete account”, “Sign out”) need presenter approval. Tabs, and links in a
  plural or past form that name a list or a state (“Transfers”, “Deleted”),
  open without asking, since opening a view commits nothing and the
  destructive control inside stays denied. A control with no title or
  description is judged by the label it borrows from its help text, an image
  inside it, or the element that titles it, so those words can deny it too.
  Unlabelled controls (with none of these), and controls
  inside an open dialog, sheet, or alert other than dismissals such as Cancel
  or Close, need presenter approval. Text or an icon inside a link or button
  resolves to that control, so the policy judges the control itself.
- Secure fields are never clicked. Secure and sensitive fields (passwords,
  codes, recovery phrases, card numbers, and similar) never receive typing.
  Typed text containing line breaks, tabs, or other control characters is
  denied. Typed text must come from the request unless approved, and Return
  after typing outside a search field needs approval.
- Only HTTP/HTTPS addresses open. The host must be the start host or a host
  written in the request, exactly or as a subdomain of it (a substring such as
  `hub.com` in `github.com` does not count), with any query taken from the
  request; anything else needs approval.

Presenters approve with Allow, or decline with Skip, while building; approvals
are recorded on the step with the exact question approved, replay accepts only
that question (or, for a control that has since borrowed a label, the question a
demo saved before then asked about it unnamed, judging denials with the label),
and denials cannot be approved. When trusting the app can answer
the question, the approval also offers **Always Allow in App**, which allows it,
adds the app's bundle ID to `demo.alwaysAllowedApps`, and keeps building. Builds
in that app then answer such questions without stopping and record each on its
step as if the presenter had chosen Allow, and test runs and playing accept them
even when a renamed control no longer matches the recorded question. Trust
answers controls in a dialog whose own text reads as harmless, unlabelled
controls, typed text the request doesn't contain, and a query the request
doesn't contain on the start host or a host it names. It never answers opening a
host the request doesn't name (the way page content could send data elsewhere),
Return outside a search field, a link that names a destructive action (“Sign
out” and “Delete account” often act the moment they're clicked), a
destructive-sounding menu item, or a control in a dialog whose text sounds
destructive or sensitive, warns without naming the action (“Are you sure?”,
“This can't be undone”), or couldn't be read in full, and it never turns a
denial into an approval. A dialog's text is its title, accessible name, and
static text, kept per dialog whatever its length, never page text outside it,
and never sent to Claude; it only decides whether trust may answer, never
whether an action is allowed. In a trusted app, text Claude chose, which may
come from the page, can be typed without asking; Return, destructive buttons,
and other sites stay guarded, but neutral commit buttons such as Save or Add are
not denied. Settings › Demos lists always-allowed apps by name and icon;
removing one makes later builds, test runs, and plays ask or stop again, while
steps already approved keep their recorded approvals. Returning to the start
presses only the browser's Back button, a dialog's Close or Cancel button, and
start items and switches the policy allows without approval; every click still
passes the denial check, and in the background a Close button or start item that
showed nothing is clicked once more on the next route, never a switch. Builds stop at 24 turns, 40 steps, four minutes, or $2
of estimated spend, counting failed calls, each fallback attempt, and replies
asked again because they named an unlisted element or arguments that can't
work; script and idea requests are not counted toward that limit. A build also
stops after three actions in a row that the policy denied (“Stopped because
Claude kept choosing actions BetterMeets won’t do.”), counted apart from turns
that changed nothing. The policy
guards against model mistakes; it is not a guarantee about what an app's controls do.
Presenters should review steps and use demo accounts. **Tested** shows that the
recorded actions replayed once against that app version and window size (in
100-point steps); it is not a security or correctness guarantee.

Imported logos are dimension-checked, downsampled, normalized as PNG, and stored
atomically in Application Support. UserDefaults contains a storage-version
marker, with one-time migration of older logo blobs.

Public updates use an HTTPS Sparkle appcast and EdDSA signatures. Feed and
public-key metadata must be configured together. Unconfigured local builds
leave the updater inactive. Release signing and notarization credentials remain
outside the repository.
