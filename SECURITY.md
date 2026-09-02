# BetterMeets security and distribution model

BetterMeets is a directly distributed, Developer ID-signed macOS utility. The
shipping target intentionally does not enable App Sandbox because its core job
combines ScreenCaptureKit window capture, global event observation,
Accessibility inspection, and user-authorized event synthesis. App Sandbox
feasibility must be reassessed before pursuing Mac App Store distribution; do
not add temporary-exception entitlements as a substitute for that review.

The hardened runtime is enabled for local packaged builds and Developer ID
releases. Shipping builds grant only microphone input for Demo Mode and retain
library validation. Local ad-hoc packages additionally disable library
validation because ad-hoc code has no Developer Team ID with which macOS can
validate the embedded Sparkle framework; this development-only exception is not
used for public releases. Screen Recording, Microphone, and Accessibility remain
user-controlled macOS privacy grants and are requested only when their features
need them.

## Input-synthesis boundary

Input synthesis remains dormant until the presenter enables Demo Mode. Within
Demo Mode, the default “Highlight and click” setting permits actuation only when
the presenter uses an explicit action command and grants Accessibility access.
`DemoActionExecutor` is the only component allowed to post mouse or keyboard
events.

- Model-proposed clicks require an explicit, un-negated spoken click/navigation
  command.
- Model-proposed typing requires an explicit, un-negated type/write/enter
  command, and the complete typed payload must appear in the transcript at the
  command's payload position.
- The selected CG window must uniquely match the focused Accessibility window;
  its PID and exact focused editable element are revalidated before every typed
  character. Ambiguous same-process windows fail closed.
- Consent, provider, source, and focus generations invalidate stale cloud work.

Treat screenshots, OCR, Accessibility labels, window titles, and model output as
untrusted data. Prompt instructions are defense in depth, never the final
authorization boundary.

## Data handling

- Speech transcription is on-device. Audio is not sent to cloud providers.
- Cloud understanding is off by default and sends a transcript plus a shared
  window screenshot only after explicit provider-specific consent.
- API keys are stored in Keychain with this-device, when-unlocked accessibility.
- Cloud requests use ephemeral URL sessions without persistent cookies or cache.
- Imported stage logos are dimension-checked, downsampled, normalized as PNG,
  and atomically stored under Application Support. UserDefaults contains only a
  storage-version marker; legacy image blobs migrate once.
- Public updates use an HTTPS Sparkle appcast plus EdDSA signatures. Feed and
  public-key metadata are injected together at release packaging time; partial,
  insecure, and unconfigured local builds cannot start the updater.

## Cloud model lifecycle

Default model identifiers live in `Resources/Info.plist`. Operational builds can
override them with `BETTERMEETS_ANTHROPIC_MODEL` and
`BETTERMEETS_OPENAI_MODEL`. Overrides are validated before use. Request-contract
tests protect required headers and JSON fields, but release owners must still
review provider deprecation notices before shipping.
