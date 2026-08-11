# OpenLARP iOS Product Architecture

## Scope

This document describes the product architecture for a future iPhone-first SwiftUI app. It does not define code, data models, Firebase setup, or implementation details.

The core product question is:

> What should the user do today to become more credible for the person they want to become?

## Product Principles

### 1. One Main Daily Action

The home screen should not be a generic dashboard. It should make the next action obvious.

### 2. Honest Progress Over Vanity Metrics

XP and levels are secondary. The primary progress should show real gap shrink.

### 3. Private First

Career insecurity is sensitive. The app should feel like a private training room, not a public profile.

### 4. Proof Over Claims

The app should encourage evidence:

- Projects.
- Messages sent.
- Interview practice.
- Resume improvements.
- Target lists.
- Portfolio artifacts.
- Real applications.

### 5. Playful But Credible

OpenLARP can use game language, but it must not feel childish. The tone should be witty, direct, and useful.

## Main Navigation

Recommended tab structure:

1. Today
2. Progress
3. Plan
4. Assets
5. Profile

Avoid more than five tabs.

## Screen Map

### 1. Today

Purpose:

The daily command center.

Primary components:

- Current level.
- Today's quest.
- Why this quest matters.
- Estimated time.
- Difficulty.
- Gap affected.
- Start quest button.
- Proof submission.
- Streak/re-entry state.

Key states:

- New quest available.
- Quest in progress.
- Proof submitted.
- Quest completed.
- Missed day recovery.
- Weekly mission active.

Design priority:

The user should understand in five seconds what to do next.

### 2. Quest Detail

Purpose:

Guide the user through one specific action.

Components:

- Quest title.
- Objective.
- Context.
- Step-by-step instructions.
- Example output.
- Proof required.
- Time estimate.
- "I did it" submission.
- "This is too hard" escape hatch.
- "Swap quest" option if the quest is badly matched.

Important:

Every quest should make the user act outside the app or improve a real asset.

### 3. Proof Submission

Purpose:

Convert checklists into evidence.

Supported proof types:

- Text pasted by user.
- Link.
- Screenshot.
- File upload later.
- Reflection.
- Voice recording later.

Rich V0 supports written descriptions, links, screenshots, photos, and explicit self-reports. Image bytes remain app-private and are not transmitted to the AI review workflow; the review can use only the written description, link format, and attachment metadata. The receipt always discloses what was and was not inspected. AI contributes bounded coaching, while deterministic client rules own rewards and readiness.

After a submission is claimed, its receipt remains immutable and an editable evidence card is created. Users may refine the completed-action wording, a reusable future-use note, a personal note, and a private note. Quest identity, readiness gap, source proof, confirmation state, timestamp, and provenance cannot be silently rewritten.

### 4. Progress

Purpose:

Show that the user is becoming more credible.

Primary sections:

- Overall readiness.
- Gap bars.
- Recent proof.
- Completed quests.
- Weekly level-up summary.
- Trend over time.

Recommended gap categories:

- Target clarity.
- Role fit.
- Skill proof.
- Experience proof.
- Resume credibility.
- LinkedIn credibility.
- Network strength.
- Interview readiness.
- Application execution.

Avoid presenting fake precision. Use labels such as:

- Missing.
- Weak.
- Developing.
- Credible.
- Strong.

### 5. Plan

Purpose:

Show the user's current questline without overwhelming them.

Sections:

- Current mission.
- This week's quests.
- Upcoming milestones.
- Backup targets.
- Stepping-stone path.
- Completed mission archive.

Design principle:

Show enough future structure to create confidence, but not so much that users feel buried.

### 6. Assets

Purpose:

Store and improve career materials.

Initial asset types:

- Resume notes.
- LinkedIn sections.
- Project proof.
- Outreach messages.
- Interview stories.
- Target roles.
- Job descriptions.

Later asset types:

- Resume files.
- Portfolio links.
- Application tracker items.
- Interview recordings.

Strategic note:

Assets should be outputs of quests, not the whole product.

### 7. Profile

Purpose:

Represent the user's current and desired identity.

Sections:

- Current state.
- Target identity.
- Target roles.
- Constraints.
- Time available.
- Confidence.
- Preferences.
- Ethical boundary settings.

The app should ask:

- "Who are you trying to become?"
- "What are you willing to do daily?"
- "What will you not fake?"

### 8. "Am I Cooked?" Diagnostic

Purpose:

Create the initial emotional hook and establish trust.

Flow:

1. User chooses target.
2. User provides current background.
3. User provides resume/profile/project text if available.
4. App identifies gaps.
5. App gives a blunt but constructive diagnosis.
6. App proposes an editable 14-day, two-chapter mission using only confirmed facts and clearly labeled diagnostic advice.
7. User reviews and explicitly approves the mission; target facts and ethical boundaries cannot be silently rewritten.
8. App creates the first seven-day chapter within the approved daily commitment.
9. Completing day 7 pauses the daily cadence for a grounded checkpoint report.
10. The app creates days 8–14 from readiness, counters, generated quest metadata, and proof quality scores only; private proof bodies, links, and attachment data stay on device.
11. Completing day 14 creates a durable sprint report. Starting another sprint or changing the goal preserves earned XP, proof receipts, editable evidence cards, readiness history, outcomes, and archived sprint summaries.

Output:

- Current state summary.
- Main gap.
- Risk level.
- Best target.
- Backup targets.
- First seven-day chapter, adaptive second chapter, and Day 7/Day 14 reports.
- First daily quest.
- Explicit mission approval state.

Tone:

Direct, not cruel. Funny, not unserious.

### 9. Weekly Level-Up

Purpose:

Create a strong return ritual.

Contents:

- What changed this week.
- Which gap shrank.
- Proof created.
- What still blocks the user.
- Next mission.
- Recommended target adjustment.

This should feel like a coach reviewing the user's actual work.

### 10. Rejection Recovery

Purpose:

Prevent churn after negative outcomes.

Trigger:

- User reports rejection.
- User misses multiple days.
- User says they feel stuck.

Flow:

- Normalize the event.
- Identify whether it was targeting, proof, resume, networking, interview, or market issue.
- Assign a recovery quest.

## Native Implementation Architecture

OpenLARP uses a deliberately small unidirectional architecture:

1. SwiftUI views render state and send user intent to `OpenLARPStore`.
2. The app owns one observable store as the UI source of truth. Temporary presentation state stays local to the view.
3. `OpenLARPEngine` contains synchronous state transitions and validation that can be tested without SwiftUI, Firebase, or a model provider.
4. Narrow protocols isolate AI, authentication, subscriptions, persistence, attachments, and backend sync so deterministic local behavior remains available.
5. Codable state uses explicit schema versions and conservative migrations; durable user facts, proof, readiness history, and sprint history are never reconstructed from model guesses.

This structure is intentionally not split into a view model and repository for every screen. Add a new layer only when it owns a real boundary, independently testable policy, or replaceable dependency. Keep network/model credentials and provider-specific behavior behind the server boundary, and keep business logic out of SwiftUI view bodies.

## Onboarding Architecture

### Onboarding Goal

Get enough context to produce a credible first quest without making the user feel interrogated.

### Rich V0 Review Boundary

The implemented first-run flow uses four short stages: name the outcome, describe the current reality, choose a realistic commitment, and review OpenLARP's understanding. During review, explicitly confirmed inputs may produce at most one material adaptive follow-up; the user can answer it or keep the detail unknown. Service-enabled beta builds may first offer Apple, Google, or device-only entry; local-only public builds begin the career questions directly.

The review is a product trust boundary, not a cosmetic summary:

- User-entered facts remain pending until the person explicitly confirms them during review; nothing becomes durable until final approval.
- AI suggestions must appear separately as hypotheses and require explicit confirm, edit, or reject action.
- Missing optional information stays visibly unknown; OpenLARP must not fill it with a plausible story.
- A goal, readiness check, and plan become durable only after approval.
- The exact reviewed records—and their identifiers, provenance, edits, confirmations, and rejections—cross the approval boundary; approval must not regenerate a cleaner replacement summary.
- If the service is unavailable, the same explicitly confirmed inputs feed the deterministic follow-up, readiness, and plan fallbacks.
- Account-enabled builds resolve the active protected workspace before accepting answers and clear an unfinished draft if the workspace owner changes.

Legacy saved goals migrate conservatively. Facts that existed in the old goal remain attributed to migration, while fields introduced later—such as urgency or daily commitment—remain unknown until reviewed.

Cloud mapping follows the same knownness rule. A compatibility default may keep old local behavior running, but it is omitted from downstream career-goal fields until the provenanced understanding says the user confirmed it.

The server-side adaptive intake workflow, grounding rules, post-generation validation, private service boundary, and deterministic fallback are implemented. The first-run UI now sends only explicitly confirmed facts, presents no more than one returned question and two hypotheses, preserves skipped details as unknown, and keeps every returned hypothesis pending until confirm, edit, or reject. Adaptive workflow runs are recorded without persisting the unfinished career text. The private service still requires a live authenticated development smoke before the service-backed path can be called production-ready.

## Live AI Trust Boundary

The iOS app talks only to an authenticated Firebase callable. Firebase Functions owns user identity, public request validation, safety checks, per-user quota, the expiring workflow policy, daily provider budget, and fallback selection. When every gate permits a live call, Functions uses its workload identity to obtain a Google-signed ID token for the exact private Cloud Run origin.

Cloud Run owns the Genkit/Gemini runtime and exposes only health and structured workflow routes. It does not accept a client user identity as authority, persist long-term memory, or perform external actions. Its output must match the workflow schema and pass grounding/truthfulness validation before Functions can return it. A provider timeout, malformed or unsafe output, quota/budget exhaustion, missing policy, missing service configuration, or IAM/network failure resolves to the same deterministic product behavior based on the user's approved facts.

Model choice, prompts, service location, prices, budgets, and provider credentials remain server-only. Neither layer uses long-lived key files; Cloud Run IAM and Application Default Credentials provide service-to-service authentication.

### Contextual Help Boundary

`Ask OpenLARP` is a bounded workflow inside the Cooked evaluation, mission review, quest detail, proof preparation, proof feedback, and checkpoint report. It is not a separate chat destination or a second source of product state. Each one-shot request contains only the approved goal, explicitly confirmed facts, the relevant mission/diagnostic/quest/report slice, bounded proof text and metadata when necessary, and current progress counters.

The response contract separates confirmed fact references, inferences, advice, and one concrete user-controlled next action. A returned fact reference must match an identifier in the request. Conversations are ephemeral in Rich V0: question and answer text are not written to durable state or long-term memory. Proof URLs, local attachment paths, and attachment bytes are never included; the assistant may know only that a link or attachment exists. Both client and server force memory writes and external actions off, while deterministic local answers keep every surface useful when the live service is unavailable.

### Recommended Onboarding Steps

The stages below describe the fuller product direction. Rich V0 combines them into the shorter reviewable flow above so the first quest remains reachable without a long intake.

#### Step 1: Promise

Explain in one screen:

- OpenLARP helps you become credible honestly.
- It gives one daily quest.
- It tracks real gap shrink.

#### Step 2: Current State

Ask:

- Student/new grad/career switcher/professional.
- School or current role optional.
- Current experience.

#### Step 3: Desired Identity

Ask:

- Target role.
- Target industry.
- Dream target.
- Backup openness.

#### Step 4: Evidence Upload

Ask for optional:

- Resume text.
- LinkedIn text.
- Portfolio/project links.
- Recent job description.

Make skipping easy.

#### Step 5: Constraints

Ask:

- Minutes per day.
- Comfort with networking.
- Application urgency.
- Biggest fear.

#### Step 6: Diagnostic

Show:

- "Here is where you stand."
- "Here is the main gap."
- "Here is today's first quest."

#### Step 7: Commitment

Ask the user to choose:

- 7-day sprint.
- 14-day sprint.
- 30-day campaign.

For MVP, default to 14 days.

## Information Architecture

### User-Owned Objects

Conceptually, the app revolves around:

- User profile.
- Target identity.
- Career gaps.
- Missions.
- Quests.
- Proof.
- Assets.
- Reflections.
- Outcomes.

### Hierarchy

Target Identity
-> Gap Analysis
-> Mission
-> Daily Quests
-> Proof
-> Progress
-> Updated Gap Analysis

This hierarchy matters because it prevents the app from becoming a random pile of tools.

## Core User Journeys

### Journey 1: New User

1. Hears "Am I Cooked?"
2. Chooses account-backed or device-only storage when the build supports accounts.
3. Completes the short guided intake.
4. Reviews confirmed facts, hypotheses, and unknowns.
5. Approves OpenLARP's understanding.
6. Receives diagnosis.
7. Gets first quest.
8. Submits proof.
9. Sees first gap movement.

### Journey 2: Daily Return

1. Optionally receives the generic local reminder at the time and cadence they chose.
2. Opens Today.
3. Completes quest.
4. Submits proof.
5. Sees progress.

The V0 reminder is device-local and deliberately narrow. Notification permission is requested only when the user turns reminders on after a sprint exists. The user chooses the time and either daily or weekday cadence, can disable it in-app, and gets a direct iPhone Settings recovery path when system permission is off. Pending reminders are reconciled after account restoration and app activation, cancelled when no active sprint remains, and removed during local erase. Notification content never includes a target role, goal, quest title, proof, outcome, or other private career text.

### Journey 3: Missed Days

1. User returns after missing days.
2. App does not shame them.
3. App offers a recovery quest.
4. Questline adjusts.

### Journey 4: New Job Target

1. User pastes job description.
2. App compares current proof to requirements.
3. App identifies gap.
4. App assigns a targeted quest.

### Journey 5: Weekly Review

1. User opens level-up report.
2. App summarizes progress.
3. App recommends next mission.
4. User recommits.

## Tone System

OpenLARP needs a distinctive voice:

- Blunt but kind.
- Playful but not childish.
- Honest but not discouraging.
- Practical, not motivational fluff.

Examples:

- "You are not cooked. But your proof is thin."
- "This role wants evidence. Right now you have interest."
- "Today's quest is small because avoidance is expensive."
- "Do not add skills you cannot defend. Build a tiny proof instead."

## Features To Delay

Delay until retention is proven:

- Full resume editor.
- Full job tracker.
- Resume export.
- Social feed.
- Public profiles.
- Referral marketplace.
- Employer dashboard.
- University admin dashboard.
- Auto-apply.
- Live interview copilot.
- Complex XP economy.

## First iOS Version After MVP Validation

If the concierge MVP works, the first native app should include only:

- Onboarding.
- Diagnostic.
- Today quest.
- Proof submission.
- Progress.
- Weekly report.
- Basic profile.
- Notifications.

This is enough to test whether mobile improves the habit loop.

## Product Architecture Verdict

The iOS app should not be a career toolbox. It should be a daily transformation system.

The first screen should always answer:

> What should I do today, and how does it make me less cooked?
