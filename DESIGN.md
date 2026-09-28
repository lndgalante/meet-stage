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
    width: "224pt"
  source-preview:
    rounded: "{rounded.source}"
  action-button:
    height: "30pt"
  status:
    height: "60pt"
---

# BetterMeets design system

One native window contains the presentation workspace. Tools sit above a
vertically scrolling window list on the left. The source preview fills the
remaining area at its own aspect ratio. A status strip below the stage contains
current state, source title, Open Source App, Pause/Resume, and Clear Stage. The bottom area can support
future presentation features without changing the source layout.

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

Five labeled rows: Auto Polish, Spotlight, Annotations, Click Highlights, and
Keystrokes. Active rows have an accent icon, fill, and small state marker. Tools
stay open at every window size. Enabled
tools waiting for a source share one readiness hint.

One gear beside the Tools heading and Command–comma open the same
native Settings window. Keep
its sidebar and size stable across panes, and show each effect’s governing
On/Off state beside its preview.

The floating source widget uses the same actions as an icon-only vertical rail:
56 × 369 points, 18-point corners, 28-point buttons, and 6-point spacing. Preserve
its translucent material and inset edge. It follows the selected source, prefers
the right gutter then the left, and falls inside the source when neither fits.
It stays separate from the shared workspace and remains available in Stage Only.
Its status, Pause/Resume, Clear Stage, and Show Controls actions precede effects.

Each source shows app identity, an upright thumbnail, and a quiet shortcut keycap
beside the identity. Show the window title only when it differs from the app name.
Full distinguishing titles appear in enlarged previews. Selection and keyboard focus
outline only the outer tile, never the thumbnail, without changing layout.
Paused tiles coordinate an orange edge, tint, and pause symbol;
live tiles use a dot. Unavailable pinned windows retain their slots and offer Unpin.
Empty unassigned slots do not consume sidebar space.

Resize the sidebar from 200 to 320 points. Automatic density uses compact rows
below a 680-point sidebar height, with no separate layout menu.
Preserve system scroll indicators. Selecting the current
live source keeps it live; pausing is an explicit action.

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

## Setup and recovery

Teach source selection → Stage Only → share BetterMeets. Explain that restoring
controls makes them visible in that window share. Use “On stage” for local capture;
BetterMeets does not know whether a meeting is transmitting the window.

Presenter controls show specific setup and recovery actions. Audience placeholders
stay brief and contain no raw error diagnostics or operator instructions. Pausing
hides the source image; it does not freeze its last frame. The in-app presentation
guide remains available from Help and the idle status strip.
