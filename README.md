# BetterMeets

**Stay in flow. Look polished.**

BetterMeets is a lightweight macOS app for smoother live software demos. Share
one stable Demo Stage in your meeting, then switch between app windows without
reopening the share picker or exposing your desktop.

## How it works

BetterMeets has two windows:

- **BetterMeets** is a compact floating controller with four visible previews
  in a horizontally scrolling window strip, plus global shortcuts.
- **BetterMeets — Demo Stage** is the clean, high-resolution output window. This
  is the only window you share in Google Meet or another meeting app.

The Demo Stage follows the selected window's aspect ratio and capture dimensions
to avoid unnecessary black padding. A source appears as **Live** only after
ScreenCaptureKit delivers a complete video frame. The active source tile is
marked **Live** in the controller. The pointer appears
on the Demo Stage only while the selected source application is active, so
moving through a different app does not leak its cursor position into the demo.
Idle, paused, permission, and error screens all use the same default stage size.
The stage keeps standard macOS window semantics beneath its hidden chrome, so it
can be dragged from its surface and selected by window-capture utilities.

BetterMeets automatically assigns **Command–Option–1** through
**Command–Option–9** to the first nine available windows. Choose another global
modifier—or turn global shortcuts off—in **BetterMeets → Settings → General**.
Right-click a source to move it to a specific shortcut or unpin it. Manual pins
remain stable across refreshes and app launches, and an
explicitly unpinned window stays unassigned until you pin it again. If the exact
window for a manual pin is unavailable or ambiguous, BetterMeets keeps the
shortcut reserved instead of silently pointing it somewhere else.

Swipe or scroll horizontally over the window strip to browse every available
source. Newly opened windows appear automatically. Minimized or hidden windows
temporarily leave the strip and return when restored, while their pinned slots
stay reserved. Closed windows are removed automatically. The four default
shortcut slots remain visible even when none currently resolve to a window.
When you switch with a global shortcut, BetterMeets brings that source into view
automatically. Click the live source, or press its configured shortcut again, to
pause sharing. Repeat the same action to resume it.

Use the attached control bar below the strip to draw temporary annotations,
highlight mouse clicks, or show keystrokes on the Demo Stage. Annotation mode
places its drawing surface over the selected app window and mirrors that ink on
the shared Demo Stage. Drawing is limited to that selected window: its input
overlay suspends whenever another app, including BetterMeets, becomes active and
resumes when the selected source app returns. This keeps the Demo Stage draggable
and lets it move normally in front of or behind other windows. Enabling Draw with
a live source returns focus to that source app so drawing can begin immediately.
When a stroke closes into a rough circle or four-sided box, releasing the pointer
snaps it to a true circle or axis-aligned rectangle; other strokes remain
freehand. Each stroke fades automatically after the delay selected in Settings.
The tabbed Settings window also lets you choose the annotation color,
click-ripple color and size, and the size and light or dark appearance of
keystroke badges. Press
Escape, choose Done, or click the pencil again to leave annotation mode. Click
Keystroke highlighting asks for Accessibility access the first time you enable
it so BetterMeets can observe keys pressed in the app you are presenting. All
three presentation controls can be enabled before sharing or while sharing is
paused; annotations attach automatically when a live source becomes available.
Draw and click highlighting can remain enabled together, with click ripples
appearing above the temporary ink.

Turn on **Auto Polish** (the wand control) to produce a presentation-ready Demo
Stage without changing how you use the source app. A click starts an immediate,
temporary zoom around that activity. While zoomed, the camera stays still until
the pointer leaves a generous safe zone, then moves only enough to keep the
pointer visible. BetterMeets hides ScreenCaptureKit's embedded cursor and
mirrors the actual macOS system cursor—arrow, I-beam, pointing hand, resize
cursor, or another active shape—at exactly 2× in the Demo Stage. It preserves
the native hotspot, moves smoothly, and never controls the real pointer.

Auto Polish can also place the source in a styled frame. Open Settings → Stage
to choose a built-in backdrop and adjust padding, corners, background blur,
shadow, and zoom strength. The framing is applied only to the Demo
Stage, so the source window remains untouched. Auto Polish runs entirely from
mouse activity — no microphone or network request. (Demo Mode, below, is the one
feature that listens to the microphone, and only while you turn it on.)

Turn on **Demo Mode** (the waveform control) to drive the UI by voice while you
narrate. BetterMeets transcribes your narration entirely on device and matches
the control names you say against the buttons, links, and tabs in the window you
are presenting. Naming a control highlights it on the Demo Stage and gently
zooms to it — say "here's the new **Receive** button" and it lights up. Add an
action verb and BetterMeets performs the click for you — "let's **click**
**Discover**" glides the pointer to the Discover button and opens it, so the
navigation you are describing actually happens. The verb is the safety line:
nothing is clicked unless you say click, press, open, select, or a phrase like
"take us to". A small caption over your window shows what BetterMeets heard and
did; meeting viewers never see it.

Demo Mode finds controls through macOS Accessibility, falling back to on-screen
text recognition for canvas or web-rendered apps whose accessibility is sparse.
It needs microphone access (for transcription) and, to read controls and click
them, Accessibility access; BetterMeets requests both the first time you enable
it. If Accessibility is declined, Demo Mode still highlights controls it can read
but will not click. Set Settings → Demo → Voice actions to **Highlight only** to
keep BetterMeets from ever clicking. All transcription is on device; no audio or
audio leaves your Mac. Demo Mode stays entirely on device unless you explicitly
enable Cloud understanding in Settings; when enabled, each command sends the
transcript and a screenshot of the shared window to the provider you selected.

The live pipeline is intentionally bounded for presentation workloads. Smaller
sources keep their native pixel size, while 4K and 5K windows are scaled to a
maximum 2560-pixel edge at 30 fps. Pointer-driven effects share one monitor and
coalesce bursts to display cadence, so styled framing, zoom, ink, spotlight,
and click highlights do not queue duplicate work when used together.

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

BetterMeets has no third-party dependencies or package-install step.

BetterMeets is distributed directly and intentionally runs without App Sandbox
because window capture, global event observation, Accessibility inspection, and
opt-in input synthesis are core features. Hardened-runtime builds use a minimal
microphone entitlement. See [SECURITY.md](SECURITY.md) for the permission,
cloud-data, input-synthesis, and distribution threat model.

## Local development

The native equivalent of `pnpm dev` is:

```bash
./dev-app.sh
```

This command:

1. Builds the Swift package in debug mode.
2. Creates `dist/BetterMeets.app` with its Info.plist and icon.
3. Signs the app with its stable local identity.
4. Stops the previous BetterMeets process.
5. Launches the new build.

There is no hot reload. After changing Swift code, run `./dev-app.sh` again. The
build happens before the running app is stopped, so a compiler error leaves the
current instance alone.

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
| `pnpm install` | No equivalent; there are no external dependencies |
| `pnpm dev` | `./dev-app.sh` |
| Compile check | `swift build` |
| Optimized local build | `./build-app.sh` |
| Build artifacts | `.build/` and `dist/` |

## First run

1. Run `./dev-app.sh`.
2. Allow Screen & System Audio Recording when macOS asks. BetterMeets captures
   video only.
3. If macOS asks for a restart, select **Restart** in the controller.
4. Select a source window.
5. In your meeting, share **BetterMeets — Demo Stage**.
6. Switch sources from BetterMeets or your pinned global shortcuts.
7. Repeat the current source click or global shortcut to pause or resume it.
8. Optional: turn on Auto Polish and choose its framing and motion in Settings
   → Stage.

The BetterMeets controller is excluded from the source list. Your meeting keeps
capturing the same Demo Stage window while BetterMeets changes what appears
inside it.

## Project structure

| Path | Purpose |
| --- | --- |
| `Sources/MeetStage/MeetStageApp.swift` | SwiftUI app entry point and windows |
| `Sources/MeetStageCore/` | Framework-free authorization and cloud configuration policies, compiled as an independent SPM target |
| `Sources/MeetStage/CaptureServices.swift` | Injected thumbnail and cloud-provider service boundaries |
| `Sources/MeetStage/ControlView.swift` and `Control*.swift` | Floating controller composition, settings, reusable controls, preview rendering, and source-picker views |
| `Sources/MeetStage/CaptureManager.swift` and `CaptureManager+*.swift` | Main-actor state plus responsibility-focused discovery, command, lifecycle, presentation, and callback extensions |
| `Sources/MeetStage/Diagnostics.swift` | Categorized, privacy-aware unified logging |
| `Sources/MeetStage/WindowSourceDiscovery.swift` | Source eligibility, ScreenCaptureKit discovery, and thumbnails |
| `Sources/MeetStage/WindowGeometry.swift` | Canonical source coordinates, window-frame resolution, and overlay tracking |
| `Sources/MeetStage/GlobalLocalEventMonitor.swift` | Shared global/local AppKit event-monitor lifecycle for pointer effects |
| `Sources/MeetStage/ShortcutAssignments.swift` | Deterministic shortcut-assignment policy |
| `Sources/MeetStage/ShortcutPreferencesStore.swift` | Backward-compatible shortcut persistence |
| `Sources/MeetStage/SampleBufferRenderer.swift` | High-resolution frame rendering |
| `Sources/MeetStage/StageWindowSizing.swift` | Demo Stage geometry and aspect-ratio handling |
| `Sources/MeetStage/AutoPresentation.swift` and `CaptureManager+AutoPresentation.swift` | Click-driven zoom camera, read-only pointer tracking, and 2× native system-cursor mirroring |
| `Sources/MeetStage/StageFramePresentation.swift` | Styled-frame layout, built-in backdrops, blur, corners, and shadows |
| `Sources/MeetStage/WindowConfiguration.swift` | AppKit window behavior used by SwiftUI scenes |
| `Sources/MeetStage/GlobalHotKeyManager.swift` | Configurable global source-slot shortcut registration |
| `Sources/MeetStage/Annotations.swift`, `AnnotationShapeRecognizer.swift`, and `AnnotationOverlay.swift` | Temporary ink, closed-shape recognition and rendering, plus AppKit source-overlay presentation |
| `Sources/MeetStage/ClickHighlights.swift`, `KeystrokeHighlights.swift`, and `SpotlightEffect.swift` | Effect-specific models, monitoring, overlays, and rendering |
| `Sources/MeetStage/PresentationPreferences.swift` | Shared color, size, and keystroke appearance options |
| `Sources/MeetStage/StageLogoStore.swift` | Bounded image normalization and Application Support persistence |
| `Sources/MeetStage/WorkspaceObservationBag.swift` | App lifecycle observation and notification-token ownership |
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
`com.lndgalante.bettermeets` and the same designated signing requirement. Keep these
values stable: changing either can make macOS treat the build as a different
Screen Recording client.

If capture permission becomes stuck:

1. Open **System Settings → Privacy & Security → Screen & System Audio Recording**.
2. Confirm BetterMeets is enabled.
3. Quit BetterMeets and run `./dev-app.sh` again.

As a last resort, reset only BetterMeets' Screen Recording decision, then launch
the app and grant access again:

```bash
tccutil reset ScreenCapture com.lndgalante.bettermeets
```

Demo Mode adds two more permissions, keyed to the same stable identity:
Microphone (for on-device transcription) and Accessibility (to read and click
controls in the app you are presenting). Grant them under **System Settings →
Privacy & Security → Microphone** and **→ Accessibility**. If either becomes
stuck, reset only BetterMeets' decision and re-grant it:

```bash
tccutil reset Microphone com.lndgalante.bettermeets
tccutil reset Accessibility com.lndgalante.bettermeets
```

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
codesign --verify --deep --strict "dist/BetterMeets.app"
git diff --check
```

GitHub Actions repeats formatting, metadata, tests, and warnings-as-errors
debug/release compilation for every push and pull request on an Apple Silicon
macOS runner.

The automated suite covers window eligibility, deterministic shortcut
assignment, persisted preference compatibility, corrupt preference recovery,
auto-zoom and styled-frame geometry, presentation and annotation policies,
stage sizing, and AppKit stage interaction. For ScreenCaptureKit, global-hotkey,
or controller changes, also
test the complete flow manually in a meeting because those APIs require real
windows and macOS privacy consent.

## Release builds

Create the optimized local build with:

```bash
./build-app.sh
```

The result is `dist/BetterMeets.app`. It is ad-hoc signed for local use and is
not notarized for public distribution.

For a public build, provide a Developer ID Application identity. The packaging
script enables the hardened runtime and trusted timestamp automatically:

```bash
BETTERMEETS_CODESIGN_IDENTITY="Developer ID Application: Example Corp (TEAMID)" \
    ./build-app.sh
```

Store App Store Connect credentials in the Keychain once, using Apple's
`notarytool store-credentials` command. Then submit, wait for acceptance, staple
the ticket, run Gatekeeper verification, and create a distributable
`dist/BetterMeets.zip` with:

```bash
BETTERMEETS_NOTARY_PROFILE="bettermeets-notary" \
    ./scripts/notarize-app.sh
```

Before publishing, increment both version fields in `Resources/Info.plist`, run
the complete verification commands above, and manually exercise first-run
permissions, capture switching, pause/resume, all presentation effects, and
global shortcuts on a clean macOS user account. Apple signing credentials and
notarization are intentionally external to the repository.

## Known limitations

- Source audio is not captured; the microphone is used only by Demo Mode, and
  only while it is turned on.
- Auto Polish starts zooms from clicks and does not read page content or speech;
  the voice-driven behavior lives in Demo Mode instead.
- Demo Mode matches spoken control names against visible controls; it cannot
  target a control that is scrolled off screen or has no readable name.
- Styled frames use built-in gradients and colors; custom image wallpapers are
  not yet supported.
- macOS may block protected video surfaces, causing them to appear black.
- Keep the Demo Stage open while it is being shared.
- If an app restores two windows with the same title, its pinned shortcut stays
  unavailable instead of guessing.
