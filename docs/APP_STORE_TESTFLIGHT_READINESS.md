# App Store And TestFlight Readiness

This is a working launch packet for a small TestFlight beta. It is not final legal copy, not a public marketing page, and not permission to submit a paid product before Apple Developer, RevenueCat, privacy, support, and review details are finalized.

## Current Release Position

- Release type: private or small public TestFlight beta
- Product state: local-first SwiftUI V0 with Firebase-ready backend, deterministic callable AI fallback, RevenueCat-ready subscription boundaries, and live dev Firebase smoke coverage
- Primary beta promise: help students, new graduates, career switchers, and early-career professionals complete one useful career action per day, save proof, and understand readiness gaps
- Not ready to claim: production AI agent, autonomous opportunity monitoring, live paid subscription, final privacy policy, App Store public launch

## App Store Connect Draft

- App name: OpenLARP
- Subtitle: Daily proof for career readiness
- Category: Productivity
- Secondary category: Education
- Age rating intent: 4+, assuming no user-generated public feed, no unrestricted web browsing, and no mature content
- Copyright: OpenLARP project owner
- Support URL: `https://openlarp.app/support` or another owner-controlled page before submission
- Privacy policy URL: `https://openlarp.app/privacy` or another owner-controlled page before submission

## Short Description Draft

OpenLARP helps job seekers build real career proof through focused daily quests, private evidence, and readiness tracking.

## Full Description Draft

OpenLARP is a career action app for students, new graduates, career switchers, and early-career professionals preparing for a job search.

Instead of starting with a resume editor or a generic chatbot, OpenLARP helps you choose a target role, understand your proof gaps, complete one focused career action per day, and save evidence as your readiness improves.

Current beta features include:

- target-role setup
- career readiness diagnostic
- daily career quests
- proof submission with text, links, photos, and screenshots
- proof receipts and proof history
- XP, streaks, badges, and readiness movement
- private profile and evidence controls
- Firebase-ready account and backend sync foundations

OpenLARP is designed around honest career progress. It should help you frame real work better, not invent schools, employers, certificates, dates, titles, projects, or ownership claims.

Some cloud, AI, subscription, and agent features may be limited during beta while backend services are verified.

## Keywords Draft

career, jobs, internship, job search, students, graduates, resume, readiness, networking, proof, portfolio, interview

## TestFlight Beta Notes Draft

Thank you for testing OpenLARP. This beta is focused on the core career action loop:

1. Set a realistic target role.
2. Review the readiness diagnostic.
3. Start today&apos;s quest.
4. Submit honest proof using text, links, screenshots, or photos.
5. Check how your readiness, streak, and proof history change.

Please report:

- confusing goal setup or quest wording
- proof submission bugs
- readiness changes that feel wrong
- account sign-in or sync issues
- places where the app seems to encourage exaggeration instead of honest proof

Known beta limitations:

- live AI model calls may stay disabled while backend safety and dependency checks are completed
- RevenueCat/App Store subscription products may not be live
- App Check enforcement, signed archive, and broad TestFlight distribution still require final setup
- designer-led visual polish may change the interface after backend readiness is complete

## App Review Notes Draft

OpenLARP is an iOS-first career readiness beta. The app helps users complete daily career-building quests and save private proof. It does not auto-apply to jobs, send messages, publish content, or take external actions without explicit user approval.

For review, provide a test account only after Firebase Auth and TestFlight account flows are finalized. If subscriptions are enabled, provide sandbox subscription details and RevenueCat product IDs in App Store Connect, not in this repository.

## Privacy Policy Checklist

A final hosted privacy policy must cover:

- account identifiers from Firebase Auth
- target-role, profile, readiness, quest, proof, and progress data
- optional private evidence cloud sync consent
- proof attachments such as screenshots, photos, PDFs, and plain-text files
- Firebase Firestore, Storage, Functions, App Check, and Authentication usage
- RevenueCat subscription status if live subscriptions are enabled
- analytics or beta measurement events
- AI workflow routing through backend services, including no direct provider calls from the iOS app
- account deletion behavior, including local on-device progress versus cloud account deletion
- support contact and retention policy for account deletion markers, billing records, and operational logs

Do not submit broad TestFlight or App Store review until the hosted privacy policy matches the live backend and subscription behavior.

## Support Page Checklist

A support page or support email must cover:

- how to report beta bugs
- how to request account help
- how to request cloud account deletion support if an in-app deletion returns partial or unknown status
- how to get purchase/subscription support after RevenueCat products are live
- how to contact the owner for privacy questions

## Screenshot Plan

Capture final screenshots after designer-led UI is integrated. Avoid showing real private user data.

Suggested App Store screenshot story:

1. Target role and readiness diagnostic
2. Today quest and proof requirement
3. Proof submission with text/link/screenshot/photo options
4. Readiness and streak progress
5. Proof timeline or receipt detail
6. AI career agent or brief screen, if enabled for beta
7. Account privacy controls

## Pre-Submission Gates

Do not submit a build until these are true:

- `npm run public:safety` passes
- `npm run test:scripts` passes
- `npm run test:backend` passes
- `npm run build:backend` passes
- `npm run test:rules:emulators` passes
- `npm run firebase:live-readiness` passes, with App Check warnings understood
- `npm run firebase:signed-in-smoke` passes against the dev project
- Xcode build/test passes locally or in CI
- signed simulator/device Google and Apple sign-in flows are verified
- App Check enforcement rollout plan is confirmed
- RevenueCat products are either disabled for beta or fully configured and sandbox-tested
- final hosted privacy/support URLs exist
- signed archive uploads successfully to App Store Connect
