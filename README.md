# OpenLARP

OpenLARP is an iOS-first career action app. The product idea is a private AI career agent wrapped around daily career quests, proof collection, readiness tracking, and opportunity preparation.

The app is currently a SwiftUI beta foundation, not a production service. It is being built local-first while backend, AI, Firebase, RevenueCat, and TestFlight work are added in stages.

## Source-Visible, Not Open Source

This repository is public for visibility, review, and GitHub Actions access.

It is not an open-source project. No open-source license is granted. You may read the code, but copying, redistribution, commercial use, or derivative product use requires written permission from the project owner.

## What Is Here

- Native SwiftUI iOS app source in `OpenLARP/`
- XCTest coverage in `OpenLARPTests/`
- Local quest, proof, progress, and readiness models
- Backend-ready contracts for Firebase, Firestore, AI workflows, and subscriptions
- Product and architecture notes in `docs/`
- Xcode project plus `project.yml` for project generation

## What Is Not Here

- Production AI provider keys
- Firebase private plist files
- App Store signing assets
- RevenueCat keys or live product IDs
- Private user data
- Production backend secrets

## Build

Unsigned local build:

```bash
xcodebuild \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/OpenLARPDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Simulator tests:

```bash
xcodebuild test \
  -project OpenLARP.xcodeproj \
  -scheme OpenLARP \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/OpenLARPDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Signed device builds and TestFlight uploads require Apple Developer account setup in Xcode.

## Repository Hygiene

Do not commit:

- `.env` files
- `GoogleService-Info.plist`
- provisioning profiles, certificates, or App Store signing material
- Xcode user state
- build output
- private founder/application notes

The app is intentionally structured so the iOS client does not call LLM providers directly. AI providers should be routed through backend services such as Cloud Run, Cloud Functions, or Genkit.
