# BetterMeets security and distribution model

BetterMeets is a directly distributed, Developer ID-signed macOS utility. The
shipping target intentionally does not enable App Sandbox because its core job
combines ScreenCaptureKit window capture, global event observation,
Accessibility inspection, and user-authorized event synthesis. App Sandbox
feasibility must be reassessed before pursuing Mac App Store distribution; do
not add temporary-exception entitlements as a substitute for that review.

The hardened runtime is enabled for local packaged builds and Developer ID
releases. The only explicit entitlement is microphone input for Demo Mode.
Screen Recording, Microphone, and Accessibility remain user-controlled macOS
privacy grants and are requested only when their features need them.

## Input-synthesis boundary

Input synthesis is disabled by default. It requires the presenter to select
“Highlight and click” and grant Accessibility access. `DemoActionExecutor` is
the only component allowed to post mouse or keyboard events.

- Model-proposed clicks require an explicit, un-negated spoken click/navigation
  command.
- Model-proposed typing requires an explicit, un-negated type/write/enter
  command, and the complete typed payload must appear in the transcript at the
  command's payload position.
- The selected window, PID, and exact focused editable Accessibility element
  are revalidated before every typed character.
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

## Cloud model lifecycle

Default model identifiers live in `Resources/Info.plist`. Operational builds can
override them with `BETTERMEETS_ANTHROPIC_MODEL` and
`BETTERMEETS_OPENAI_MODEL`. Overrides are validated before use. Request-contract
tests protect required headers and JSON fields, but release owners must still
review provider deprecation notices before shipping.
