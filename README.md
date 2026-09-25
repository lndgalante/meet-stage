# BetterMeets

**Stay in flow. Look polished.**

BetterMeets is a lightweight macOS app for smoother live software demos. Share
one stable Demo Stage in your meeting, then switch between app windows without
reopening the share picker or exposing your desktop.

## How it works

BetterMeets brings tools, window selection, and the live stage into one resizable
Mac window. The left sidebar stacks presentation tools above a vertical list of
window thumbnails. The main area shows the selected source at its original
aspect ratio. The bottom strip shows status and provides Open App and Stop actions.

Choose a thumbnail to put a window on stage. Click it again to pause, and again
to resume. The toolbar also offers Pause/Resume (Shift–Command–P). A source is
marked live only after ScreenCaptureKit delivers its first complete video frame.
The window keeps the size and position you chose when sources change.

Share **BetterMeets** in your meeting app. Choose **View → Stage Only**
(Control–Command–S) to hide the tools, window list, status strip, and toolbar.
Press the same shortcut or Escape to restore controls. Use the standard green
traffic light for full screen while controls are visible. Returning
to controls while sharing makes them visible to your audience.

The stage is a live presentation surface. Use **Open App** (Shift–Command–O) to
interact with the original source window. Cursor, ink, and pointer effects follow
the selected source while its application is frontmost.

BetterMeets assigns **Option–1** through **Option–9** to available windows.
Change the modifier or disable global shortcuts in Settings → General. Right-click
a thumbnail to pin or unpin a slot. Pins survive launches and reserve their slot
when the source is unavailable. An ambiguous window identity is never guessed.
Scroll vertically to browse sources; Up/Down and Return select by keyboard, and
Space opens a larger preview. Source shortcuts also scroll the selected tile
into view. New and closed windows update automatically.

The six tool rows provide Auto Polish, Spotlight, Annotate, Click Highlights,
Keystrokes, and Settings. Right-click a tool to open its settings. Settings opens
as a native popover from the gear and remains available through Command–comma.

The same tools also appear in the compact floating widget beside the selected
source window. It follows moves and resizes, uses the right or left gutter when
space allows, and stays inside the screen. It remains available in Stage Only
mode and hides when the source is unavailable or another app is frontmost.
The widget is a separate window; sharing the BetterMeets workspace excludes it.
Window → Show Source Tools (Control–Command–T) brings it forward for keyboard use.

- **Auto Polish** adds a styled frame, temporarily zooms around clicks, and
  mirrors the macOS cursor at 2× without moving the real pointer. Settings → Stage
  selects the backdrop and optional logo.
- **Spotlight** follows the source pointer with a focused circle and dims the
  surrounding content. Settings → Focus adjusts size and outside opacity.
- **Annotate** draws temporary ink over the original source and mirrors it on
  stage. Closed strokes can snap to circles or rectangles. Escape finishes drawing;
  Command–Z undoes strokes. Settings → Draw sets color and fade time.
- **Click Highlights** shows ripples at source clicks. **Keystrokes** displays
  shortcut badges on stage and requests Accessibility when first enabled.

The capture pipeline keeps smaller sources at native resolution and caps larger
sources at a 2560-pixel edge, at 30 fps. Presentation effects share pointer
monitoring. VoiceMode, speech recognition, AI providers, and input synthesis have
been removed; BetterMeets neither records microphone audio nor sends captured
content to an AI service.

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
library validation and require no microphone entitlement. See [SECURITY.md](SECURITY.md).

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
3. If macOS asks for a restart, select **Restart BetterMeets** in the sidebar.
4. Select a source window.
5. In your meeting, share **BetterMeets** and enable **Stage Only**.
6. Switch sources from BetterMeets or your pinned global shortcuts.
7. Repeat the current source click or global shortcut to pause or resume it.
8. Optional: turn on Auto Polish and choose its framing and motion in Settings
   → Stage.

BetterMeets windows are excluded from the source list. Your meeting keeps
capturing the same workspace window while BetterMeets changes what appears
inside it.

## Project structure

| Path | Purpose |
| --- | --- |
| `Sources/MeetStage/MeetStageApp.swift` | SwiftUI scenes and menu commands |
| `Sources/MeetStage/WorkspaceView.swift` | Unified workspace layout and Stage Only mode |
| `Sources/MeetStageCore/` | Framework-free capture frame validation and bounded concurrency, compiled as an independent SPM target |
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
System Settings → Privacy & Security → Accessibility.

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
stage sizing, and AppKit stage interaction. For ScreenCaptureKit, global-hotkey,
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
- Keep the Demo Stage open while it is being shared.
- If an app restores two windows with the same title, its pinned shortcut stays
  unavailable instead of guessing.
