# BetterMeets

<!-- impeccable:product-schema 1 -->

## Platform and users

Native macOS, using SwiftUI and AppKit. Built for people presenting app windows
in Google Meet, Zoom, and other meeting apps.

## Product purpose

Keep one shared window while switching the app content shown on its stage.
Unify window selection, presentation tools, and preview in one workspace.

## Operating context

A resizable window stacks tools above a vertical window selector on the left.
The selected source occupies the main area. A bottom strip provides status and
capture actions, with room for future presentation features.

A compact floating feature widget follows the selected source window, keeping
the same presentation tools close to the app the presenter is using.

Stage Only hides the sidebar, bottom strip, and toolbar for window sharing.
Control–Command–S or Escape restores controls. Reopening the controls makes them
visible to viewers of that shared window. The separate source widget remains
available in Stage Only mode.

## Capabilities

- Source thumbnails, app icons, window titles, hover previews, and keyboard preview.
- Select, switch, pause, resume, and stop capture; open the original source app.
- Configurable global slots 1–9, persistent pins, unavailable slots, and conflicts.
- Auto Polish, Spotlight, temporary annotations, click ripples, and keystroke badges.
- Native settings, window controls, resizing, full screen, and frame restoration.
- Permission, loading, empty, pending, paused, live, and failure states.

VoiceMode, microphone transcription, AI providers, and synthesized input are removed.

## Design principles

Recognizable windows and clear live state. Compact, labeled tools. Native system
fonts, materials, and accent color. Stable window geometry as sources change.
Keyboard and VoiceOver access; Reduce Motion, Reduce Transparency, Increase
Contrast, and Bold Text support.
