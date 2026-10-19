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
  header-source-icon:
    size: "24pt"
  stage-actions:
    width: "56pt"
    height: "316pt"
    rounded: "18pt"
  demo-panel:
    rounded: "{rounded.panel}"
    padding: "16pt"
    height: "168pt"
    max-composing-height: "200pt"
  demo-library:
    width: "20%"
    min-width: "160pt"
    max-width: "240pt"
    row-height: "24pt"
  demo-request-field:
    rounded: "14pt"
  demo-step-marker:
    size: "16pt"
  demo-step-row:
    height: "18pt"
  teleprompter:
    width: "460–700pt (500pt at 26pt text)"
    shoulder: "16pt"
    rounded: "20pt"
    control: "28pt"
---

# BetterMeets design system

## Overview

One native window contains the presentation workspace, with no title bar. A compact,
vertically scrolling app-icon rail runs the full height on the left, with the window's
close, minimize, and zoom buttons centered in its top row. Beside it, a column stacks
the header card, the stage, and the demo panel, 12 points apart; until a window is
chosen, the demo panel is hidden and the stage's setup guidance fills the column below
the header. The source preview fills the stage at its own aspect ratio. The header
card names the app on stage, its state, and its window title on the leading edge, and
holds the effect toggles, Pause Stage/Resume Stage, and Clear Stage on the trailing
edge. The demo panel holds a list of the app's demos beside the open demo's status,
steps, and playback controls. Keep the preview dominant as the demo moves between
building, testing, and playback.

## Window behavior

The window has no title bar, but keeps the standard window buttons, title-bar
dragging, native resizing, and full screen. The buttons sit centered in the rail's top
row, level with the header card, and move to the menu bar in full screen as usual. The
source title, the header card's empty space, the rail's top row, and the gutters
between the cards move the window, and a double-click there does what System Settings
asks of a title bar. The initial content size is 1180 × 780 points, with an 800 × 560
minimum. Remember size and position. Switching sources never resizes the workspace.

Stage Only hides the source rail, header card, demo panel, and window buttons.
Control–Command–S toggles it; Escape restores controls when annotation mode is
inactive. Restore controls to access the window buttons. Never imply that visible
workspace controls are excluded from window sharing.

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

Presentation tools remain available in the header card, menu bar, Settings, and
floating source widget. Command–comma opens the native Settings window. Keep its
sidebar and size stable across panes, and show each effect’s governing On/Off state
beside its preview; the General and Demos panes have none.

The header card shares the workspace panel treatment, 56 points tall with 16 points of
horizontal padding. It leads with the app on stage: its 24-point icon, its name in
headline text, a state capsule (On stage in the accent color, Paused or Needs
attention in orange, or a mini spinner while busy), and the window title below in
secondary caption text, or the guidance title and hint when nothing is on stage. A
flexible space separates it from the trailing controls, set in callout text like the
demo panel's action bar. First, five icon-only accessory-bar toggles, 2 points apart
and in the accent color while on: Auto Polish (Option–Command–P), Spotlight
(Option–Command–F), Annotations (Option–Command–A), Click Highlights
(Option–Command–C), and Keystrokes (Option–Command–K). Then, 12 points on, the labeled
Pause Stage/Resume Stage (Shift–Command–P) and Clear Stage (Command–period) buttons, 4
points apart, in the same bordered accessory-bar style as the demo panel's Edit Demo…
and Test Again. When the card is narrow, Pause and Clear drop their labels first. The
stage starts 12 points below the header card. The header card hides in Stage Only.

The floating source widget is an icon-only vertical rail, 56 points wide with
18-point corners, 28-point buttons in 30-point rows, 6-point spacing, and 10-point
vertical insets. It has eight slots. From the top it holds the demo button (only
once the app has a demo), Pause Stage/Resume Stage, a divider, then every effect in
order of importance: Auto Polish, Spotlight, Annotations, Click Highlights, and
Keystrokes, which carries a permission badge while Accessibility is missing. A
second divider precedes More, an ellipsis menu with only Clear Stage, Show
BetterMeets, and Settings…. The panel follows its content's height: 316 points with
all eight slots, shorter while the app has no demo. Preserve its translucent material and inset edge. It
follows the selected source, prefers the right gutter then the left, and falls
inside the source when neither fits. It stays separate from the shared workspace
and remains available in Stage Only.

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

The demo panel sits below the stage, once a window is chosen, in the same workspace
panel treatment as the rail: regular material, 16-point corners, a subtle inset edge,
and 16-point padding. It shares the workspace's semantic colors and SF text. It has
two regions. On the left, the library says which demo is open and is the only place to
create, switch, rename, and delete demos. On the right, the detail reads top to
bottom: a status band with the state, its reason, and the one primary action; a step
grid; and an action bar. The panel is 168 points tall in every state except composing,
which grows with a longer request up to 200 points, so playing, pausing, or finishing
a demo never moves the stage.

The library takes 20% of the content width, 160 to 240 points, followed by 12 points,
a full-height divider, and 12 points. Its header, “App Demos” in semibold subheadline
text (secondary, primary with Increase Contrast), sits above a plain native list with
24-point rows: three rows and a peek of the fourth, with no separators or alternating
backgrounds. Each row is a status glyph and the demo's title in callout text, cut at
the tail with the full title as its help tag. Selection uses the system highlight and
opens that demo without building or playing it; the open demo stays selected. The
glyphs are an accent play while presenting; a small spinner while building,
testing, or going back to the start; an orange pause circle while paused, off track,
or while a build is paused; a green seal when tested; and a secondary dashed circle
when not. While BetterMeets drives the app, the other rows dim to tertiary and can't
be selected (“Pause first to switch demos”). A library bar under the list holds
“+ New Demo” and “−” accessory buttons. While the presenter writes a new demo, a
selected “New demo” row with a pencil-on-square glyph and a small Cancel button ends
the list. No row shows a close button, so nothing that looks like closing deletes.
With no saved demos the library is hidden and the composer spans the full width; the
library eases in over 0.18 seconds when the first build saves a draft.

Return on the selected row renames the demo in place, as in Finder: the title becomes
a plain field, Return or leaving it saves, Escape cancels, an empty name reverts, and
titles keep at most 80 characters. Renaming keeps a tested demo tested, and drafts
take their title when the build finishes. Double-clicking a built row, clicking a
step, Edit Demo… in the action bar or the row's context menu, and Demo › Edit Demo…
all open Edit Demo. Delete, “−”, Delete Demo… in the row's context menu, and Demo ›
Delete Demo… show the same confirmation: “Delete “Title”?” with “Its steps and lines
are removed from this Mac. Other demos stay.”, Delete Demo, and Cancel. The open built
demo's context menu holds Edit Demo…, Rename, Test Again, Go to Start, and Delete
Demo…; another saved demo offers Open, Rename, and Delete Demo…; a paused build offers
Use N Steps, Edit Request, and Delete Demo…; and the New demo row offers Cancel New
Demo. Escape in the request field, “−” on the New demo row, or selecting a saved demo
also cancels a new demo. Every library action is unavailable while BetterMeets drives
the app.

The status band is 38 points: a 20-point glyph and a semibold title-3 headline on one
line, then a one-line callout subline. The headline names the state, or the demo's
full title when it is ready. Building and testing show a Build › Test › Ready
pipeline with the current stage in semibold, done stages secondary with a checkmark,
and upcoming stages tertiary. Headlines count steps the same way the grid shows them:
Step 4 of 9, Paused at step 4 of 9, Test paused at step 3 of 9. The glyph carries the
color, never the text: accent for playing, green only for Tested, orange for paused
or needing the presenter, secondary otherwise, or a small spinner while BetterMeets
works, which becomes a secondary hourglass while a step waits for a pause. The
subline holds facts (“Tested · 9 steps · About 2 min · Starts on the
Scheduled page”, which drops the duration and then the start when narrow and shows
the full start description as its help tag), “Next: …” while presenting, or a reason.
While a building or testing step waits for a pause, the subline adds “Waiting for a
pause to bring App forward…” after the progress (“Testing step 3 of 9 · …”),
shortening to “Waiting for a pause…”, with a help tag saying BetterMeets waits
until the presenter stops typing and moving the pointer, then puts their window and
pointer back. When a browser had to come forward for web steps because its
setting was off, a ready demo's subline shows a one-time tip in place of its facts,
below a notice or a moved step: a secondary lightbulb and “Dia had to come forward
for some steps. Turn on Allow JavaScript from Apple Events in its Developer menu to
keep it in the background.” (View › Developer in Chrome, Develop › Developer
Settings in Safari), or, when BetterMeets may not control the browser, where to
allow it in System Settings → Privacy & Security → Automation. A browser's tip
shows once, until the next build or test run.
Reasons and notices are primary, selectable text; when one is cut it ends in a More
link that opens a popover with the full text. API errors add Copy Details, which
shows Copied for 1.5 seconds.

Actions sit on the band's trailing edge. While presenting, a transport group of three
icon-only buttons comes first: Start Over, Previous Step, and Next Line while playing
or Next Step while paused, disabled rather than removed when they don't apply. Up to
two regular bordered secondaries follow, then the one primary, which always sits at
the trailing content edge. The primary is the only large control, with a filled
glyph and a 112-point minimum width. Forward actions (Play, Resume, Allow, Go to
Start, Try Again) are prominent; interrupts (Pause Build, Pause Test, Pause Demo, and
Stop) take the same slot and size, bordered. When the band is narrow, the secondaries
fold into a split-button primary, the last first, and Continue from Step N shortens to
From Step N; the transport and the primary never drop. Builds, tests, and demos all use Pause and
Resume, matching Pause Stage and Resume Stage. A paused build offers Use N Steps and
Edit Request beside Resume Build. A build or test run that paused because the Mac's
displays slept or the presenter switched to another user says so and that it goes on
by itself (“Paused while your Mac sleeps. The build goes on once it wakes.”, “Paused
while you’re switched to another user. The test goes on once you’re back.”), keeps
its usual actions, and raises no notice over the presenter's app; about two seconds
after they're back, signed in past the lock screen, it carries on. An approval offers Skip and Allow and circles the
control in question; when trusting the app can answer the question, Always Allow in
App follows Skip as the second secondary, so Allow stays the one primary, and it is
the first to fold into Allow's menu when narrow. A blocked request offers Edit Request and Build Alternative, and
the subline names the closest real alternative. A build that hit a limit offers Use N
Steps; its subline names the limit, and a build whose actions BetterMeets kept
turning down says so rather than that nothing changed (“Stopped because Claude
kept choosing actions BetterMeets won’t do.”), as one whose last actions changed
nothing or went the wrong way says they got nowhere (“Stopped because the last
few actions didn’t get the demo anywhere.”). Going back to the start offers Stop, Pause Test, or Pause Demo, depending on
what follows. Not at the start offers Go to Start; I'm There instead when no
automatic return exists or the page isn't exposed, and both when only switches
differ; each preceded by Play Anyway when the return leads to playing or to ready
rather than a test run. A paused test offers Go to Start
and Resume Test. Off track offers Skip Step while presenting and Try Again, or
Continue from Step N when the app is already on a later step's screen. Finished
offers Play Again, which goes back to the start, then plays from the top. Actions
that drive the app are disabled while the source isn't live, with a help tag that
says why.

The body is 58 points: a step grid of three 18-point rows, 2 points apart, that never
scrolls. Steps run down each column, and columns are 140 to 260 points wide, 12 points
apart, and leading aligned, so nine steps fit at the minimum window width and fifteen
at the default size. Each cell is a 16-point numbered marker and the title in callout
text. Idle markers are a faint circle with a secondary number, and titles stay primary
so the agenda never looks disabled. While building, the step being recorded shows a
mini spinner and “Recording…”, the outline's planned beats follow as dashed rings with
tertiary titles, and an approval shows an orange raised hand. The grid shows the steps
the demo will keep, so a click that showed nothing, or a detour that came back to
where it began with nothing shown, leaves it as the build goes on. A test marks passed
steps with a green circle and a white checkmark and the current step with a spinner
in an accent ring. Presenting marks done steps with an accent circle and a white
checkmark and the current step with an accent ring and a semibold title. A step that
went off track gets an orange ring with an exclamation mark. When steps don't fit,
the last cell reads “N more steps” and opens an “All N Steps” popover; a current or
failed step hidden there takes that cell, so the run's position stays in view. While
the demo is built and nothing runs, clicking a step opens Edit Demo scrolled to it,
with a faint 6-point rounded hover fill and a pencil, and the help tag previews the
step's line. While presenting with the teleprompter hidden, the body shows the
current line instead, in 15-point medium SF Rounded up to three lines; while Follow
my voice listens, words already said turn secondary and the next word takes the
accent color with an underline. A step without a line reads “No line for this step”
in secondary text. When the demo finishes, the body shows the closing line, or
“That's the whole demo.”, and a build that recorded nothing reads “Nothing recorded
yet.” The grid and the line cross-fade over 0.18 seconds.

The 24-point action bar holds this demo's tools on the leading side: Edit Demo… and
Test Again once the demo is built, always shown and disabled while they don't apply,
then a mini spinner and “Writing lines…” while Claude writes the narration. The
presenter's tools sit on the trailing side: a Teleprompter toggle (a captions bubble)
and a Pacing pull-down whose label shows the mode (Voice, Timed · 2×, or Step by
Step). Pacing holds Follow My Voice, Pause After Each Step, Speed, and Demo
Settings…, which opens Settings › Demos. When the bar is narrow, Teleprompter and
Pacing go icon-only first; Edit Demo… and Test Again keep their labels. Speed defaults
to 2× and offers 1×, 1.5×, 2×, and 3×; it affects only timed playback, shortening
pauses and silent steps, never the time a line takes to say. While Follow my voice is
on, the presenter sets the pace: the Pacing menu and the Demo menu hide Speed, and
Settings › Demos disables it with a help tag explaining why. Playback advances
automatically by default.

While composing, the band reads “Real-time demos” beside an accent play-rectangle for
the first demo (“Describe a flow. Claude builds it in App, tests it, and gets it
ready to present.”), or “New demo” beside a secondary pencil glyph once others exist.
A large request field follows: one to three lines of title-3 text on a translucent
text background with 14-point continuous corners, led by a multi-hue sparkles mark
and ending in a prominent large Build Demo button (a magic wand icon) inside the
field. Its placeholder asks “What should the demo show in App?”. While the field has
focus, its edge becomes Claude's multi-hue glow (accent, purple, pink, and orange). A
Try row of callout capsules follows: two fixed ideas, Quick tour and Main flow, then
three ideas Claude found in the window's own features, each a sparkles capsule
labeled with the feature's name in two to four words, and More Ideas, which asks
again. While Claude looks, three faint “Finding ideas…” placeholders hold their
place. Choosing an idea fills the field with its request (shown as the capsule's help
tag) and focuses it without building. The row never scrolls: Claude's ideas drop from
the end when it is narrow, and More Ideas always stays. Without Claude access only
the two fixed ideas show. Sparkles mark only the request field and Claude's ideas.

The Try row can become a setup row, which hides the band's subline, holds the field
to one line, and turns Build Demo bordered so only one control is prominent. The
first time a window is chosen, until the presenter answers, it is a consent row:
“Claude operates the window you choose, in the background while you watch. Building
sends your request, screenshots and control labels to Anthropic.” Learn More opens a
Claude Access popover that adds that playing or testing later sends a screenshot only
to find a control that moved, that clicking or typing in the app pauses it, and what
Claude never does. Not Now and Allow follow; Allow turns on Claude access for every
app. Build shows the same row with Allow and Build while access is off. When Build
needs a key, it is an API key row with a secure field, Not Now, and Save and Build; a
Keychain failure shows under its message as primary text with an orange warning
glyph.

VoiceOver reads the panel as “Real-time demos for App”, the list as “App Demos”, and
the detail by the open demo's title; the band's headline and subline read as one
element, and each step reads as “Step N: title” with its state as the value. Phase
changes are announced (“Building the demo.”, “Tested. Ready to play.”, “Paused at
step 4.”, “Demo finished.”), step changes are not. Reduce Motion makes the band's
cross-fades, the grid and line swap, the library appearing, rows coming and going,
hover fills, and the Copied feedback instant; spinners stay. Increase Contrast
strengthens idle markers, hover fills, planned beats, and the library header. Orange
marks glyphs only, never text, and red is only for Delete Demo.

Edit Demo opens a native sheet, ideally 680 × 720 points and at least 600 × 560. Its
header holds the editable title in semibold title-2 text, “App · N steps”, a green
Tested badge, and an editable Starts on field for the short start label, whose
placeholder is the label BetterMeets would use and whose help tag shows the screen
BetterMeets checks for. A rewrite bar below holds a Tone
picker (Conversational, Concise, Technical), a Language picker (Same as My Request,
then each language by its own name), an audience field, and Rewrite Lines,
which keeps lines edited in the sheet and is disabled while removed steps are
unsaved; while Claude writes, the button becomes a small spinner and the lines fade
to 45% opacity, and a failed rewrite shows its reason below the bar in orange
caption text. The list runs from the Opening line through every step to the Closing
line. Each step shows its number, an editable title, a remove button, a read-only
action summary with its action icon, and a multi-line field for its line. There is
no timing control: each step holds for as long as its line takes to say. Removing an
action confirms that it and every later step will go. The footer holds Copy Script,
a footnote (“Edited words keep the demo tested.” or “Removing an action means
testing the demo again.”), Cancel, and Save. Edit Demo is unavailable while
BetterMeets drives the app.

Settings › Demos uses the Settings window's form rows: the API key (Return or Save
stores it, then Saved in Keychain with Remove); the Claude access checkbox with a
plain-language explanation of what building sends, that playing or testing sends a
screenshot only when a control moved and has to be found again, that it never pays,
sends, deletes, or enters passwords, asks before anything unusual, and that builds
stop at $2; Always allowed, listing each app chosen with Always Allow by its
16-point icon and name (its bundle ID once the app is gone) with a Remove link, or
“None yet. Choose Always Allow when a build asks.”, and a caption saying what builds
there still ask about and that removing an app keeps steps already allowed; Script language, a pop-up of Same as My Request and each language by
its own name, with a caption that it sets the demo title, step titles and lines and
that Rewrite Lines changes an existing demo;
Teleprompter, with Show under the camera when a demo plays and a caption to share
the BetterMeets window, not the whole screen, to keep it private; Pacing, with
Follow my voice and a note that each step moves on when its line is finished and
speech stays on this Mac, Pause after each step, and Speed, disabled while following
the voice; and Accessibility status.

The teleprompter is a solid black island that grows out of the camera notch on the
display with the camera (the built-in display when present, else the primary
display), so reading it looks like talking to the audience. It is a borderless,
nonactivating panel just above the menu bar and its status items and below other
apps' menus, on every Space and over full-screen apps, with no shadow and a forced
dark appearance. It never activates BetterMeets, can't be dragged or resized, and
docks itself again whenever it shows, the text size changes, or displays change. With
a notch it is flush with the top edge and centered on the notch, with concave
shoulders where it meets the menu bar and continuous bottom corners; without one it
hangs from the bottom of the menu bar. When there is no line to read (before the demo
is built, or while building, testing, or going back to get ready), it is a compact
island only as tall as the menu bar and 224 points wider than the notch (300 × 28
points without one), with a short status beside the camera, after a glyph when the
state calls for one, and a 20-point options button on the other side. With a line it
expands to 500 × 188 points at the default text size (460–700 points wide as the text
grows), with 16-point shoulders and 20-point corners, and it stays expanded when the
demo finishes, to offer Play Again.

Beside the camera, in 11-point semibold SF Rounded, the left side shows where the
demo is: the step position (such as 2/6) in monospaced digits and the step title, or
Opening, Wrap up, or Done, after a pause, spinner, orange warning, or green check
glyph when the state calls for one. The right side shows Next and the next step's
title, Wrap up before the closing line, or Last step, and nothing on the closing
line. Each side stops 8 points short of the camera, and a title that doesn't fit is
cut, with the full text in its help tag. Below, only the current line shows, in
semibold SF Rounded (bold with Bold Text) at 26 points by default (16–48),
leading-aligned in rows that scroll forward only, so the row being read stays second
from the top with the row before it in view (at the very largest sizes, at the top);
a line shown again, as after Start Over, reads from its first row. Rows that go on
below the bottom edge fade out, and the top edge fades only over a row already read,
never over the row being read. The next step's words appear only when its step
begins. Words already said are white at 34 percent and, while Follow my voice
listens, the next word is underlined in the accent color; the highlight eases over
0.15 seconds. With voice off the line is uniformly white and scrolls with the timed
hold, keeping its place when the hold ends or the demo pauses, and once a line is said
all of it dims as the demo moves on. Paused, stopped,
not at the start, or going back, the line dims to 60 percent. A step without a line
reads “No line for this step” in italics, and a demo that finishes without a closing
line reads “That’s the whole demo.” A new line slides in from below, or from above
when the demo goes back.

The footer holds a level meter whose bars follow the voice and whose lit bars, in the
accent color, show how much of the line is said or how much of a timed hold has
passed; a status of up to two lines (the last three words heard, Listening, a
countdown, Moving on…, the microphone getting ready, or why the demo paused, stopped,
or can't play, in orange with a warning glyph when something is wrong); four
transport buttons in fixed places (Start Over, Previous Step, the state's one primary
action, and Next Line, Next Step, or Skip Step); then Follow my voice and
Teleprompter options. All six are 28-point circles: a forward primary is filled with
the accent color, Pause Demo stays quiet, and buttons are disabled rather than
hidden, so none ever moves. The microphone is crossed out while Follow my voice is
off, takes the accent color while it listens, shows a spinner while it gets ready,
and turns orange when it's unavailable. Titles, help, and enabled states match the
demo panel, and VoiceOver names the buttons as the panel does. VoiceOver reads the
island as Teleprompter: the place (such as “Step 2 of 6, Pick the schedule”, plus
paused, stopped, or going back), Next, Current line with the line as its value, the
status with how much of the line is said (both kept current through a timed hold), then
the controls. The options menu and the
island's context menu hold Larger Text, Smaller Text, any other action the panel
offers in that state (such as Play Anyway or Try Again), and Hide Teleprompter.
Showing grows the island out of the notch over 0.4 seconds before its content fades
in; hiding fades the content and folds the island back in, and switching between
compact and expanded morphs it the same way, as does a new text size. From 40 points up
the island is already as large as it gets, so only the content fades out and back in
at the new size. Without a notch it also fades as it
grows and folds. With Reduce Motion it fades instead, rows snap instead of scrolling,
and the meter's bars stay flat. Increase Contrast raises the island's faint text and
fills and adds a faint edge on the sides and bottom; an off-track stop adds an orange
edge. When a demo clicks or scrolls under the island, it steps aside for that input
and fades back.

When a build or test run the presenter started finishes, or needs them, while
BetterMeets is in the background, BetterMeets stays where it is and a notice grows out
of the camera notch on the display under the pointer, where the presenter is already
looking. It is the same solid black, forced-dark island as the teleprompter, on the
same nonactivating panel, with the expanded teleprompter's 16-point shoulders and
20-point corners, as wide as the notch plus 300 points (440–520 points; 440 without a
notch). Without a notch it hangs from the bottom of the menu bar. When the
teleprompter is up on that display, the notice is instead a black card with 20-point
continuous corners, 8 points below it and exactly as wide as its body at any text size
(inside the expanded island's 16-point shoulders or the status pill's 8-point ones),
so its text lines up with the teleprompter's; it follows the teleprompter as it
resizes. Beside the camera, in 12-point semibold SF Rounded and never behind it, a
badge says what happened: a green seal with Demo ready, or an orange bubble with Build
paused, Test waiting, or Test stopped. An attention card always hangs under the status
pill, so it drops the badge and leads with its title, 14 points from the top, instead
of repeating the pill. Below, the app's 32-point icon leads a 15-point semibold title
and a 12-point detail of up to two lines in white at 60 percent: for a ready demo, its
title and “Tested · 4 steps · Dia” (or Not tested); otherwise what the build or test
run needs. At the bottom right, Open BetterMeets is an accent-filled 28-point capsule
beside a 28-point Dismiss circle in the teleprompter's button style. Content sits 12
points inside the body, as in the teleprompter, with 14 points below the buttons. It
grows out of the notch over 0.4 seconds before its content fades in and folds back
when it leaves; without a notch, and with Reduce Motion, it fades, and a card slides 8
points out from under the teleprompter, its window reaching up to the teleprompter so
the slide is never clipped. A newer notice replaces it in place, cross-fading the
content and morphing to the new height. There is no timeout: it stays until the
presenter clicks Open BetterMeets (the only thing that brings BetterMeets forward) or
Dismiss, switches to BetterMeets, or the demo moves on to something it doesn't
describe, and a notice put away doesn't return while the demo stays in that state.
VoiceOver hears it as it appears (“Demo ready: El Gran Premio de Cannes, tested, 4
steps”), since it never takes focus, and the demo panel stays quiet about that change
meanwhile; it reads it as Demo notice with Open BetterMeets and Dismiss buttons, and
Dismiss's help tag shows though BetterMeets is in the background. Open BetterMeets on
Build paused, Test waiting, or Test stopped also leaves Stage Only, so the panel to
act in is there. Increase Contrast raises the detail to 80 percent and adds the
teleprompter's faint edge.

While BetterMeets builds, tests, or goes back to the start, the stage's edge carries
Claude's multi-hue glow (accent, purple, pink, and orange): a 2-point angular-gradient
line over a wider blurred halo at 55% opacity, turning once every four seconds. It
fades in and out over 0.3 seconds, holds still with Reduce Motion, never takes input,
and is hidden from VoiceOver. It belongs to the workspace, so Stage Only never shows
it.

While BetterMeets builds, tests, or goes back to the start, the window it drives
carries a badge like the stage's glow: an accent capsule 22 points tall, inset 8 by
6 points from the window's top-left corner over its window buttons, with a white
cursor-with-motion-lines glyph, a subtle shadow, and a 1.5-point ring in Claude's
hues that turns once every four seconds. Hovering it, even with BetterMeets in the
background, expands it over 0.12 seconds to show “BetterMeets is building”, “is
testing”, or “is going back to the start” in 11-point semibold SF Rounded, with a
help tag saying the presenter can keep working in other windows; clicking it shows
BetterMeets without the badge taking focus. The stage's arrow and click ripples are
drawn inside the window too, while the presenter's own pointer stays theirs. Both
sit just above the window and under the presenter's other windows, follow it as it
moves, and hide while it is minimized, hidden, or on another Space. Escape, Up and
Down in a list, Page Up and Page Down, and scrolling in the app's own views, and a
field that takes its text only as a replaced selection, stay in the background, so
they never wait for a pause; while building, a step the app showed no change for
within about a second is tried again before Claude hears it did nothing, as a
page's own click and then a real click, or once with the real key or wheel, and
the panel's progress says so (“Trying a real click on Details”). It never is for
a switch, a Save or Add, a step the presenter approved, a scroll whose bar moved,
or a step a window opened for. A test run does the same, once, for a click that
showed nothing within about a second (“Step 3 of 9: Trying another click on
Details”), never for a switch, a Save, Add, Search, or Next, or a step the
presenter approved; once the test passes, the step keeps the click that worked. When a step
needs the app in front, the badge shows an hourglass and “Waiting for a pause”, its
ring holds still, and BetterMeets waits until the presenter has left the keyboard
and pointer alone for 1.5 seconds, brings the window forward for well under a
second, then puts their app, window, and pointer back; badge and arrow step away
meanwhile. Input from the presenter before the step commits puts things back, and
the step tries again at the next pause; after eight tries the run pauses with
“This step needs Dia in front for a moment. Resume when you can leave the keyboard
and pointer alone for a second.” A pause partway through a password never counts.
The presenter's other windows of the same app stay theirs: typing there doesn't
pause the run, and the badge and arrow stay under them. Playing never shows the badge: the app is in
front and the presenter presents from it. Reduce Motion stops the ring and the
expansion animation; Increase Contrast adds a white edge. VoiceOver reads the badge
as a button named by its label.

**The Separate Pauses Rule.** Pause Demo stops the sequence while preserving the
live app and current visual cue. Pause Stage hides the source image. Name both
actions explicitly wherever they appear together, including the floating widget,
whose demo button uses the panel's names: Pause Build or Resume Build, Pause Test or
Resume Test, Pause Demo or Resume Demo, Stop while going back to the start, Try
Again, Play Again, Go to Start when the app isn't at the start, and otherwise Play
Demo. The Demo menu's first item (Control–Command–Return) uses the same names, with
Play Anyway when the app isn't at the start.

Demo effects use the existing presentation vocabulary: spotlight, magnification,
drawn emphasis, click highlights, and displayed keystrokes. Because demos run the
app in the background, a virtual system arrow glides to each target on the stage
and demo clicks ripple on the stage, and, while building and testing, inside the
driven window too. Drawn emphasis uses the system accent;
Reduce Motion shows it, and moves the virtual cursor, immediately. Spotlight
edges strengthen with Increase Contrast. When a presentation or test run ends, its
last effect and the virtual cursor stay for 2 seconds, then fade out over 0.6
seconds on the stage and the source window; with Reduce Motion they go at once.
Effects do not intercept input or add screen-reader content.

## Setup and recovery

The idle workspace teaches two steps: choose a source window, then share BetterMeets.
Stage Only remains available through the View menu and keyboard shortcut. Use “On stage” for local capture;
BetterMeets does not know whether a meeting is transmitting the window.

Presenter controls show specific setup and recovery actions. Audience placeholders
stay brief and contain no raw error diagnostics or operator instructions. Pausing
the stage hides the source image; it does not freeze its last frame. The in-app presentation
guide remains available from Help.
