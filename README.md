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

BetterMeets automatically assigns **Option+1** through **Option+9** to the first
nine available windows. Right-click a source to move it to a specific shortcut
or unpin it. Manual pins remain stable across refreshes and app launches, and an
explicitly unpinned window stays unassigned until you pin it again. If the exact
window for a manual pin is unavailable or ambiguous, BetterMeets keeps the
shortcut reserved instead of silently pointing it somewhere else.

Swipe or scroll horizontally over the window strip to browse every available
source. Newly opened windows appear automatically. Minimized or hidden windows
temporarily leave the strip and return when restored, while their pinned slots
stay reserved. Closed windows are removed automatically. The four default
shortcut slots remain visible even when none currently resolve to a window.
When you switch with a global shortcut, BetterMeets brings that source into view
automatically. Click the live source, or press its Option shortcut again, to
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
The tabbed Settings popover also lets you choose the annotation color,
click-ripple color and size, and the size and light or dark appearance of
keystroke badges. Press
Escape, choose Done, or click the pencil again to leave annotation mode. Click
highlighting uses ScreenCaptureKit on macOS 15 and later.
Keystroke highlighting asks for Accessibility access the first time you enable
it so BetterMeets can observe keys pressed in the app you are presenting. All
three presentation controls can be enabled before sharing or while sharing is
paused; annotations attach automatically when a live source becomes available.
Draw and click highlighting can remain enabled together, with click ripples
appearing above the temporary ink.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Swift 6 and the macOS SDK from Xcode or the Command Line Tools

Install the Command Line Tools if needed:

```bash
xcode-select --install
```

Confirm that Swift is available:

```bash
swift --version
```

BetterMeets has no third-party dependencies or package-install step.

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
6. Switch sources from BetterMeets or your pinned Option shortcuts.
7. Repeat the current source click or Option shortcut to pause or resume it.

The BetterMeets controller is excluded from the source list. Your meeting keeps
capturing the same Demo Stage window while BetterMeets changes what appears
inside it.

## Project structure

| Path | Purpose |
| --- | --- |
| `Sources/MeetStage/MeetStageApp.swift` | SwiftUI app entry point and windows |
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
| `Sources/MeetStage/WindowConfiguration.swift` | AppKit window behavior used by SwiftUI scenes |
| `Sources/MeetStage/GlobalHotKeyManager.swift` | Option+1 through Option+9 registration |
| `Sources/MeetStage/Annotations.swift`, `AnnotationShapeRecognizer.swift`, and `AnnotationOverlay.swift` | Temporary ink, closed-shape recognition and rendering, plus AppKit source-overlay presentation |
| `Sources/MeetStage/ClickHighlights.swift`, `KeystrokeHighlights.swift`, and `SpotlightEffect.swift` | Effect-specific models, monitoring, overlays, and rendering |
| `Sources/MeetStage/PresentationPreferences.swift` | Shared color, size, and keystroke appearance options |
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
`dev.poc.meetstage.v2` and the same designated signing requirement. Keep these
values stable: changing either can make macOS treat the build as a different
Screen Recording client.

If capture permission becomes stuck:

1. Open **System Settings → Privacy & Security → Screen & System Audio Recording**.
2. Confirm BetterMeets is enabled.
3. Quit BetterMeets and run `./dev-app.sh` again.

As a last resort, reset only BetterMeets' Screen Recording decision, then launch
the app and grant access again:

```bash
tccutil reset ScreenCapture dev.poc.meetstage.v2
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
presentation and annotation policies, stage sizing, and AppKit stage
interaction. For ScreenCaptureKit, global-hotkey, or controller changes, also
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

- Video only; source audio is intentionally not captured.
- macOS may block protected video surfaces, causing them to appear black.
- Keep the Demo Stage open while it is being shared.
- If an app restores two windows with the same title, its pinned shortcut stays
  unavailable instead of guessing.
