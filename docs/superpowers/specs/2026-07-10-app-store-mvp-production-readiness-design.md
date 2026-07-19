# OpenLARP App Store MVP Production-Readiness Design

**Date:** 2026-07-10

**Status:** Approved direction; implementation planning pending user review

**Product target:** A trustworthy, high-quality first public iOS release

## 1. Objective

Prepare OpenLARP's core iOS experience for App Store submission without waiting for the entire long-term roadmap.

The first public release must make every visible promise work correctly. Incomplete Agent, cloud-sync, subscription, and provider-specific AI capabilities will remain in the codebase behind internal release gates. They will not appear as broken or simulated public features.

The core product promise is:

> OpenLARP turns a real career goal into a focused seven-day proof sprint, helps the user complete one useful action each day, and shows honest progress based on what the user actually did.

## 2. Confirmed Product Decisions

- The App Store MVP is the immediate priority.
- Future roadmap capabilities remain planned but do not block the first release.
- Users under 18 must be supported.
- The AI/provider boundary must remain swappable.
- Provider-specific live AI is a separate workstream; provider-independent core work can proceed first.
- The public app must not expose mocks, no-op controls, sample opportunities, or developer infrastructure.
- User claims and proof must be represented honestly. The app must not claim it inspected content that it did not inspect.

## 3. Approaches Considered

### Submit the current beta and fix it later

Rejected. The current build contains public dead ends, simulated Agent behavior, incomplete subscriptions, weak data isolation, and unfinished release assets. Shipping it would create privacy and App Review risk.

### Finish the entire product roadmap before submitting

Rejected. Persistent agents, opportunity monitoring, resume tools, interview preparation, community, Android, and other later systems would delay validation of the core behavior without making the first release more coherent.

### Ship a narrow, complete production MVP

Selected. Finish the goal-to-proof-to-progress loop, make data handling safe, complete the seven-day lifecycle, hide unfinished systems, and verify the exact public experience through TestFlight before submission.

## 4. Public Release Contract

### Public navigation

The App Store MVP has four tabs:

1. **Today** — goal setup, diagnostic, current quest, proof coaching, recovery, and sprint completion.
2. **Map** — seven-day sprint overview and quest status.
3. **Progress** — readiness trend, XP, streak, outcomes, badges, and proof archive.
4. **Profile** — user settings, privacy, support, data controls, and optional account controls when safe.

The Agent tab and Agent chat are hidden from the public release until they produce real, persisted value. The underlying code remains available to internal builds.

### Public core journey

1. The user establishes a real career goal.
2. OpenLARP produces an honest diagnostic without pretending to know more than the provided information supports.
3. OpenLARP creates exactly seven quests suited to the goal and available time.
4. The user completes one quest at a time.
5. The user supplies proof or explicitly chooses a self-report.
6. OpenLARP gives coaching about the submission it can actually inspect.
7. The user claims progress and receives the next quest or recovery state.
8. Day seven produces a useful sprint report and a clear choice to continue, adjust the goal, or start another sprint.

### Release access mode

The first public configuration defaults to **free and non-expiring** until App Store products, RevenueCat configuration, paywall disclosures, purchase restoration, and lifecycle testing are complete.

Subscription code remains behind a release mode. Internal builds may continue exercising it. A public build must never lock the core experience unless a complete purchase path is available and verified.

## 5. Release Configuration and Feature Gates

Introduce one centralized release configuration rather than scattering beta checks through views.

The configuration owns:

- public versus internal build mode;
- free versus subscription access;
- Agent visibility;
- developer diagnostics visibility;
- cloud-sync visibility;
- live versus deterministic AI capability;
- release support and privacy URLs.

The App Store configuration must fail the release gate if it enables a capability without its required configuration. Examples:

- Agent visibility requires a real Agent service and functional chat behavior.
- subscription access requires configured products, offering, purchase, restore, legal links, and sandbox verification;
- cloud-sync wording requires restore, conflict, and deletion behavior;
- live AI requires an approved provider, production environment, safety evaluation, cost controls, observability, and a client-compatible response contract.

## 6. Local Identity, Persistence, and Privacy

### Identity isolation

Device-local data must never be silently rebound from one Firebase account to another.

Persistence will distinguish:

- a device-local guest identity; and
- each authenticated account identity.

State and proof attachments will be stored under an owner-specific container. Switching accounts loads the matching container. Signing out returns to the guest container or an explicit signed-out state; it does not expose the previous account's data.

Legacy global state will migrate once into the guest container. Moving guest progress into an account must be an explicit user action, never an automatic side effect of signing in.

### Data controls

Profile will provide:

- **Export My Data**;
- **Erase All On-Device Data**;
- **Delete Cloud Account**, when signed in;
- clear explanations of what each action removes and retains.

Erasing local data removes state, proof drafts, committed proof attachments, cached previews, and owner-specific metadata. Account deletion must not imply that retained local data was deleted.

### File policy

- Sensitive state and attachments use iOS complete file protection.
- Temporary drafts and caches are excluded from device backups. The backup behavior of committed user-created proof is documented and tested rather than changing implicitly.
- Attachment paths are validated to remain inside the expected owner directory.
- File cleanup is covered by automated tests.

## 7. Goal, Sprint, and Historical Data Semantics

"Change Goal" and "Erase All Data" must not be the same operation.

- **Change Goal** ends the active sprint and starts goal setup while preserving completed proof receipts, outcomes, and historical progress.
- **Start Another Sprint** preserves the completed sprint and generates a new seven-day sprint.
- **Erase All On-Device Data** is the only action that intentionally destroys all local history.

The data model will represent completed sprint history explicitly rather than forcing a new goal to replace the only stored sprint. Migration must preserve the current active state.

Day-seven completion includes:

- quests completed;
- proof submitted;
- readiness changes supported by recorded actions;
- outcomes logged;
- a short, honest summary;
- next recommended focus;
- continue, adjust goal, and new-sprint actions.

## 8. Proof Lifecycle and Truthful Coaching

### Attachment ownership

Selected photos first enter a draft staging area owned by the proof composer. They move into committed proof storage only when the proof is claimed. Cancelling, abandoning, switching to self-report, resetting the active draft, or failing validation removes uncommitted files.

The composer allows at most four attachments total across repeated picker actions, accepts supported image content types, limits each processed attachment to 8 MB, and compresses oversized photos when appropriate.

### Proof types

- **Evidence:** requires content the app can use, such as written context, a link plus pasted explanation, or an attachment.
- **Self-report:** requires a written reflection and cannot receive evidence-level language merely because a discarded attachment existed earlier.

### Honest evaluation

Until an approved production model receives explicit image content, the product must not say that it visually inspected a photo. Until a safe retrieval design exists, the product must not say that it opened or verified a URL.

Public wording will describe the current behavior as proof coaching or submission review. Results must distinguish:

- what was inspected;
- what was not inspected;
- why the submission is useful;
- how the user could make it more defensible.

Arbitrary server-side URL fetching is outside this MVP design. Users may paste the relevant excerpt or explanation instead.

## 9. AI Boundary

The iOS app continues to depend on a narrow `V0AIWorkflowServicing`-style interface rather than any provider SDK.

The four production AI jobs are:

1. diagnostic;
2. seven-day quest plan;
3. proof coaching;
4. sprint/progress summary.

Every provider implementation must return the same validated product contracts. The deterministic implementation remains a fallback and test oracle, but public copy must not present deterministic heuristics as objective AI judgment.

The later provider workstream must include:

- a provider whose terms support the intended audience;
- structured generation and strict validation;
- fabricated-credential and prompt-injection defenses;
- bounded input and output;
- retry, timeout, and fallback behavior;
- privacy-safe observability;
- cumulative cost controls and a kill switch;
- evaluation and canary release gates;
- explicit consent before sending private proof media.

Changing the provider must not require rewriting SwiftUI views, local persistence, or sprint rules.

## 10. Cloud and Account Scope

Authentication may remain available only after account isolation and deletion behavior pass device testing.

The public app will not describe upload-only behavior as full synchronization. A public cloud-sync feature requires:

- reading and restoring the user's state on another device;
- deterministic conflict handling;
- propagation of deletions or tombstones;
- private-evidence consent and revocation;
- account deletion that covers server-owned data;
- App Check enforcement and signed-device verification.

Until then, cloud infrastructure may support internal testing without being presented as a complete public benefit.

## 11. Error Handling and Offline Behavior

- The core local journey remains usable without a network connection.
- Loading states identify the action in progress.
- Recoverable network, quota, provider, and decoding failures show plain-language recovery actions.
- AI failure falls back to a clearly described local plan when safe.
- No tab silently hides a failed save or dismisses a form after rejection.
- Public error messages do not expose Firebase, provider, schema, or raw server details.

## 12. Accessibility and Product Quality

The release must be verified for:

- Dynamic Type through accessibility sizes;
- VoiceOver labels, order, and asynchronous announcements;
- sufficient text and control contrast;
- narrow and large iPhone layouts;
- dark mode;
- Reduce Motion;
- keyboard presentation and dismissal;
- loading, empty, success, failure, and destructive confirmation states.

Centralized style tokens remain the source of truth. Fixed typography and one-off styles will be changed only where they prevent accessibility or consistent release behavior.

## 13. Testing Strategy

### Unit and contract tests

- release configuration cannot expose unconfigured capabilities;
- guest and account data remain isolated;
- account switching never adopts another owner's state;
- local erase removes all owner files;
- change-goal and new-sprint actions preserve history;
- abandoned proof drafts clean their files;
- proof-kind switching cannot create invalid or orphaned submissions;
- seven-day plans and completion summaries meet invariants;
- AI provider and fallback results satisfy the same contracts.

### UI tests

Add a focused release UI target covering:

- first launch and goal setup;
- diagnostic to first quest;
- weak and strong proof coaching;
- claim progress and advance;
- missed-day recovery;
- day-seven completion and new sprint;
- change goal;
- local data erase;
- account switch isolation if accounts are public;
- free/subscription release-mode behavior;
- privacy and support links.

### Manual and signed verification

Verify the exact App Store build on physical small and large iPhones, with large text and VoiceOver. Exercise authentication, photo selection, sharing, background/relaunch, offline recovery, account deletion, and any enabled purchase path. TestFlight precedes App Store submission.

## 14. Release Operations

The release candidate requires:

- a real app icon;
- signing team and distribution configuration;
- hosted Privacy Policy and Support pages;
- in-app Privacy, Terms, and Support links;
- accurate App Privacy disclosures;
- crash reporting and privacy-safe operational metrics;
- final screenshots and metadata;
- export-compliance, age-rating, and regional compliance answers;
- App Review notes and credentials when required;
- CI required for changes entering the release branch;
- a release gate that checks public configuration, icon assets, legal URLs, and absence of public mock surfaces.

## 15. Workstream Order

The program is intentionally split into bounded implementation plans:

1. **Release mode and public feature gates** — free public mode, four-tab shell, hidden mocks and diagnostics.
2. **Identity-safe persistence and data erase** — owner containers, migration, local erase, file policy.
3. **Proof and reset integrity** — staging, validation, cleanup, truthful copy, history preservation.
4. **Sprint completion and continuation** — sprint records, day-seven report, new sprint and change-goal behavior.
5. **Production AI provider** — provider selection, real generation, evaluation, safety, cost, and rollout.
6. **Cloud/account completion** — only if retained as a public MVP capability.
7. **Accessibility, UI tests, observability, and release assets.**
8. **Signed device QA, TestFlight, App Store submission, and review follow-through.**

Each workstream receives its own implementation plan and verification before the next release dependency is enabled.

## 16. Definition of Done

The App Store MVP is ready to submit when:

- every visible action has a complete result or clear recovery state;
- no public surface describes mock or simulated functionality as real;
- local and account data cannot cross users;
- proof files have a complete creation-to-deletion lifecycle;
- the seven-day sprint has a useful ending and continuation path;
- access cannot expire without a functioning purchase route;
- legal, privacy, support, icon, signing, and metadata requirements are complete;
- accessibility and release UI journeys pass;
- the signed build passes physical-device and TestFlight verification;
- any enabled AI, account, cloud, or purchase capability meets its additional production gate.
