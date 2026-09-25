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
    width: "176pt"
  source-preview:
    width: "148pt"
    height: "84pt"
  action-button:
    height: "30pt"
  status:
    height: "52pt"
---

# BetterMeets design system

One native window contains the presentation workspace. Tools sit above a
vertically scrolling window list on the left. The source preview fills the
remaining area at its own aspect ratio. A status strip below the stage contains
current state, source title, Open App, and Stop. The bottom area can support
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
letterboxing and captured imagery. System accent marks active tools and the
selected source; orange indicates paused, pending, or permission states.

Panels use 16-point rounded corners and a subtle inset edge. Reduce Transparency
replaces materials with a solid system control background. Increase Contrast
strengthens edges. Semantic font styles and inherited legibility weight support
Bold Text. Source details also appear in previews and accessibility labels.

## Tools and sources

Six labeled rows: Auto Polish, Spotlight, Annotate, Click Highlights, Keystrokes,
and Settings. Active rows have an accent icon, fill, and small state marker.
Right-click opens the tool's settings; the gear anchors a native settings popover.

The floating source widget uses the same actions as an icon-only vertical rail:
56 × 230 points, 18-point corners, 28-point buttons, and 6-point spacing. Preserve
its translucent material and inset edge. It follows the selected source, prefers
the right gutter then the left, and falls inside the source when neither fits.
It stays separate from the shared workspace and remains available in Stage Only.

Each source shows app identity, an upright thumbnail, a shortcut keycap, and its
window title. Selection outlines do not change layout. Paused and pending states
have explicit symbols. Unavailable pinned windows retain their reserved slots.
Empty unassigned slots do not consume sidebar space.

Up/Down moves source focus, Return selects, and Space previews. Hover previews
appear after a short dwell to avoid distracting accidental passes. Selected and
keyboard-focused windows scroll into view. All controls have accessibility
labels, visible hover and keyboard focus, and press feedback.

## Motion

Use a critically damped 0.3-second spring for source scrolling. Selection and
hover use short color/opacity transitions. Stage Only cross-fades the layout
without sliding the entire stage. Reduce Motion removes spatial effects while
retaining state feedback. Input stays available during every transition.
