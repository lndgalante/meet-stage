# BetterMeets security and distribution model

BetterMeets is a directly distributed macOS utility. It does not enable App
Sandbox because it combines ScreenCaptureKit window capture with global mouse
and keyboard observation. Reassess sandbox feasibility before App Store distribution.

The hardened runtime is enabled for packaged builds. Certificate-signed releases
retain library validation. Local ad-hoc packages disable library validation so a
teamless build can load the embedded Sparkle framework. The shipping entitlement
file contains only `com.apple.security.device.audio-input`, which the hardened
runtime requires for Follow my voice to hear the microphone; the development
file adds the library-validation exception. Neither grants input-synthesis
capabilities. CI asserts that the release app carries the audio-input
entitlement and `NSMicrophoneUsageDescription`.

## Permissions and capture

- Screen Recording is checked without prompting at launch and requested through
  the sidebar's Allow Access action.
- Keystroke highlighting requests Accessibility when the user enables it.
- Real-time demos use Accessibility to read the selected window and to operate
  it in the background, without bringing the app to the front: clicks use the
  element's press action, typing sets a field's value, and scrolling asks an
  element to scroll into view. Every input is bound to the selected source
  window and its process. Before a click, BetterMeets hit-tests the target
  within the app, stops when another of the app's controls covers it, and
  re-checks the policy's denials against the element actually there. Key steps,
  Return after typing, browser navigation, controls that refuse Accessibility
  actions, and scrolling Accessibility can't do bring the source app forward
  briefly; that fallback
  requires exact focus on the source window, stops if the app loses the front,
  and asks for BetterMeets to become active again afterwards. Fallback clicks
  are hit-tested system-wide and must hit the source process. Keyboard events
  are posted only to the source process, so a focus change cannot send
  keystrokes to the meeting app, and Return goes only to the field the step
  typed into. Synthetic events come from a private event source with explicit
  modifier flags and an identifying tag. Pointer travel and typing can be
  cancelled; a posted mouse-down always gets its mouse-up and every key-down its
  key-up. Text with line breaks, tabs, or control characters is never typed.
  Browser navigation accepts only HTTP/HTTPS URLs without embedded credentials
  and types them into the same tab's address bar after confirming that the
  address bar, not the page, has focus.
- When a build action opens another standard window of the source app,
  BetterMeets closes that window with its own close button through
  Accessibility, leaves the action out of the demo, and keeps building, at most
  three times per build; a window without a close button, a fourth one, or the
  demo window closing pauses the build until the presenter closes it. Focus
  changes never pause demos. A click or scroll on the source window, or a key while the
  source app is frontmost, pauses building, test runs, and playback; input to
  BetterMeets' own windows and to other apps, including the meeting, does not.
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
- The teleprompter is also a separate window, placed under the camera. It sets
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
about earlier actions, a JPEG of the selected window (at most 1024 pixels on its
longest edge), and the visible Accessibility elements' roles, labels, positions,
and states. The element list includes a text field's length, never its value;
secure fields are flagged and never read. Test runs and playing resolve targets
locally whenever they can. While Claude access is on and a key is saved, if a
target moved on the right screen during a test run, or a highlighted control
moved during a presentation (actions are never relocated live), Claude Haiku
receives the step title, a target description, one screenshot of the window,
and the element list to find it again. Settings › Demos and the inline consent
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
never forwarded, and does not log response bodies. Keychain stores API keys; an ANTHROPIC_API_KEY environment
override is available for development.

UserDefaults stores any number of demos per app under `demo.library.v2`, and
which one each app last had open under `demo.selection.v2`. Each demo keeps the
request, title, outline, scripts (including the opening and closing lines),
holds, element locators, approved policy questions, typed text, opened addresses,
screen signatures, the full start URL, the test result's date and fingerprint, and an
interrupted build's action log and estimated spend. Prompt drafts, cached demo
ideas, Claude access and whether it was answered, playback preferences, the script tone and audience notes, and teleprompter
and Follow my voice settings are stored separately. Locators keep a label only
when it names a control; rows, cells, and data-like text such as amounts,
dates, and names are stored by position, and field values are never used as labels. No
screenshot is persisted by demos. Migration copies v1 prompts into drafts and
leaves the v1 library key untouched.

AI output is treated as untrusted. The model may act only on element IDs from
the current list, each of which must be found again uniquely before use, and
the recorded outcome comes from observing the app, not from the model.
Screenshots, labels, and page content are marked as untrusted content in
requests; only the presenter's request can authorize actions. `DemoActionPolicy`
in MeetStageCore enforces fail-closed rules in code while building and again
against the live element before every replayed action, so editing saved data
cannot turn a denied action into an allowed one:

- Controls whose label, help text, identifier, placeholder, or container label
  sounds destructive (delete, send, pay, transfer, sign out, publish, and
  similar, matched in English and several other languages) are never clicked;
  demos highlight them instead. Links, tabs, and menu items that sound
  destructive, unlabelled controls, and controls inside an open dialog, sheet,
  or alert other than dismissals such as Cancel or Close need presenter
  approval. Text or an icon inside a link or button resolves to that control,
  so the policy judges the control itself.
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
that question, and denials cannot be approved. Returning to the start
presses only the browser's Back button, a dialog's Close or Cancel button, and
start items and switches the policy allows without approval; every click still
passes the denial check. Builds stop at 24 turns, 40 steps, four minutes, or $2
of estimated spend, counting failed calls and each fallback attempt; script and
idea requests are not counted toward that limit. The policy
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
