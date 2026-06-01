# OpenLARP

OpenLARP is an iOS-first career action app: a "Duolingo for careers / LinkedIn" experience built around daily quests, proof, progress, and a long-term career agent vision.

## Current Stage

This repository is a local-first public beta V0 candidate. The app is not production-service-backed yet, but the main on-device loop is implemented and test-covered.

It currently includes:

- Planning and product strategy documents in `docs/`
- A native SwiftUI iOS app shell with Today, Map, Progress, and Profile tabs
- Goal setup and a deterministic local "Am I Cooked?" diagnostic
- A seven-day quest plan generated from the user's target role
- Local quest start, proof/self-report, mock quality check, XP, streak, badges, and readiness updates
- Daily cadence rules that lock the next quest until the next local day
- Intentional skip-today and missed-day recovery states
- Proof text, links, and local screenshot/photo attachment metadata
- App-private local proof attachment file storage
- Proof receipts, proof detail, proof archive, completed quest detail, and map preview surfaces
- JSON persistence in the app documents directory
- XCTest coverage for the core local engine, persistence, proof attachments, proof archive/detail, cadence, skip, and recovery behavior

It does not yet include:

- Real AI calls
- Backend/auth or cross-device sync
- Cloud proof uploads
- Push notifications
- Subscriptions/paywalls or payment processing
- Production analytics
- CI
- TestFlight/App Store release setup

## Project Structure

```text
OpenLARP/
  OpenLARP/                 SwiftUI app source
    Models/                 Local state, engine, persistence, and attachment storage
    Resources/              Asset catalogs
    Style/                  Shared colors, cards, pills, button styles
    Views/                  State-driven V0 product screens
  OpenLARPTests/            XCTest coverage for the local V0 behavior
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

The current app remains quest-first. The Agent Helper is local/mock support for the action loop, not the primary product surface.

## Development Notes

- Keep secrets out of the repository.
- Do not commit Xcode user state, build output, provisioning profiles, certificates, `.env` files, or local machine config.
- Use branches for feature work.
- Keep V0 narrow and focused on the daily quest loop before adding agent search, resume help, interview prep, or community features.

## Useful Docs

- `docs/PRODUCT_ROADMAP.md`
- `docs/AGENT_ARCHITECTURE_ROADMAP.md`
- `docs/BACKEND_AI_ARCHITECTURE.md`
- `docs/FOUNDER_DECISIONS.md`
- `docs/IOS_PRODUCT_ARCHITECTURE.md`
- `docs/UX_FEATURE_PROMPT.md`
- `docs/DEVELOPMENT_ROADMAP.md`
