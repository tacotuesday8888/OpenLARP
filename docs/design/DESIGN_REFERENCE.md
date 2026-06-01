# Open Design Reference

This folder preserves the original Open Design HTML export that was used to explore OpenLARP's richer visual direction.

- Source artifact: `open-design-reference.html`
- Purpose: design reference, not production source code
- Current rule: preserve the visual direction and feature ideas, but implement them through real state-driven SwiftUI screens

## What The HTML Contains

The HTML includes a full mobile app visual exploration with these major screens:

- Goal setup: "Set your goal"
- Cooked diagnostic: "The roast report"
- Duolingo-style sprint path: "Proof Sprint"
- Daily quest: "Public proof"
- Proof submission: "Add evidence"
- Proof quality result: "Review result"
- Seven-day plan: "Comeback Map"
- Progress/stats: "Less cooked"
- Proof archive: "Evidence bank"
- Recovery flow: "Not over"
- Profile/account hub: "Career Hub"
- Settings/account management: "Settings"

## Visual System

The design uses:

- Bright blue/cyan primary identity
- Coral/red cooked diagnostic accents
- Green/mint proof accents
- Purple quest accents
- Orange/yellow stats accents
- Rounded mobile screens and cards
- Chunky raised buttons with pressed states
- Feature marks/icons for each product area
- Strong top bars with screen-specific identity
- Meme-native but still structured copy

## Product Ideas Captured

The design includes product concepts that should not be lost:

- "Am I Cooked?" as a high-signal diagnostic surface
- Meme-strip explanations after the cooked score
- Proof as the main habit mechanic
- A "Proof Sprint" path, not a generic dashboard
- Proof quality result with grade, signal checklist, and next fix
- Evidence bank / proof vault
- Comeback map with locked and completed path nodes
- Missed-day recovery and streak protection language
- Career hub with goal, proof count, streak, memory/privacy, and sprint strip
- Settings concepts for account, subscription, notifications, privacy, and support

## How To Use This Reference

Use the HTML as a design source when improving SwiftUI UI/UX.

Do:

- Reuse the visual language where it supports the real product flow.
- Extract reusable SwiftUI components from the design language.
- Bring feature marks, top-bar treatments, proof cards, path visuals, progress visuals, and recovery language into state-driven screens.
- Keep the real app flow connected to `OpenLARPStore` and `OpenLARPEngine`.

Do not:

- Restore static/demo-only screens as production surfaces.
- Replace real state-driven flows with disconnected visual mockups.
- Copy every HTML feature into V0 just because it appears in the reference.
- Add backend, payments, account settings, or subscription UI unless the current product phase calls for it.

## Suggested Integration Path

1. Keep the current state-driven product shell reliable.
2. Use this design reference to recover the strongest visual identity.
3. Migrate visual ideas into the real screens:
   - `TodayView`
   - `QuestMapView`
   - `ProgressTabView`
   - `ProofArchiveView`
   - `ProfileView`
   - shared components in `OpenLARPStyle.swift`
4. Keep design-only future concepts documented until the corresponding product phase is active.

The goal is not "old design shell versus real app." The goal is:

```text
state-driven beta reliability + preserved Open Design visual direction
```
