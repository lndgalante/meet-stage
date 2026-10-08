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
The selected source occupies the main area, with source status and capture
actions above it. The bottom strip holds a prompt-based live demo composer,
editable steps, and playback controls.

A compact floating feature widget follows the selected source window, keeping
the same presentation tools close to the app the presenter is using.

Stage Only hides the sidebar, bottom strip, and toolbar for window sharing.
Control–Command–S or Escape restores controls. Reopening the controls makes them
visible to viewers of that shared window. The separate source widget remains
available in Stage Only mode.

## Capabilities

- Source thumbnails, app icons, window titles, hover previews, and keyboard preview.
- Select and switch sources; explicitly pause, resume, or clear the stage; open the original source app.
- Configurable global slots 1–9, persistent pins, unavailable slots, and conflicts.
- Auto Polish, Spotlight, temporary annotations, click ripples, and keystroke badges.
- Native settings, window controls, resizing, full screen, and frame restoration.
- Permission, loading, empty, pending, paused, live, and failure states.

Real-time demos turn a prompt into a walkthrough of the selected app. Claude
operates the real app one action at a time, so every step targets something
that was on screen; BetterMeets then returns to the start and plays the demo
back, marking it checked only after a pass in which every step succeeds.
Requests the app can't show stop with the closest real alternative.
BetterMeets operates the app in the background through Accessibility while the
presenter stays in BetterMeets and watches the stage, where a virtual cursor
glides to each target. Checked demos need no AI and pause only when the
presenter clicks, scrolls, or types in the source app itself. A code-enforced
policy keeps demos away from destructive controls and credentials, and asks
before anything unusual. Demos, with editable scripts, titles, and timing, stay
on this Mac. Anthropic access is
opt-in, with keys in Keychain.

After each build, Claude rewrites the narration as one story, with an opening
line, a line and short title per step, and a closing line, without affecting the
check; the presenter can rewrite it in a chosen tone for a described audience. A
floating Presenter Notes teleprompter shows the current line and what comes
next; it asks macOS to keep it out of screen sharing, and sharing the BetterMeets
window rather than the whole screen keeps it private. Follow my voice, on by
default, transcribes the presenter on the Mac while presenting, highlights the
next word, and lets the presenter set the pace with no timers: each step moves
on a beat after its line is said or when the presenter says “next”, and a step
without a line waits for “next”. With voice off or the microphone unavailable,
lines are timed at speaking pace, which playback speed never shortens. Nothing
is saved or sent. VoiceMode remains removed.

## Design principles

Recognizable windows and clear live state. Compact, labeled tools. Native system
fonts, materials, and accent color. Stable window geometry as sources change.
Keyboard and VoiceOver access; Reduce Motion, Reduce Transparency, Increase
Contrast, and Bold Text support.
