# OpenLARP

OpenLARP is an iOS-first career action app: a "Duolingo for careers / LinkedIn" experience built around daily quests, proof, progress, and a long-term career agent vision.

## Current Stage

This repository is at the starter foundation stage.

It currently includes:

- Planning and product strategy documents in `docs/`
- A native SwiftUI iOS starter shell
- Static sample data for the current product shape
- Core V0 screens for Today, Map, Chat, and Profile
- Basic shared styling and model types

It does not yet include:

- Real onboarding
- Real AI calls
- Backend/auth
- Persistence
- Proof upload/storage
- Subscriptions
- Production analytics
- Tests or CI

## Project Structure

```text
OpenLARP/
  OpenLARP/                 SwiftUI app source
    Models/                 Starter product models and sample data
    Resources/              Asset catalogs
    Style/                  Shared colors, cards, pills, button styles
    Views/                  Starter app screens
  OpenLARP.xcodeproj/       Xcode project
  docs/                     Product, roadmap, and architecture docs
  project.yml               XcodeGen-style project definition
```

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

The normal signed app build will require setting an Apple development team in Xcode.

## Product Direction

The V0 product loop is:

```text
Goal setup -> Am I Cooked? diagnostic -> Today quest -> proof/self-report -> AI quality check -> XP/streak/progress -> next quest
```

The app should remain quest-first. Chat is support for the action loop, not the primary product surface.

## Development Notes

- Keep secrets out of the repository.
- Do not commit Xcode user state, build output, provisioning profiles, certificates, `.env` files, or local machine config.
- Use branches for feature work.
- Keep V0 narrow and focused on the daily quest loop before adding agent search, resume help, interview prep, or community features.

## Useful Docs

- `docs/PRODUCT_ROADMAP.md`
- `docs/AGENT_ARCHITECTURE_ROADMAP.md`
- `docs/FOUNDER_DECISIONS.md`
- `docs/IOS_PRODUCT_ARCHITECTURE.md`
- `docs/UX_FEATURE_PROMPT.md`
- `docs/DEVELOPMENT_ROADMAP.md`
