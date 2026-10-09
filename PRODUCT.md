# BetterMeets

<!-- impeccable:product-schema 1 -->

## Platform and users

Native macOS, using SwiftUI and AppKit. Built for people presenting app windows
in Google Meet, Zoom, and other meeting apps.

## Product purpose

Keep one shared window while switching the app content shown on its stage.
Unify window selection, presentation tools, and preview in one workspace.

## Operating context

A resizable window places a full-height vertical window selector on the left.
The selected source occupies the main area, with a demo panel below it. The
window toolbar names the app on stage and its state, and holds the presentation
effects, Pause Stage, and Clear Stage. The demo panel holds a list of the app's
demos beside the open demo's status, steps and playback controls, and keeps one
height while a demo plays, pauses, or finishes. A new demo starts from a
prompt-based composer with starter ideas (two fixed, three that Claude finds in
the app's own features). While BetterMeets operates the app, a multi-hue glow
traces the stage's edge.

A compact floating feature widget follows the selected source window, keeping
demo playback, Pause Stage, and every presentation effect close to the app the
presenter is using, with Clear Stage and Settings in its More menu.

Stage Only hides the sidebar, demo panel, and toolbar for window sharing.
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
back, marking it tested only after a test run in which every step succeeds.
Requests the app can't show stop with the closest real alternative, and a
separate window an action opens is closed and left out while the build goes on.
BetterMeets operates the app in the background through Accessibility. While a
demo builds or tests, the presenter stays in BetterMeets and watches the stage,
where a virtual cursor glides to each target; Play brings the app's window to
the front so the presenter presents from the app itself, with the teleprompter
under the camera and the floating widget beside the window. Tested demos find
their targets on the Mac and pause only when the presenter clicks, scrolls, or
types in the source app itself (a presentation remote's keys move the demo on or
back instead);
while Claude access is on, a control that moved can be found again from one
screenshot and the element list sent to Anthropic. A code-enforced
policy keeps demos away from destructive controls and credentials, and asks
before anything unusual. Each app keeps any number of demos on this Mac, which
the presenter can rename, edit, or delete from the demo list, and each names the
screen it starts on in a few words. Anthropic access is opt-in, asked once for every
app the first time BetterMeets opens, with keys in Keychain. While presenting,
the presenter can step back to the previous step or start over from the opening
line.

After each build, Claude rewrites the narration as one story, with an opening
line, a line and distinct short title per step, and a closing line, without
affecting the test; the presenter can rewrite it in a chosen tone for a described
audience. A script language (Same as My Request by default, or English, Spanish,
Portuguese, French, German, Italian, Dutch, Japanese, Korean or Chinese) sets the
language of the demo title, step titles, lines and start label for builds,
rewrites and ideas; the teleprompter follows the presenter's voice in it. A dark teleprompter hangs just under the camera, so reading the
current line looks like talking to the audience, and shows what comes next; it
asks macOS to keep it out of screen sharing, and sharing the BetterMeets window
rather than the whole screen keeps it private. Follow my voice, on by default,
transcribes the presenter on the Mac while presenting, highlights the next word,
and lets the presenter set the pace with no hold timers: each step moves on a
beat after its line is said, after most of it is said in the presenter's own
words followed by a pause, or when the presenter says “next”, and a step without
a line moves on after a short beat. With voice off or the microphone unavailable,
lines are timed at speaking pace, which playback speed never shortens. Nothing
is saved or sent. VoiceMode remains removed.

## Design principles

Recognizable windows and clear live state. Compact, labeled tools. Native system
fonts, materials, and accent color. Stable window geometry as sources change.
Keyboard and VoiceOver access; Reduce Motion, Reduce Transparency, Increase
Contrast, and Bold Text support.
