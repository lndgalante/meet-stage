# Controller widget rebuild

Mode: Operate. Scope: ControlView, source tiles, widget sizing and window shell.
Keep the existing native macOS visual system and all source-selection features.

## Task and evidence

The presenter switches among app windows without changing the meeting's shared
Stage. Screenshots show three sources and an empty fourth slot. The old window
has 30 points of transparent shadow padding per side and a hidden titled frame.
Both must be removed. The default thumbnail strip currently hides app names.

## Structural exploration

Seven viable structures considered: named filmstrip with footer status; status
header over filmstrip; active-window emphasis with adjacent source carousel;
compact icon rail with revealed preview; two-row paged source grid; dual-caption
carousel separating app identity from shortcut/status; source carousel beside
a narrow status column. The surface seed 324e2ed7 assigned the sixth structure.

The composed alternatives preserve that separation while varying status location
and relative preview emphasis. All keep native materials, system text and accent,
clear labels, scrollable sources and a window that exactly bounds its surface.

The staged-command challenger would add a confirmation step to switching; the
x-ray challenger exposes implementation detail; the lever challenger implies a
continuous action where this app selects discrete windows. They do not improve
this task or the presenter's recognition of it. Other-world palettes are outside
the established native identity.

## Approved visual checkpoint

The comps are saved as .impeccable/mocks/widget-a-balanced.png,
.impeccable/mocks/widget-b-status-first.png, and
.impeccable/mocks/widget-c-compact.png. The user selected C after trying A, requesting a smaller controller. Implement
Compact with app identities above previews and status on the left and guidance on the right below.

Comps use illustrative thumbnails and approximate icons. Production must use
real source thumbnails and app icons, semantic system text, and true state.
The empty slot must not imply an unsupported add action. The final utility will
be sized in macOS points rather than tracing the enlarged comp canvas.

## Implementation constraints

- Own the borderless controller with a native NSWindow subclass; preserve the
  shared Stage scene, menus and Settings scene. SwiftUI's plain window was tested
  and cannot become key on this OS, so it cannot preserve keyboard access.
- Remove transparent shadow padding; let the window server own the outer shadow.
- Preserve live/pending/paused state, unavailable pins, shortcut conflicts,
  hover previews, keyboard focus, source context menus, automatic scrolling,
  all permission/recovery actions, dragging and position restoration.
- Keep settings and Stage actions separate from this surface.
- Verify actual window bounds and native keyboard/minimize/close behavior.
- Keep verification bounded to one batched inspection and at most one confirmation.

## Fidelity inventory

- One rounded native material panel, with a window-server shadow outside its bounds.
- Four equal thumbnail columns, shortcuts at bottom right, real app icon and name above.
- Accent inset selection border and play symbol in the identity row; paused and pending
  states use distinct symbols and text.
- Current state aligned left and next-action guidance aligned right; no divider.
- Passive empty-window placeholder, not an unsupported add button.
- Native SF text and materials replace only the comp's illustrative content;
  production previews are real captured images. At native utility scale, long app
  names truncate with complete titles in hover previews and VoiceOver.
- 360 × 128 points, with 8-point source insets and gaps. The large comp is a
  composition reference, not a pixel-size specification.
