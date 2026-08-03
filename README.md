# Meet Stage PoC

Meet Stage is a small macOS proof of concept for switching the video source shown in Google Meet without reopening Meet's screen picker.

It has two windows:

- **Meet Stage** is the floating controller with live thumbnails of shareable windows.
- **Meet Presenter Stage** is the fixed 16:9 output window. This is the only window you share with Google Meet.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Swift Command Line Tools (already installed on the development machine)

## Build

From this folder, run `./build-app.sh`.

The resulting application is `dist/Meet Stage.app`.

## First run

1. Open `dist/Meet Stage.app`.
2. Allow Screen & System Audio Recording when macOS asks. The app only captures video.
3. If macOS asks you to restart the app, quit Meet Stage and open it again.
4. Select a source window in the controller.
5. In Google Meet, present the window named **Meet Presenter Stage**.
6. Return to the controller and click other windows to switch the stage instantly.

The controller belongs to Meet Stage itself and is excluded from the source list. Because Meet keeps capturing the same Presenter Stage window, switching sources does not trigger Chrome's chooser again.

## Known PoC limitations

- Video only; source audio is intentionally not captured.
- Closed or newly opened windows require pressing **Refresh Windows**.
- Some protected video surfaces may appear black because macOS blocks their capture.
- Keep the Presenter Stage window open while it is shared.
- The app is ad-hoc signed for local use, not notarized for distribution.
