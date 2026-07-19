# App Store And TestFlight Readiness

This is a working launch packet for the free, local-first App Store build. It is not final legal copy, not a public marketing page, and not permission to submit before the hosted privacy policy, support page, signed-device QA, screenshots, archive, and App Store Connect details are complete.

## Current Release Position

- Release type: free public TestFlight and App Store validation build
- Product state: local-first SwiftUI V0 with deterministic on-device diagnostic, quest-plan, and proof-review workflows
- Public navigation: Today, Map, Progress, and Profile
- Primary promise: help students, new graduates, career switchers, and early-career professionals complete one useful career action per day, save honest proof locally, and understand readiness gaps
- No account or purchase is needed. Account, cloud sync, subscriptions, and Agent are not included in this App Store build.
- Repository work still required before submission: identity-safe local persistence and complete erase, proof-draft ownership and truthful review limits, sprint history and day-seven continuation, and final accessibility/release-UI verification
- External work still required: final hosted URLs, metadata and screenshots, signed-device QA, signed archive upload, and App Store Connect completion

## App Store MVP Release Profile

- Release builds resolve to the fail-safe `app-store` profile and explicit local-only service mode.
- The public profile is free and non-expiring.
- OpenLARP does not upload or sync career goals, progress, proof text, links, or private proof attachments in this release. iOS device backups may include app data according to the user's device backup settings.
- Public navigation contains Today, Map, Progress, and Profile.
- No sign-in, OpenLARP cloud backup, cross-device sync, subscription, purchase, or Agent surface is present.
- Ignored Firebase and RevenueCat configuration plists are copied only into the separate `internal-beta` build and are absent from the App Store Release bundle.
- Debug builds retain the separate `internal-beta` profile for service-enabled development and verification.

## Repository-Controlled Release Verification

- `OpenLARPReleaseContract` compiles the real app module with the optimized Release configuration and keeps `ENABLE_TESTABILITY=NO`.
- Its separate XCTest target uses ordinary `import OpenLARP`, not `@testable import`, and reads a minimal immutable snapshot derived from the bundled release channel and the same presentation/lifecycle policies used by the SwiftUI app.
- The contract verifies the hosted app bundle identifier, literal `app-store` plist value, free/local-only service posture, empty unfinished-capability set, no live AI, exact public tabs and ordered sections, local-only privacy presentation, local-only lifecycle, and absence of Firebase/RevenueCat local configuration plists.
- CI fails when simulator discovery fails, when the optimized contract test is skipped or does not run exactly once, when the Release app enables testability, or when the unsigned generic build is not Release.
- The JavaScript repository gate validates the structured XcodeGen and GitHub Actions wiring plus non-Swift readiness files. Swift behavior is proven by compiled XCTest rather than source-text parsing.

These automated checks do not replace signed-device visual and interaction QA. The final local flow, accessibility, layout, offline behavior, signing, archive, and uploaded build still require the external checks below.

## App Store Connect Draft

- App name: OpenLARP
- Subtitle: Daily proof for career readiness
- Category: Productivity
- Secondary category: Education
- Age rating intent: 4+, assuming no public user-generated feed, unrestricted web browsing, or mature content
- Copyright: OpenLARP project owner
- Support URL: `https://openlarp.app/support` or another owner-controlled page before submission
- Privacy policy URL: `https://openlarp.app/privacy` or another owner-controlled page before submission
- Price: Free
- Account requirement: None
- In-app purchase requirement: None

## Short Description Draft

OpenLARP helps job seekers build real career proof through focused daily quests, private on-device evidence, and readiness tracking.

## Full Description Draft

OpenLARP is a local-first career action app for students, new graduates, career switchers, and early-career professionals preparing for a job search.

Instead of starting with a resume editor or generic chatbot, OpenLARP helps you choose a target role, understand your proof gaps, complete one focused career action per day, and save evidence as your readiness improves.

Features in this build include:

- target-role setup and an on-device career readiness diagnostic
- a Today tab with one focused career quest
- a seven-day Map that shows the near-term plan
- proof submission with text, links, photos, and screenshots
- proof receipts, proof history, XP, streaks, badges, and readiness movement
- a Progress tab for local milestones and readiness
- a Profile tab for goal details and local privacy information

OpenLARP is designed around honest career progress. It should help you frame real work better, not invent schools, employers, certificates, dates, titles, projects, or ownership claims.

No account or purchase is required. Account, cloud sync, subscriptions, and Agent are not included in this App Store build. OpenLARP does not upload or sync career data in this release. iOS device backups may include app data according to the user's device backup settings. Exported items leave the app only when the user explicitly shares them through iOS.

## Keywords Draft

career, jobs, internship, job search, students, graduates, readiness, networking, proof, portfolio, progress

## TestFlight Beta Notes Draft

Thank you for testing OpenLARP. This free, local-first build is focused on the core career action loop:

1. Set a realistic target role.
2. Review the on-device readiness diagnostic.
3. Start today&apos;s quest.
4. Submit honest proof using text, links, screenshots, or photos.
5. Check how local readiness, streak, and proof history change.

Please report:

- confusing goal setup or quest wording
- proof submission or local attachment bugs
- readiness changes that feel wrong
- problems returning to Today, Map, Progress, or Profile
- places where the app seems to encourage exaggeration instead of honest proof

No account or purchase is needed for this test. Account, cloud sync, subscriptions, and Agent are not included. OpenLARP does not upload or sync career data in this release. iOS device backups may include app data according to the user's device backup settings, and deleting the app can remove local data.

## App Review Notes Draft

OpenLARP is a free, local-first iPhone career readiness app. It helps users set a target role, receive a deterministic on-device diagnostic and seven-day plan, complete daily career-building quests, save private proof on the device, and review progress across Today, Map, Progress, and Profile.

No review account is required. No purchase or subscription is required. Account, cloud sync, subscriptions, and Agent are not included in this App Store build.

Suggested review path:

1. Complete target-role setup.
2. Review the diagnostic and seven-day map.
3. Start the available Today quest.
4. Add text or link proof, or attach a non-sensitive test image.
5. Run the local proof check and review the resulting progress.

The app does not auto-apply to jobs, send messages, publish content, or take external actions. OpenLARP does not upload or sync career data in this release. iOS device backups may include app data according to the reviewer's device backup settings. Exported items leave the app only when the reviewer explicitly uses an iOS share action.

## Privacy Policy Checklist

The public privacy policy and App Store privacy answers must describe the shipped local-only build, not internal service-enabled development paths.

Before submission, confirm and document:

- target-role, profile, readiness, quest, proof, progress, and outcome data are stored on the device
- proof attachments can include user-selected screenshots and photos stored in app-private local storage
- users should avoid adding secrets or unnecessary personal information to proof
- no account identifier, email address, cloud-sync record, or purchase is required by the public build
- no career context or proof is sent to a remote workflow by the public build
- iOS device backups may include app data according to the user's device backup settings; the app does not provide its own cloud backup or cross-device sync in this release
- exported or shared items leave the app only after an explicit iOS share action
- local-data deletion and app-uninstall behavior are explained accurately
- camera/photo-library wording, privacy nutrition labels, and `OpenLARP/PrivacyInfo.xcprivacy` match the final submitted binary
- the hosted policy includes a privacy contact and an effective date

Do not submit until the hosted policy and App Store privacy answers match the final local-only binary.

## Support Page Checklist

The public support page or support email must cover:

- how to report TestFlight or App Store bugs
- how to reset a goal or remove local proof and attachments
- how to troubleshoot photo or screenshot attachment permissions
- how local progress behaves after app deletion or reinstall
- how to contact the owner for privacy questions
- a clear statement that the public build has no account, cloud sync, subscription, purchase, or Agent feature

## Screenshot Plan

Capture final screenshots after the public UI is locked. Use fictional, non-sensitive examples and avoid real private user data.

Suggested App Store screenshot story:

1. Target role and on-device readiness diagnostic
2. Today quest and proof requirement
3. Seven-day Map
4. Proof submission with text, link, screenshot, or photo options
5. Readiness, streak, and proof progress
6. Local-first Profile and privacy explanation

Do not include account, cloud-sync, subscription, purchase, developer-tool, or Agent screens.

## Pre-Submission Gates

Do not submit the public build until all of these are true:

- `npm run public:safety` passes
- `npm run test:scripts` passes
- `npm run beta:gate` passes
- the dedicated `OpenLARPReleaseContract` test passes in Release and its result bundle reports exactly one passed, zero failed, and zero skipped contract test
- the full iOS test suite passes on the supported simulator runtime
- an unsigned generic Release build succeeds and its built plist resolves exactly to `app-store`
- the complete local flow is verified on a signed physical device, including goal setup, diagnostic, Today, Map, proof text/link/photo handling, Progress, Profile, relaunch persistence, and offline behavior
- local state and proof files use owner-specific containers with a tested legacy migration, complete local erase, file protection, and documented backup behavior
- proof drafts have tested staging, attachment-count/type/size limits, cleanup on every abandonment path, and truthful results that state what was and was not inspected
- Change Goal preserves completed proof and progress history, while day-seven completion produces a useful summary and tested Start Another Sprint path
- final App Store metadata and local-only screenshots are complete
- final hosted privacy and support URLs exist and match the submitted binary
- App Store Connect privacy answers, age rating, review notes, export compliance, and availability are complete
- a signed archive validates and uploads successfully to App Store Connect
- the uploaded build completes TestFlight processing and final review smoke testing

## Internal / Service-Enabled Verification — Do Not Paste Into App Store Connect

This section applies only to the separate internal beta/service-enabled profile. It is not a feature list, limitation list, review note, privacy statement, or support promise for the App Store build.

- `npm run test:backend`, `npm run build:backend`, and `npm run test:rules:emulators` pass
- Firebase configuration, Firestore, Storage, Functions, Authentication, and App Check readiness are verified with ignored local configuration
- `npm run firebase:live-readiness` and `npm run firebase:signed-in-smoke` pass against the intended development project without exposing credentials or user data
- Google and Apple sign-in, persisted session restore, backend event sync, private-evidence consent/cleanup, and account deletion are verified on simulator and signed device
- App Check debug/device registration, metrics, enforcement rollout, and incident recovery are confirmed
- RevenueCat offerings, subscriber identity, restore, purchase, product IDs, and sandbox behavior are verified before any future service-enabled distribution
- remote deterministic workflow routing, fallback behavior, quotas, safety rules, observability, and provider-disabled behavior are verified
- live-model use remains separately approval-gated and is not implied by Agent UI or deterministic remote workflow availability
