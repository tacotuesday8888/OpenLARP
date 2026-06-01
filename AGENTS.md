# AGENTS.md

## Project Context

OpenLARP is an iOS-first career development product.

Use the docs as the source of truth instead of relying on memory or old chat context. Keep this file short and durable; detailed product plans belong in `docs/`.

## Read First

Before major product, architecture, or implementation work, read:

- `README.md`
- `docs/DEVELOPMENT_ROADMAP.md`
- `docs/PRODUCT_ROADMAP.md`
- `docs/FOUNDER_DECISIONS.md`
- `docs/IOS_PRODUCT_ARCHITECTURE.md`

For UX-specific work, also read:

- `docs/UX_FEATURE_PROMPT.md`

If the docs disagree, ask which source should win before making broad changes.

## Technical Context

- Native iOS first.
- SwiftUI app.
- Keep architecture simple and maintainable.
- Use ShipSwift selectively for useful SwiftUI UI, motion, share, or paywall components.
- Do not let generated UI/component code dictate the app architecture.

## UI Direction

Treat UI and UX quality as important to the product, especially for public beta readiness.

Prioritize:

- Correct flows
- Clear state
- Reusable SwiftUI components
- Polished, readable layouts
- Clear interaction states
- Consistent visual hierarchy
- Centralized styling
- Accessibility and responsive behavior

Avoid:

- Deeply nested generated UI
- Visual polish that makes product logic harder to maintain
- One-off styling that should be a shared component or token
- Fancy effects that distract from the user workflow
- ShipSwift components unless they clearly support the current task and fit the app architecture

When improving UI, preserve clean state flow and architecture. A designer-led UI pass may happen at any time, so keep visual systems easy to evolve rather than version-specific.

## Product Guardrails

OpenLARP should help users make real career progress.

Do not implement flows that encourage fake employers, fake schools, fake certificates, fake job titles, fake dates, fake projects, or fake ownership claims.

When in doubt, help users frame real experience better instead of inventing facts.

## Scope Discipline

Do not add major backend, AI, subscription, marketing, Android, community, or autonomous-agent systems unless the current docs or the user explicitly ask for them.

Prefer the smallest useful version that moves the documented product forward.

## Build Check

For local source validation without Apple signing configured:

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/OpenLARPDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Definition Of Done

For meaningful development work:

- Build or test the project when practical.
- Keep secrets, local files, Xcode user state, and build outputs out of Git.
- Commit intentional changes.
- Keep the working tree clean unless the user asks otherwise.
- Report what changed, what was verified, and what remains.
