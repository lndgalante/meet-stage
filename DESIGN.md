---
name: BetterMeets
description: Compact native macOS controls for recognizing, switching, and presenting app windows.
typography:
  label:
    fontFamily: "SF system"
    fontSize: "11pt"
    fontWeight: 400
  label-selected:
    fontFamily: "SF system"
    fontSize: "11pt"
    fontWeight: 500
  shortcut:
    fontFamily: "SF system monospaced"
    fontSize: "11pt"
    fontWeight: 600
  guidance:
    fontFamily: "SF system"
    fontSize: "10pt"
rounded:
  panel: "16pt"
  source: "8pt"
  keycap: "5pt"
  action: "9.5pt"
spacing:
  rail: "8pt"
  detail: "4pt"
  form: "12pt"
components:
  source-preview:
    rounded: "{rounded.source}"
    width: "80pt"
    height: "66pt"
  shortcut-keycap:
    typography: "{typography.shortcut}"
    rounded: "{rounded.keycap}"
    padding: "3pt 5pt"
  controller-panel:
    rounded: "{rounded.panel}"
    width: "360pt"
    height: "128pt"
  action-button:
    rounded: "{rounded.action}"
    width: "28pt"
    height: "28pt"
---

# Design System: BetterMeets

## Overview

**Creative North Star: "The Native Presentation Utility"**

BetterMeets uses compact macOS utility surfaces, SF system typography, SF Symbols, native controls, and the user's system accent. Real window previews and app icons provide recognition; labels and state cues explain what the audience is seeing. Density serves quick switching while the presenter watches another app.

The controller, settings, and vertical presentation palette retain distinct jobs within this native system. Settings preserve restrained surfaces and two primary controls per tab, with supporting guidance or recovery actions where needed. Presentation controls stay in their own vertical palette, separate from the shared Stage.

**Key Characteristics:**

- Adaptive neutral materials with semantic system text and accent.
- App identity above real previews, followed by sharing status and trailing guidance.
- Compact native controls with pointer, keyboard, and VoiceOver access.
- Brief state feedback that respects accessibility preferences.

This is a SwiftUI/AppKit system. Frontmatter dimensions ending in `pt` denote macOS logical points, not CSS physical units. Dynamic colors, semantic fonts, materials, and native window behavior are represented in `.impeccable/design.json` under `extensions.native`; they have no fixed CSS palette. Sidecar HTML/CSS is explicitly a preview translation, not production source.

## Colors

Adaptive neutral materials keep the utility quiet; system accent and warning colors communicate actual state.

### Primary

- **System Accent** (`ControlPalette.accent = Color.accentColor`): selected source borders, selected shortcut keycaps, play symbols, keyboard focus, and active presentation controls. Honor the user's accent choice.
- **State Warning** (`ControlPalette.warning = Color.orange`): paused or pending sources, unavailable pinned slots, permission warnings, and warning guidance. Shortcut conflicts use `Color.red` and an exclamation symbol.

### Neutral

- **Native Material** (`.regularMaterial`): the controller and presentation palette. Reduce Transparency substitutes `Color(nsColor: .windowBackgroundColor)`.
- **System Text** (`.primary` / `.secondary`): identities, labels, and supporting guidance. The footer uses primary state text and secondary next-action text.
- **Preview Contrast** (`Color.black` / `Color.white` with local opacities): thumbnail backdrops, shortcut text, inset preview edges, and focus details.
- **Controller Tint**: the material receives a dark neutral overlay in dark appearance and a light neutral overlay in light appearance. The source defines these as black at 0.55 and white at 0.20, respectively; do not replace them with a sampled screenshot color.

**The State Has Two Cues Rule.** Pair color with text, an icon, or an explicit focus shape: a play symbol for sharing, a pause symbol for paused, progress for switching, and a dashed inset with a Return glyph for keyboard focus.

## Typography

**Body and label font:** SF through SwiftUI's system font APIs. **Shortcut font:** the system font with `.monospaced()`; no bundled display family.

The hierarchy is deliberately shallow. App labels use `label`, selected labels and footer status use `label-selected`, shortcut keycaps use `shortcut`, and next-action guidance uses `guidance`. The source's small play/pause symbol is supporting state metadata, never the sole explanation of sharing. Hover previews use semantic `.callout.weight(.semibold)` for the window title and `.caption` for the app name and shortcut. Settings form labels retain `.callout` and native control typography.

System line metrics remain native; there is no authored line-height or tracking scale. Bold Text is honored through `legibilityWeight`. Labels truncate at one line where the compact controller requires it, with source details exposed in the hover preview and VoiceOver labels.

**The Recognition Before Decoration Rule.** Keep app identity, shortcuts, and sharing state more prominent than decorative effects; preserve native text metrics and meaningful labels.

## Layout

The controller uses four equal source columns inside the `controller-panel` bounds. Its source region is 104 points high; the status region is 24 points high. The rail uses `spacing.rail` for outer, vertical, and between-column spacing. Each source places an 18-point identity row above a `spacing.detail` gap and a `source-preview`. Shortcut keycaps sit at the bottom right of previews. Additional sources browse horizontally, with edge fades and directional chevrons only where content continues. Focus and selected-source changes scroll the relevant source into view.

The native borderless controller window exactly matches the visible rounded panel. It can become key and main, preserves close/minimize commands, restores position, and constrains restored coordinates to a visible screen. Its footer is the native drag surface; dragging must preserve one-to-one pointer movement without stealing source interactions.

Settings retain a native segmented tab selector above the form. Their 568-point-wide surface sizes to content until a 480-point content-height cap, then scrolls vertically. A preview well precedes the two primary form controls; aligned callout labels and native segmented controls, checkboxes, sliders, and fields retain the established settings arrangement.

The presentation palette remains a separate 56-point-wide vertical surface with compact actions above and below the larger circular voice control. These surface-specific dimensions are not general breakpoints; the app has no web or mobile layout system.

**The Visible Bounds Rule.** The controller's native window bounds must equal its visible panel bounds; use no transparent layout padding solely to contain an outer shadow and no titled frame hidden behind a smaller widget.

## Elevation & Depth

The controller combines regular material, a neutral tint, and an inset one-point edge. Increase Contrast strengthens the edge from primary opacity 0.18 to 0.50. Its outer shadow belongs to the window server through `NSWindow.hasShadow`; the SwiftUI controller draws no outer shadow.

The incumbent presentation palette keeps the gradient tint and graduated edge in `PresenterPanelBackground`, currently called with `drawsShadow: false`. The larger voice control retains its own contact/ambient shadows, top-lit sheen, and a static listening halo. These native depth cues remain valid for that control. Settings use lightly tinted wells and inset borders; native popovers provide hover-preview elevation.

**The Window Owns the Controller Shadow Rule.** Keep the controller's outer shadow outside content layout; do not generalize this rule into a ban on the presentation palette's existing control shadows or native gradients.

## Shapes

Continuous rounded rectangles define utility panels, preview clips, and shortcut keycaps using their named frontmatter radii. The controller's background, outline, and clip share one panel silhouette. Preview state outlines are inset, so selection does not enlarge the preview or collide with adjacent labels.

The neutral preview edge is one point; selected, pending, and keyboard-focused previews use two points. Keyboard focus adds a separate white dashed inset and a Return glyph. Empty slots use a dashed outline and a passive window symbol. Native segmented controls, capsules in hover-preview shortcuts, and the circular voice action retain their own native forms.

## Components

### Source buttons

Compact, recognizable window choices. Each plain button contains a real captured thumbnail, app icon/name, optional shortcut keycap, and state cue. Preview images fill and clip; the larger hover preview fits the image. Live sources show the accent border, accent keycap, and play symbol. Play and pause use the same 12-point-wide slot and 9-point semibold symbol size. Paused sources use warning borders/keycaps and a pause symbol; pending sources use warning borders/keycaps and progress. A conflicting shortcut remains red with a warning symbol even when its source is selected.

Hover adds a restrained white preview overlay; after 450 ms it opens a native popover with the window title, app identity, larger preview, and shortcut information. Keyboard focus is distinct from selection. Arrow keys browse and Return selects; a selected source click pauses, and a paused source click resumes. Context menus pin or unpin source slots.

The shared compact button style briefly scales to 0.96 and dims on press. Hover feedback uses 0.12-second ease-out, source state transitions 0.15-second ease-out, and compact press feedback 0.10-second ease-out. Reduce Motion removes the animations and press scale.

### Empty and unavailable slots

Passive placeholders preserve the source grid. An empty slot has a neutral dashed edge and the label Empty. An unavailable pin uses a warning edge, pin-slash symbol, and Unavailable label, retaining the pinned shortcut context. Neither placeholder implies an unsupported add action.

### Status footer

One status line below the source rail, without a divider or separate band. The state symbol and medium-weight title align left; secondary next-action guidance aligns right. Long text truncates with priority given to the title; the combined accessibility label and help always describe the full guidance. The same region supplies native window dragging and controller context commands.

### Presentation actions

Native symbol buttons remain in the separate vertical palette. Active actions use accent symbols and low-opacity accent fills; hover and keyboard focus remain visible. The circular voice action is larger and uses a static listening halo, with permission warnings shown separately. Settings can open from the palette or controller without adding controls to shared Stage content.

### Settings navigation and inputs

Preserve the native segmented tab selector, restrained container, preview wells, and two primary controls per tab. Fields remain native `SecureField`/`TextField` controls, with native focus, validation feedback, and disabled behavior. Supporting help or permission recovery belongs near the relevant control. Avoid replacing established controls with web-style custom input or navigation chrome.

## Do's and Don'ts

### Do:

- **Do** use native semantic colors and materials, including Reduce Transparency and Increase Contrast variants.
- **Do** preserve the separate controller, settings, vertical presentation palette, and shared Stage.
- **Do** keep source identity and sharing state readable at native utility scale, with full context in help and accessibility labels.
- **Do** maintain distinct live, paused, pending, unavailable, shortcut-conflict, and keyboard-focus cues.
- **Do** preserve native keyboard access, source context menus, position restoration, and footer dragging when changing the controller.

### Don't:

- **Don't** add transparent shadow padding or hide a titled frame behind the controller surface.
- **Don't** hard-code a sampled accent or material color as the native palette.
- **Don't** make color the only indication of source state or keyboard focus.
- **Don't** turn empty source slots into unsupported add buttons.
- **Don't** apply controller-specific shadow rules to eliminate the existing voice-control depth or native material gradients.
