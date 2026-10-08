# BetterMeets

**Stay in flow. Look polished.**

BetterMeets is a lightweight macOS app for smoother live software demos. Share
one stable BetterMeets window in your meeting, then switch between app windows without
reopening the share picker or exposing your desktop.

## How it works

BetterMeets brings tools, window selection, and the live stage into one resizable
Mac window. The left sidebar is a compact vertical rail of application icons. The main area shows the selected source at its original
aspect ratio. Source status, Pause Stage, and Clear Stage sit above the preview.
The bottom strip holds the real-time demo composer and playback controls.

Choose an app icon to put a window on stage. Selecting the live source again
keeps it live. Use Pause/Resume (Shift–Command–P) to hide or restore the source.
Clear Stage removes it without stopping your meeting app’s share. A source is
marked live only after ScreenCaptureKit delivers its first complete video frame.
The window keeps the size and position you chose when sources change.

Choose **Stage Only** (Control–Command–S) to hide the window rail,
status strip, and toolbar. Then share **BetterMeets** in your meeting app.
Press the same shortcut or Escape to restore controls. Use the standard green
traffic light for full screen while controls are visible. Returning
to controls while sharing makes them visible to your audience.

The stage is a live presentation surface. Use **Open Source App** from the menu (Shift–Command–O) to
interact with the original source window. Cursor, ink, and pointer effects follow
the selected source while its application is frontmost.

BetterMeets assigns **Option–1** through **Option–9** to available windows.
Change the modifier or disable global shortcuts in Settings → General. Right-click
an app icon to pin or unpin a slot. Pins survive launches and reserve their slot
when the source is unavailable. An ambiguous window identity is never guessed.
Scroll vertically to browse sources; Up/Down and Return select by keyboard, and
Space opens a larger preview. Source shortcuts also scroll the selected tile
into view. New and closed windows update automatically.

Presentation tools are available from the menu bar and Settings (Command–comma).
Each effect’s settings show its On/Off state beside the preview.

The window rail stays compact at every window size. Hover over an icon or press
Space to see the full window title, preview, and shortcut. Unavailable pinned
windows have a local Unpin action.

The same tools also appear in the floating widget beside the selected source
window, together with Pause/Resume, Clear Stage, and Show Controls. It follows moves and resizes, uses the right or left gutter when
space allows, and stays inside the screen. It remains available in Stage Only
mode while the source app is active. Returning to BetterMeets or another app
hides it, as does the source becoming unavailable.
The widget is a separate window; sharing the BetterMeets workspace excludes it.
Window → Show Source Tools (Control–Command–T) opens the source app and its widget.

- **Auto Polish** adds a styled frame, temporarily zooms around clicks, and
  mirrors the macOS cursor at 2× without moving the real pointer. Settings → Auto Polish
  selects the backdrop and optional logo.
- **Spotlight** follows the source pointer with a focused circle and dims the
  surrounding content. Settings → Spotlight adjusts size and outside opacity.
- **Annotations** draws temporary ink over the original source and mirrors it on
  stage. Closed strokes can snap to circles or rectangles. Escape finishes drawing;
  Command–Z undoes strokes. Settings → Annotations sets color and fade time.
- **Click Highlights** shows ripples at source clicks. **Keystrokes** displays
  shortcut badges on stage and requests Accessibility when first enabled.

The capture pipeline keeps smaller sources at native resolution and caps larger
sources at a 2560-pixel edge, at 30 fps. Presentation effects share pointer
monitoring. BetterMeets uses the microphone only while you present a demo with
**Follow my voice** on; speech is transcribed on the Mac, and nothing is saved
or sent. Real-time demos send screenshots and control labels of the selected
window to Anthropic only after the presenter enables AI access.

## Real-time demos

Select an app window, describe the walkthrough in the bottom strip, and choose
**Build Demo**. Demo Setup accepts an Anthropic API key (stored in Keychain),
the **Allow Claude to see and control the selected window while building**
toggle, and Accessibility access, which lets BetterMeets read the app and click
and type in it. The first build in each app asks for a one-time confirmation
before BetterMeets touches it.

Claude does not plan the demo from a single screenshot. Claude Opus 5.5 operates
the real app one action per turn: BetterMeets reads the window's Accessibility
elements and takes a screenshot, Claude picks exactly one action (click, type,
press a key, scroll, open a page, highlight, finish, or report that the request
can't be shown) using an element from the current list, and BetterMeets checks
that the element exists, can be found again uniquely, and passes the safety
policy before performing it. Once the app settles, BetterMeets records what
actually changed, so every step targets something that was really on screen.
Steps appear in the strip as they are recorded, followed by dashed outlines for
beats still to come. A build stops after 24 turns, 40 steps, four minutes, or
$2 of API usage (failed and fallback model calls count), or when several
actions in a row change nothing.

If the app doesn't show what the request needs, Claude explores briefly, then
stops with the reason and the closest real alternative it saw.
**Show … Instead** returns the app to where the build started and rebuilds with
that alternative; **Edit Request** returns to the composer. An action the
safety policy wants you to confirm pauses the build, circles the control, and
offers **Allow** and **Skip**. After **Stop** or an
interruption, choose **Keep Building**, **Use N Steps** to check what was
recorded so far, or **Discard**, which returns the app to where the build
started. A build that hits a limit offers the last two.

When a build finishes, BetterMeets returns the app to its starting point without
asking a model: browsers press their Back button until the start address shows,
reopening it in the same tab only if that fails, and other apps close dialogs
with their Close or Cancel button (or Escape), reselect the recorded start item,
and reset switches to how they started. It then plays the demo back with short
holds to check it, confirming the start screen as it goes. A paused check
continues where it stopped, and only a check in which every step passed shows
**Checked**. The check is tied to the start, the actions that change the app,
the app's version, and the window's size in 100-point steps.
Editing titles, scripts, holds, the start description, or the closing line, or
rewriting the script, keeps it; an app update, resizing the window into another
100-point step, or a changed action shows **Not checked** until **Check Again**
passes.

While that check runs, Claude Opus 5.5 rewrites the narration as one story: an
opening line, a line and a two-to-four-word title for each step, and a closing
line. Only words change (holds follow the new lines), so the check is
unaffected; steps removed in the meantime stay removed, and lines edited in the
meantime keep your edits. The strip shows
**Writing the script…** until it's done. This request is text only: your
request, the app's name, the start description, the outline, and each step's
kind, target name, title, and current line. **Use N Steps** writes a script the
same way. To write it again while AI access is on, choose **Rewrite Script** in
**Presenter Script…**, which also sets the tone (Conversational, Concise, or
Technical) and optional notes about the audience, or in the Demo menu. A
rewrite that fails keeps the existing lines and shows why in
**Presenter Script…**.

Steps store how to find each element rather than where it was: its role, a label
that names the control, its container, and, for data such as table rows, its
position among similar elements. Amounts, dates, and names are never used to
find a row, and a row found by position must still be near where it was
recorded. Unlabelled icons and text values are found by position only inside
their recorded container, within 18 points for controls and 14 for text, and
only when clearly the closest; a different caption in that spot never stands
in, and a scroll recorded while building is repeated before a position is
trusted. A target with a look-alike within 30 points is refused when it's
recorded. A count badge, as in “Inbox 3”, doesn't change which control a label
names, and identifiers that web frameworks generate are ignored. Checking and
playback wait for the screen to settle after each action, find targets locally
through Accessibility, and act only when exactly one element matches, so
playing a checked demo needs no AI. If a target moved or was renamed on the
right screen and AI access is on, Claude Haiku 4.5 can relocate it. During a
live presentation, actions are never relocated, and a highlight that can't be
found is skipped instead of stopping the demo. If the app is already on another
step's screen, **Continue from Step N** picks up there.

Demos run the app in the background. BetterMeets doesn't bring it to the front,
so you stay in BetterMeets and watch the stage, where a virtual cursor glides to
each target and a click ripple marks each click. Clicks use the control's
Accessibility press action, after checking that nothing else in the app covers
it. Typing sets the field's text through Accessibility, character by character
during presentations so it reads as typing on the stage; a field that already
holds the text is left alone. Targets below the fold are scrolled into view
through Accessibility. Only keys (key steps, Return after typing, and ⌘L for
**Open page**), controls that refuse Accessibility actions, and scrolling that
Accessibility can't do bring the app forward briefly, after which BetterMeets
becomes active again; such fallback clicks move the real pointer and must land
on the source app. Keys go only to
the source app. Return follows typing in search fields, and elsewhere only with
your approval. Key steps are limited to Escape, Tab, Shift–Tab, the arrow keys,
and Page Up/Down, and show a key badge. In browsers, **Open page** steps use the
same tab's address bar.

**Play Demo** first checks that the app is at the start. If it isn't, the strip
shows **Not at the start** with **Return to Start** or **Play Anyway**, and
notices when you get there by hand. Playback then advances automatically.
**Pause Demo** keeps the live source and current highlight visible; **Continue**
resumes from the next action and never repeats one already dispatched.
Highlights carry a short script (navigation usually needs none); while
presenting, the current line appears below the steps in larger text. With
**Follow my voice** on (the default), you set the pace and the strip reads
**N steps · paced by your voice**. With it off, or when the microphone or
recognition is unavailable, each hold allows time to say its line at about 150
words per minute, and playback starts at **2×**. Speed only affects timed
playback: it shortens pauses and silent steps, never the time a line takes to
say, and doesn't change the saved scripts or timings; typing and page loads
keep their own pace. **Speed** (1×, 1.5×, 2×, 3×) appears in the options menu
and the Demo menu only while Follow my voice is off; Demo Setup shows it
disabled, with an explanation, while it's on. **Pause After Each Step** is in
all three. **Next Step** runs one step, then pauses. The floating source widget
also has Play/Pause Demo, and Return to Start when the app isn't at the start.
In BetterMeets, the Demo menu provides Control–Command–Return for play/pause
and Control–Command–Right Arrow for a single step, or **Next Line** while
presenting. **Pause Stage** remains separate: it hides the source.

**Presenter Notes** is a floating teleprompter that doesn't activate
BetterMeets and remembers its position. It shows the current line in large text
(with Smaller and Larger buttons), the step number, the next step's title, and
a progress bar during each timed hold. Playing from the start shows the opening
line before step 1 (continuing a paused demo doesn't), and the closing line at
the end; without a closing line the panel clears. It opens when you play
(turn off **Open presenter notes when playing** in Demo Setup), and the strip's
speech-bubble button or Control–Command–N shows or hides it. BetterMeets asks
macOS to keep the panel out of screen sharing, but macOS may not honor that when
you share your whole screen. Share the BetterMeets window, not the whole screen,
to keep your notes private, and confirm that in your meeting app before relying
on it.

**Follow my voice** is on by default; turn it off in the notes panel, Demo
Setup, or the Demo menu. When a demo becomes ready, BetterMeets asks for the
microphone and lets macOS download its speech model, so neither happens in
front of your audience. It listens only while a demo is presenting (playing or
paused) and stops when the demo finishes. Speech is transcribed on the Mac with
Apple's on-device speech recognition, biased toward the script's words, in the
language the script is written in (otherwise your system language, or US
English). Words you've said dim and the next word is highlighted. While it's
following your voice there are no timers: each line, including the opening
line, moves on a beat after you've said it, or when you say “next”. A step
without a line waits for “next”, and the notes panel and strip show **Say
“next” to continue**. “Next” counts only when it's the newest word heard and
isn't read as a word of the line, and only after about 0.6 seconds with no new
words; *siguiente*, *suivant*, *weiter*, *avanti*, *próximo*, and *seguinte*
work too. If the audio input changes (a newly connected microphone, or your
meeting app adjusting it), listening reconnects, at most once every 2 seconds,
and the demo keeps waiting for you. **Skip** in the notes panel or
Control–Command–Right Arrow (**Next Line**) always moves on; the shortcut also
ends a timed hold. Holds use timers only when Follow my voice is off, the
microphone is denied, or recognition is unavailable or stops. Audio and
transcripts are never saved or sent.

Spotlight, magnification, drawn circles, the virtual cursor, click ripples, and
key badges render on the shared stage. Demo spotlights, circles, and key badges
also appear over the source app while it is in front, with clicks passing
through. Magnification changes the stage camera, while the source app keeps its
original layout.

Using the mouse or keyboard in the source app pauses building, checking, and
playback: a click or scroll inside the source window, or a key while the source
app is in front. Input to BetterMeets itself, the meeting app, or any other app
never pauses, and neither does a change of which app is in front. Stay in
BetterMeets and leave the source app alone during automatic runs.

**Edit Steps…** changes titles, scripts, holds, the start description, and the
closing line, saving only the fields you changed, so a script rewritten while
the sheet is open survives on the other lines. Targets and actions come from
what happened in the app, so they can't be retyped; removing an action also
removes every later step and needs a new check. **Presenter Script…** opens the
complete read-aloud script, including the opening and closing lines, with
**Rewrite Script** and **Copy Script** to take it elsewhere. **Return to Start** resets the app the
same way as after a build; it does not undo other changes.

The latest demo and request are saved separately for each app. Switching apps
shows that app's demo or an empty composer; returning restores its steps at the
beginning. An interrupted build reopens with **Keep Building** and
**Use N Steps**. **New Demo…** clears only the selected app's demo and keeps its
request. Pausing capture keeps the selected app's demo visible, with building
and playback disabled until capture resumes. Switching sources or pausing
capture pauses pending work, and turning off AI access stops a build. Demos from
earlier versions can't replay; their requests return as drafts in the composer.

A safety policy in code applies while building and again before every replayed
action. BetterMeets never clicks buttons and other controls that sound
destructive, such as Delete, Send, or Pay, in English or several other
languages; a demo can highlight them instead. Text or an icon inside a link or
button counts as that control. It asks before opening links, tabs, or menu
items that sound destructive, clicking anything in a dialog other than a
dismissal such as Cancel or Close, clicking unlabelled controls, typing text
that isn't in your request, or opening sites other than the start site and
those the request names by address (that exact host or its subdomains, never a
partial match). It never types into password, code, or payment fields, and
never types line breaks, tabs, or other control characters. Screenshots and
labels are treated as untrusted content; only your request authorizes actions.
Review the steps and use a demo account for presentations that show private or
consequential data.

The choreography takes inspiration from [video-demo](https://github.com/nilbuild/video-demo):
perform the gesture, then focus attention on its result. BetterMeets runs the
steps against the live app and does not generate a video file.

## Requirements

- macOS 26 or newer
- Apple Silicon Mac
- Swift 6.2 and the macOS 26 SDK from Xcode 26 or newer

Install the Command Line Tools if needed:

```bash
xcode-select --install
```

Confirm that Swift is available:

```bash
swift --version
```

SwiftPM resolves Sparkle, the auto-update dependency, during the first build.

BetterMeets is distributed directly and runs without App Sandbox for window
capture and global event observation. Hardened-runtime release builds retain
library validation and carry only the audio-input entitlement, which Follow my
voice needs to hear the microphone; CI checks that the release app ships it and
the microphone purpose string. See [SECURITY.md](SECURITY.md).

## Local development

The native equivalent of `pnpm dev` is:

```bash
./dev-app.sh
```

This command:

1. Stops the previous BetterMeets process before changing its app bundle.
2. Builds the Swift package in debug mode.
3. Creates `dist/BetterMeets.app` with its Info.plist and icon.
4. Signs with `BETTERMEETS_CODESIGN_IDENTITY`, an available Apple Development
   certificate, or an ad-hoc signature when no certificate is installed.
5. Launches the new build.

There is no hot reload. After changing Swift code, run `./dev-app.sh` again.
`--no-launch` builds without opening the app, and requires the target app to
already be quit. Release builds go to a separate directory so packaging a
release cannot replace the running development app.

To build and package the debug app without launching it:

```bash
./dev-app.sh --no-launch
```

For a fast compile-only check:

```bash
swift build
```

Avoid `swift run` when testing capture or permissions. It runs the bare
executable without the packaged app's Info.plist, icon, and stable signing
identity.

### Command map for JavaScript developers

| JavaScript workflow | BetterMeets |
| --- | --- |
| `pnpm install` | `swift package resolve` (also runs during builds) |
| `pnpm dev` | `./dev-app.sh` |
| Compile check | `swift build` |
| Optimized local build | `./build-app.sh` |
| Build artifacts | `.build/` and `dist/` |

## First run

1. Run `./dev-app.sh`.
2. Allow Screen & System Audio Recording when macOS asks. BetterMeets captures
   video only.
3. If macOS asks for a restart, use **Restart BetterMeets** in the access setup.
4. Select a source window.
5. Enable **Stage Only**, then share **BetterMeets** in your meeting.
6. Switch sources from BetterMeets or your pinned global shortcuts.
7. Use **Pause/Resume** above the preview or in the floating source tools.
8. Optional: turn on Auto Polish and choose its framing and motion in Settings
   → Auto Polish.

BetterMeets windows are excluded from the source list. Your meeting keeps
capturing the same workspace window while BetterMeets changes what appears
inside it.

## Project structure

| Path | Purpose |
| --- | --- |
| `Sources/MeetStage/MeetStageApp.swift` | SwiftUI scenes and menu commands |
| `Sources/MeetStage/WorkspaceView.swift` | Unified workspace layout and Stage Only mode |
| `Sources/MeetStageCore/` | Framework-free capture frame validation, bounded concurrency, and the real-time demo action policy, compiled as an independent SPM target |
| `Sources/MeetStage/CaptureServices.swift` | Injected thumbnail and Screen Recording authorization services |
| `Sources/MeetStage/ControlView.swift` and `Control*.swift` | Vertical window selector, settings, reusable controls, and preview rendering |
| `Sources/MeetStage/CaptureManager.swift` and `CaptureManager+*.swift` | Main-actor state plus responsibility-focused discovery, command, lifecycle, presentation, and callback extensions |
| `Sources/MeetStage/Diagnostics.swift` | Categorized, privacy-aware unified logging |
| `Sources/MeetStage/WindowSourceDiscovery.swift` | Source eligibility, ScreenCaptureKit discovery, and thumbnails |
| `Sources/MeetStage/WindowGeometry.swift` | Canonical source coordinates, window-frame resolution, and overlay tracking |
| `Sources/MeetStage/GlobalLocalEventMonitor.swift` | Shared global/local AppKit event-monitor lifecycle for pointer effects |
| `Sources/MeetStage/ShortcutAssignments.swift` | Deterministic shortcut-assignment policy |
| `Sources/MeetStage/ShortcutPreferencesStore.swift` | Backward-compatible shortcut persistence |
| `Sources/MeetStage/SampleBufferRenderer.swift` | High-resolution frame rendering |
| `Sources/MeetStage/StageWindowSizing.swift` | Stage geometry and aspect-ratio handling |
| `Sources/MeetStage/AutoPresentation.swift` and `CaptureManager+AutoPresentation.swift` | Click-driven zoom camera, read-only pointer tracking, and 2× native system-cursor mirroring |
| `Sources/MeetStage/StageFramePresentation.swift` | Styled-frame layout, built-in backdrops, blur, corners, and shadows |
| `Sources/MeetStage/WindowConfiguration.swift` | AppKit window behavior used by SwiftUI scenes |
| `Sources/MeetStage/GlobalHotKeyManager.swift` | Configurable global source-slot shortcut registration |
| `Sources/MeetStage/Annotations.swift`, `AnnotationShapeRecognizer.swift`, and `AnnotationOverlay.swift` | Temporary ink, closed-shape recognition and rendering, plus AppKit source-overlay presentation |
| `Sources/MeetStage/ClickHighlights.swift`, `KeystrokeHighlights.swift`, and `SpotlightEffect.swift` | Effect-specific models, monitoring, overlays, and rendering |
| `Sources/MeetStage/PresentationPreferences.swift` | Shared color, size, and keystroke appearance options |
| `Sources/MeetStage/StageLogoStore.swift` | Bounded image normalization and Application Support persistence |
| `Sources/MeetStage/WorkspaceObservationBag.swift` | App lifecycle observation and notification-token ownership |
| `Sources/MeetStage/Demo*.swift`, `RealTimeDemo.swift`, `AccessibilityService.swift`, and `AXSnapshot.swift` | Real-time demo building, matching, replay, script writing, and the bottom strip |
| `Sources/MeetStage/PresenterNotes.swift`, `ScriptFollower.swift`, and `SpeechListener.swift` | Presenter notes panel, script following, and on-device speech recognition |
| `Tests/MeetStageTests/` | Policy, persistence, geometry, and AppKit interaction tests |
| `Resources/Info.plist` | Bundle name, version, permissions, and icon metadata |
| `Brand/` | BetterMeets icon masters and brand guidance |
| `dev-app.sh` | Debug build, package, sign, and relaunch workflow |
| `build-app.sh` | Release build and packaging workflow |
| `scripts/notarize-app.sh` | Developer ID notarization, stapling, and Gatekeeper verification |
| `.github/workflows/ci.yml` | Formatting, metadata, tests, and strict debug/release compilation |

The Swift package and executable retain the internal name `MeetStage`. The app
bundle and every user-facing surface use the BetterMeets product name.
See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership boundaries, lifecycle
invariants, and guidance for extending the app. See [TESTING.md](TESTING.md) for
the automated and manual verification strategy.

## Screen Recording permission

Both development and release builds use bundle identifier
`com.lndgalante.bettermeets`. Permission persistence also depends on the code
signing identity. Ad-hoc signatures can invalidate a grant after rebuilding,
even when System Settings still displays an enabled BetterMeets entry.

For development, add an **Apple Development** certificate in **Xcode → Settings
→ Accounts → Manage Certificates**. `./dev-app.sh` automatically uses the first
available Apple Development identity; set `BETTERMEETS_CODESIGN_IDENTITY` to
choose a specific one. Keep that certificate across builds. A signing-identity
change may require granting access once more.

The app checks permission on launch without opening a system dialog. Use
**Allow Access** in the sidebar to request access explicitly.
If BetterMeets is already enabled in System Settings, quit and reopen the
packaged app. If the existing grant still does not apply, remove and re-add
BetterMeets in **Privacy & Security → Screen & System Audio Recording** after
fixing the signing identity. Do not reset other applications' permissions.

Keystroke highlighting requests Accessibility when enabled. Manage it under
System Settings → Privacy & Security → Accessibility. Follow my voice requests
the microphone when a demo first becomes ready; manage it under Privacy &
Security → Microphone. Without it, demos use their timed holds.

Pinned shortcuts use the legacy `MeetStage.shortcutPins.v1` defaults key, and
explicit unpins use `MeetStage.shortcutExclusions.v1`. Keep both keys stable so
local development and future rebrands do not discard user preferences.

## Debugging and verification

Run the packaged debug executable directly when you need Terminal output:

```bash
"dist/BetterMeets.app/Contents/MacOS/MeetStage"
```

Quit any existing BetterMeets instance first. You can also inspect logs in
Console.app by filtering for `BetterMeets` or `MeetStage`.

Run the automated suite and packaging checks before handing off a change:

```bash
swift test
swift format lint --strict --recursive Sources Tests Package.swift scripts/generate-app-icon.swift
./build-app.sh
plutil -lint Resources/Info.plist
codesign --verify --deep --strict "dist/release/BetterMeets.app"
git diff --check
```

GitHub Actions repeats formatting, metadata, tests, and warnings-as-errors
debug/release compilation for every push and pull request on an Apple Silicon
macOS runner.

The automated suite covers window eligibility, deterministic shortcut
assignment, persisted preference compatibility, corrupt preference recovery,
auto-zoom and styled-frame geometry, presentation and annotation policies,
stage sizing, AppKit stage interaction, and, against fakes, real-time demo
building, matching, replay, and script following. For ScreenCaptureKit, global-hotkey,
or workspace changes, also
test the complete flow manually in a meeting because those APIs require real
windows and macOS privacy consent.

## Release builds

Create the optimized local build with:

```bash
./build-app.sh
```

The result is `dist/release/BetterMeets.app`. It is ad-hoc signed for local use and is
not notarized for public distribution. Because ad-hoc signatures have no team
identity, this local package alone disables library validation so it can load
Sparkle; Developer ID builds retain library validation.

For a public build, provide a Developer ID Application identity, the HTTPS
Sparkle appcast URL, and the EdDSA public key generated by Sparkle. The packaging
script rejects partial update configuration and enables the hardened runtime
and trusted timestamp automatically:

```bash
BETTERMEETS_CODESIGN_IDENTITY="Developer ID Application: Example Corp (TEAMID)" \
BETTERMEETS_UPDATE_FEED_URL="https://updates.example.com/appcast.xml" \
BETTERMEETS_UPDATE_PUBLIC_KEY="BASE64_EDDSA_PUBLIC_KEY" \
    ./build-app.sh
```

Store App Store Connect credentials in the Keychain once, using Apple's
`notarytool store-credentials` command. Then submit, wait for acceptance, staple
the ticket, run Gatekeeper verification, and create a distributable
`dist/BetterMeets.zip` and a retained notarization log with:

```bash
BETTERMEETS_NOTARY_PROFILE="bettermeets-notary" \
    ./scripts/notarize-app.sh
```

Place the notarized update archives in one directory and generate the signed
appcast using Sparkle's Keychain-held private key:

```bash
./scripts/generate-appcast.sh /path/to/updates
```

Publish the generated appcast and archives at the configured HTTPS endpoint.

Before publishing, increment both version fields in `Resources/Info.plist`, run
the complete verification commands above, and manually exercise first-run
permissions, capture switching, pause/resume, all presentation effects, and
global shortcuts on a clean macOS user account. Apple signing credentials and
notarization are intentionally external to the repository.

## Known limitations

- Source audio is not captured.
- The stage mirrors a source window; interaction happens in the original app.
- Showing controls while sharing the workspace makes them visible to the audience.
- Styled frames use built-in gradients and colors; custom image wallpapers are
  not yet supported.
- macOS may block protected video surfaces, causing them to appear black.
- Keep BetterMeets open while it is being shared.
- macOS may not keep the presenter notes panel out of a whole-screen share;
  share the BetterMeets window to keep notes private. Exclusion hasn't yet been
  confirmed in a live meeting share.
- If an app restores two windows with the same title, its pinned shortcut stays
  unavailable instead of guessing.
