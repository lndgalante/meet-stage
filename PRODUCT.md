# BetterMeets

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS. This repository uses SwiftUI and AppKit; it is not a web or mobile
interface. Apply macos-design-guidelines when a design tool lacks a macOS category.

## Users

People presenting app windows in Google Meet and other meeting apps.

## Product Purpose

Keep one shared Demo Stage while switching the app window shown within it.
The presenter controls the presentation without exposing those controls to viewers.

## Operating Context

A compact floating widget selects source windows. A separate vertical action menu
follows the selected source. The user has requested a complete widget rebuild
while retaining its features. Typical source count remains an open question;
the current widget presents four slots and scrolls to additional windows.

## Capabilities and Constraints

- Live window previews, app identification, larger hover previews, and guidance.
- Select, pause, resume, and switch the window shown on Stage.
- Option–1 through Option–9 by default; configurable modifiers and disabling.
- Pin/unpin source slots; retain unavailable pinned slots and explain conflicts.
- Horizontal browsing, automatic scrolling to the selected source, keyboard access.
- Drag, persist position, hide, minimize, and reopen the controller.
- Permission, loading, empty, pending, paused, live, and failure states.
- Settings and presentation actions stay outside the shared Stage content.
- Actual widget window bounds must match the visible surface, with no transparent
  shadow padding or detached title-bar line.

## Brand Commitments

BetterMeets name and existing app icon. Native macOS behavior, compact controls,
system typography and accent color. The previously requested action menu and
settings layout remain separate from this widget redesign.

## Evidence on Hand

User-provided screenshots and requirements in this conversation; README.md;
Sources/MeetStage and the existing test suites. No marketing claims are needed.

## Product Principles

- Make the currently shared window unmistakable.
- Keep switching fast by pointer and keyboard.
- Preserve feature behavior through the visual rebuild.
- Fit the visible utility to its real window bounds.

## Accessibility & Inclusion

Support keyboard navigation, VoiceOver, Reduce Motion, Reduce Transparency,
Increase Contrast, and Bold Text using native macOS affordances.
