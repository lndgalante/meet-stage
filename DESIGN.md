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
    height: "60pt"
---

# BetterMeets design system

One native window contains the presentation workspace. A compact, vertically scrolling app-icon rail sits on the left. The source preview fills the
remaining area at its own aspect ratio. An edge-to-edge status strip below both the rail and stage contains
current state, source title, Pause/Resume, and Clear Stage. The bottom area can support
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

Presentation tools remain available in the menu bar, Settings, and floating source
widget. Command–comma opens the native Settings window. Keep its sidebar and size
stable across panes, and show each effect’s governing On/Off state beside its preview.

The floating source widget uses the same actions as an icon-only vertical rail:
56 × 369 points, 18-point corners, 28-point buttons, and 6-point spacing. Preserve
its translucent material and inset edge. It follows the selected source, prefers
the right gutter then the left, and falls inside the source when neither fits.
It stays separate from the shared workspace and remains available in Stage Only.
Its status, Pause/Resume, Clear Stage, and Show Controls actions precede effects.

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

## Setup and recovery

The idle workspace teaches two steps: choose a source window, then share BetterMeets.
Stage Only remains available through the View menu and keyboard shortcut. Use “On stage” for local capture;
BetterMeets does not know whether a meeting is transmitting the window.

Presenter controls show specific setup and recovery actions. Audience placeholders
stay brief and contain no raw error diagnostics or operator instructions. Pausing
hides the source image; it does not freeze its last frame. The in-app presentation
guide remains available from Help.
