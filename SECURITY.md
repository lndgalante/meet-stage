# BetterMeets security and distribution model

BetterMeets is a directly distributed macOS utility. It does not enable App
Sandbox because it combines ScreenCaptureKit window capture with global mouse
and keyboard observation. Reassess sandbox feasibility before App Store distribution.

The hardened runtime is enabled for packaged builds. Certificate-signed releases
retain library validation. Local ad-hoc packages disable library validation so a
teamless build can load the embedded Sparkle framework. The shipping entitlement
file contains no microphone or input-synthesis capabilities.

## Permissions and capture

- Screen Recording is checked without prompting at launch and requested through
  the sidebar's Allow Access action.
- Keystroke highlighting requests Accessibility when the user enables it.
- VoiceMode and all speech, AI-provider, and synthesized-input code have been
  removed. The app does not read saved provider credentials or record audio.
- Only the selected source window is captured. Stream identity and frame
  generations prevent retired sources from publishing under a new selection.
- Stage Only hides workspace tools, the source list, status strip, and toolbar.
  Restoring controls during window sharing makes them visible to the audience.
  Native window chrome remains subject to the meeting app's capture behavior.
- The source-following tool widget is an independent panel, not a child of the
  source or workspace. It is visible when sharing an entire display.

## Data handling

Captured content stays in the local rendering pipeline. Presentation effects
observe the focused source; they do not send screenshots or transcripts to an
external service. Window titles are treated as display data.

Imported logos are dimension-checked, downsampled, normalized as PNG, and stored
atomically in Application Support. UserDefaults contains a storage-version
marker, with one-time migration of older logo blobs.

Public updates use an HTTPS Sparkle appcast and EdDSA signatures. Feed and
public-key metadata must be configured together. Unconfigured local builds
leave the updater inactive. Release signing and notarization credentials remain
outside the repository.
