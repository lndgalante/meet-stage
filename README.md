# BetterDemos

**Stay in flow. Look polished.**

BetterDemos is a lightweight macOS app for smoother live software demos. Share
one stable Demo Stage in your meeting, then switch between app windows without
reopening the share picker or exposing your desktop.

## How it works

BetterDemos has two windows:

- **BetterDemos** is a compact floating controller with three visible previews
  in a horizontally scrolling window strip, plus global shortcuts.
- **BetterDemos — Demo Stage** is the clean, high-resolution output window. This
  is the only window you share in Google Meet or another meeting app.

The Demo Stage follows the selected window's aspect ratio and capture dimensions
to avoid unnecessary black padding. A source appears as **Live** only after
ScreenCaptureKit delivers a complete video frame. The controller keeps the name
of the current live window visible below the source strip. The pointer appears
on the Demo Stage only while the selected source application is active, so
moving through a different app does not leak its cursor position into the demo.

BetterDemos automatically assigns **Option+1** through **Option+9** to the first
nine available windows. Right-click a source to move it to a specific shortcut
or unpin it. Manual pins remain stable across refreshes and app launches, and an
explicitly unpinned window stays unassigned until you pin it again. If the exact
window for a manual pin is unavailable or ambiguous, BetterDemos keeps the
shortcut reserved instead of silently pointing it somewhere else.

Swipe or scroll horizontally over the window strip to browse every available
source. Newly opened windows appear automatically, and closed windows are
removed automatically. When you switch with a global shortcut, BetterDemos
brings that source into view automatically.

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

BetterDemos has no third-party dependencies or package-install step.

## Local development

The native equivalent of `pnpm dev` is:

```bash
./dev-app.sh
```

This command:

1. Builds the Swift package in debug mode.
2. Creates `dist/BetterDemos.app` with its Info.plist and icon.
3. Signs the app with its stable local identity.
4. Stops the previous BetterDemos process.
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

| JavaScript workflow | BetterDemos |
| --- | --- |
| `pnpm install` | No equivalent; there are no external dependencies |
| `pnpm dev` | `./dev-app.sh` |
| Compile check | `swift build` |
| Production build | `./build-app.sh` |
| Build artifacts | `.build/` and `dist/` |

## First run

1. Run `./dev-app.sh`.
2. Allow Screen & System Audio Recording when macOS asks. BetterDemos captures
   video only.
3. If macOS asks for a restart, select **Restart** in the controller.
4. Select a source window.
5. In your meeting, share **BetterDemos — Demo Stage**.
6. Switch sources from BetterDemos or your pinned Option shortcuts.

The BetterDemos controller is excluded from the source list. Your meeting keeps
capturing the same Demo Stage window while BetterDemos changes what appears
inside it.

## Project structure

| Path | Purpose |
| --- | --- |
| `Sources/MeetStage/MeetStageApp.swift` | SwiftUI app entry point and windows |
| `Sources/MeetStage/ControlView.swift` | Floating controller and source picker |
| `Sources/MeetStage/CaptureManager.swift` | Capture lifecycle, live state, and shortcut persistence |
| `Sources/MeetStage/SampleBufferRenderer.swift` | High-resolution frame rendering |
| `Sources/MeetStage/StageWindowSizing.swift` | Demo Stage geometry and aspect-ratio handling |
| `Sources/MeetStage/GlobalHotKeyManager.swift` | Option+1 through Option+9 registration |
| `Resources/Info.plist` | Bundle name, version, permissions, and icon metadata |
| `Brand/` | BetterDemos icon masters and brand guidance |
| `dev-app.sh` | Debug build, package, sign, and relaunch workflow |
| `build-app.sh` | Release build and packaging workflow |

The Swift package and executable retain the internal name `MeetStage`. The app
bundle and every user-facing surface use the BetterDemos product name.

## Screen Recording permission

Both development and release builds use bundle identifier
`dev.poc.meetstage.v2` and the same designated signing requirement. Keep these
values stable: changing either can make macOS treat the build as a different
Screen Recording client.

If capture permission becomes stuck:

1. Open **System Settings → Privacy & Security → Screen & System Audio Recording**.
2. Confirm BetterDemos is enabled.
3. Quit BetterDemos and run `./dev-app.sh` again.

As a last resort, reset only BetterDemos' Screen Recording decision, then launch
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
"dist/BetterDemos.app/Contents/MacOS/MeetStage"
```

Quit any existing BetterDemos instance first. You can also inspect logs in
Console.app by filtering for `BetterDemos` or `MeetStage`.

There is no automated test suite yet. Before handing off a change, run:

```bash
swift build
./build-app.sh
plutil -lint Resources/Info.plist
codesign --verify --deep --strict "dist/BetterDemos.app"
git diff --check
```

For capture, sizing, shortcut, or controller changes, also test the complete
flow manually in a meeting.

## Release build

Create the optimized local build with:

```bash
./build-app.sh
```

The result is `dist/BetterDemos.app`. It is ad-hoc signed for local use and is
not notarized for public distribution.

## Known limitations

- Video only; source audio is intentionally not captured.
- macOS may block protected video surfaces, causing them to appear black.
- Keep the Demo Stage open while it is being shared.
- If an app restores two windows with the same title, its pinned shortcut stays
  unavailable instead of guessing.
