---
name: BetterMeets
description: A native macOS workspace for choosing, polishing, and presenting app windows.
rounded:
  panel: "16pt"
  source: "8pt"
  keycap: "5pt"
  action: "8pt"
spacing:
  workspace: "12pt"
  detail: "4pt"
components:
  sidebar:
    width: "88pt"
  source-preview:
    rounded: "{rounded.source}"
  action-button:
    height: "30pt"
  status:
    height: "40pt"
---

# BetterMeets design system

## Overview

One native window contains the presentation workspace. A compact, vertically scrolling app-icon rail sits on the left. The source preview fills the
remaining area at its own aspect ratio. Current state, source title, Pause Stage/Resume Stage,
and Clear Stage sit above the preview. An edge-to-edge demo strip below the rail and
stage holds the prompt composer, then the editable sequence and playback controls.
Keep the preview dominant as the demo moves between building, checking, and playback.

## Window behavior

Keep the standard traffic lights, title-bar dragging, native resizing, and full
screen. The initial content size is 1180 × 780 points, with an 800 × 560 minimum.
Remember size and position. Switching sources never resizes the workspace.

Stage Only hides tools, sources, status, and toolbar. Control–Command–S toggles
it; Escape restores controls when annotation mode is inactive. Restore controls
to access the traffic lights. Never imply that visible workspace controls are
excluded from window sharing.

## Materials and typography

Use semantic system backgrounds, regular material, and SF system text. The
stage well uses the system under-page color. Black is reserved for thumbnail
letterboxing and captured imagery. Unstyled capture has a transparent backdrop,
so rounded source corners reveal the stage well. System accent marks active tools and the
selected source; orange indicates paused, pending, or permission states.

Panels use 16-point rounded corners and a subtle inset edge. Reduce Transparency
replaces materials with a solid system control background. Increase Contrast
strengthens edges. Semantic font styles and inherited legibility weight support
Bold Text. Source details also appear in previews and accessibility labels.

## Tools and sources

Presentation tools remain available in the menu bar, Settings, and floating source
widget. Command–comma opens the native Settings window. Keep its sidebar and size
stable across panes, and show each effect’s governing On/Off state beside its preview.

The floating source widget uses the same actions as an icon-only vertical rail:
56 × 381 points for ten buttons, 18-point corners, 28-point buttons, and 6-point spacing. Preserve
its translucent material and inset edge. It follows the selected source, prefers
the right gutter then the left, and falls inside the source when neither fits.
It stays separate from the shared workspace and remains available in Stage Only.
Its demo playback, Pause Stage/Resume Stage, Clear Stage, and Show Controls actions precede effects.

The window rail is fixed at 88 points wide, with 56-point application icons in
68-point tiles. It shows no inline titles or thumbnails. A compact capsule at the bottom-right
of each tile displays its assigned shortcut.
Hover and Space previews show the full window title, thumbnail, and shortcut,
including for multiple windows belonging to the same app. Selection and keyboard focus outline the tile without changing
layout. Paused and pending sources use an orange outline and a top-right state indicator.
Unavailable pinned windows retain a compact Unpin control; empty slots consume no space.
Preserve system scroll indicators. Selecting the current live source keeps it live;
pausing is an explicit action.

Up/Down moves source focus, Return selects, and Space previews. Hover previews
appear after a short dwell to avoid distracting accidental passes. Selected and
keyboard-focused windows scroll into view. All controls have accessibility
labels, visible hover and keyboard focus, and press feedback.

## Motion

Source focus scrolls only enough to reveal the target, without animation.
Stage Only and source-state changes are immediate. Hover uses a 0.12-second
transition; presses use 0.10 seconds, 0.96 scale, and 0.82 opacity. Reduce Motion
removes transitions and scaling while retaining state feedback. Input stays
available during every transition.

## Components

### Real-time demos

The bottom strip shares the workspace's semantic colors and SF text. Its initial
state pairs a short feature label with a one-to-three-line prompt field, a prominent
Build Demo action, and a Demo Setup button. Once a demo exists, the strip has three
rows. The first shows the title, a caption (steps so far, check progress, or step
count with “paced by your voice” while Follow my voice is on, otherwise the estimated
length), a status pill, a secondary “Writing the script…” label
with a sparkles icon while Claude writes the narration, the current phase's actions,
a speech-bubble Presenter Notes button once the demo is built (filled while the panel
shows), and an options menu. The second is a horizontally scrolling sequence of step
chips. The third is one contextual line. Phase changes ease out over 0.18 seconds.

Chips appear live while building, followed by dashed-outline chips for outline beats
still to come. Keep the current step visible; use the system accent for its fill and
icon, and an accent underline for completed steps. Step titles use callout text;
numbers, captions, status, and the contextual line use caption text, and warnings
use callout. Orange marks paused, attention, and recovery states; green marks
Checked. Pills read Checked, Not checked, Not at the start, Build paused, Paused, or
Needs attention.

Show only the actions the phase allows. Building and returning to the start offer
Stop. A paused build offers Keep Building, Use N Steps, and Discard. An approval
offers Allow and Skip, circling the control in question. A blocked request offers
Show … Instead with the closest real alternative, which returns to the start and
rebuilds, Edit Request, and Use N Steps. Not at the start offers Return to Start;
Check when no automatic return exists or the page isn't exposed; both when only
switches differ; plus Play Anyway unless a check is waiting. Actions that drive the
app, including Return to Start, Check, Skip Step, and Continue from Step N, are
disabled while the source isn't live. Ready offers Play Demo and Next Step.
Checking offers Stop Check; playing offers Pause Demo. Paused offers Continue or
Continue Check, Next Step while presenting, and an icon-only Return to Start. Off
track offers Try Again, Skip Step while presenting, and an icon-only Return to
Start; a wrong screen adds Continue from Step N to the contextual line. Finished
offers Return to Start and Play Again.

The contextual line shows the current activity while building or checking, the
current line in larger 17-point text while presenting, the starting view when ready,
the closing line at the end, and recovery messages otherwise. While Follow my voice
is listening, words already said turn secondary, the next word takes the accent color
with an underline, and an accent waveform marks a line the demo is waiting for. A step
without a line reads “Say ‘next’ to continue” while following the voice, otherwise “No
line for this step”, in secondary text. API
errors add Copy Details; a step that moved during playback adds Check Again. Before
the first build in an app, it becomes a consent row explaining that BetterMeets will
operate the app in the background for a minute or two while the presenter watches
the stage, that clicking or typing inside the app pauses the build, and that viewers
of a shared BetterMeets window will see it, with Not Now and Build.

Once steps are recorded, the options menu holds Edit Steps, Presenter Script, Check
Again, Return to Start, Speed, and Pause After Each Step, followed by Demo Setup and
New Demo. Speed defaults to 2× and offers 1×, 1.5×, 2×, and 3×; it affects only timed
playback, shortening pauses and silent steps, never the time a line takes to say.
While Follow my voice is on, the presenter sets the pace: the options menu and the
Demo menu hide Speed, and Demo Setup disables it with a help tag explaining why. Pause
After Each Step also appears in Demo Setup and the Demo menu. Playback advances
automatically by default.

Edit Steps opens a native sheet with the title, starting view, closing line, and
ordered steps. Each step shows its number, action icon, editable title, a read-only
action summary, a hold stepper, and an optional script. Removing an action confirms
that it and every later step will go; the footer explains that words and timing keep
the check. Script opens a readable sheet with the opening line, all step scripts, the
closing line, the current step marked, and a Copy Script action. One row above the
lines holds a Tone picker (Conversational, Concise, Technical), an audience-or-notes
field, and Rewrite Script; while Claude writes, the button becomes a small spinner and
the lines fade to 45% opacity. A failed rewrite shows its reason below that row in
orange caption text. Edit Steps is unavailable while BetterMeets drives
the app. Demo Setup uses a popover with native fields and toggles: the API key
(Return or Save stores it), the consent toggle and its plain-language explanation
that BetterMeets operates the app in the background, playback options, Open presenter
notes when playing with a caption to share the BetterMeets window, not the whole
screen, to keep notes private, Follow my voice (on by default) with a short note that
the presenter sets the pace (each step moves on when its line is finished or the
presenter says “next”, and steps without a line wait for “next”), that the next word
is highlighted, and that speech stays on this Mac, and Accessibility status.

Presenter Notes is a floating, nonactivating utility panel with a transparent title
bar and regular material, 620 × 230 points at first (at least 380 × 160), placed near
the top center of the screen, close to the camera, until the presenter moves it. Its
header shows the step position in monospaced digits, the step title, the Follow my
voice toggle (a microphone with a live level capsule while listening), and Smaller
and Larger text buttons. The line uses medium SF Rounded at 26 points by default
(16–48), with the same said-word and next-word styling as the strip; the highlight
eases over 0.15 seconds. A step without a line shows “Say ‘next’ to continue.” in
secondary text while following the voice. The footer shows an accent waveform label,
“Finish the line or say ‘next’” (or “Say ‘next’ to continue” on a step without a
line), with Skip while the demo waits for the voice, otherwise a thin progress bar
during timed holds with Skip, then
“Next:” and the next step's title in secondary caption text.

**The Separate Pauses Rule.** Pause Demo stops the sequence while preserving the
live app and current visual cue. Pause Stage hides the source image. Name both
actions explicitly wherever they appear together, including the floating widget,
whose demo button reads Play Demo, Pause Demo, Continue, Stop Building, Keep
Building, Pause Check, or Return to Start when the app isn't at the start.

Demo effects use the existing presentation vocabulary: spotlight, magnification,
drawn emphasis, click highlights, and displayed keystrokes. Because demos run the
app in the background, a virtual system arrow glides to each target on the stage
and demo clicks ripple on the stage only. Drawn emphasis uses the system accent;
Reduce Motion shows it, and moves the virtual cursor, immediately. Spotlight
edges strengthen with Increase Contrast. Effects do not intercept input or add screen-reader content.

## Setup and recovery

The idle workspace teaches two steps: choose a source window, then share BetterMeets.
Stage Only remains available through the View menu and keyboard shortcut. Use “On stage” for local capture;
BetterMeets does not know whether a meeting is transmitting the window.

Presenter controls show specific setup and recovery actions. Audience placeholders
stay brief and contain no raw error diagnostics or operator instructions. Pausing
the stage hides the source image; it does not freeze its last frame. The in-app presentation
guide remains available from Help.
