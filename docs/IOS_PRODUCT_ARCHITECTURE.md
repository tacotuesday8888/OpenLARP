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

The MVP version can start with text and link proof only.

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
6. App creates the first mission.

Output:

- Current state summary.
- Main gap.
- Risk level.
- Best target.
- Backup targets.
- First 7 days.
- First daily quest.

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

## Onboarding Architecture

### Onboarding Goal

Get enough context to produce a credible first quest without making the user feel interrogated.

### Rich V0 Review Boundary

The implemented first-run flow uses four short stages: name the outcome, describe the current reality, choose a realistic commitment, and review OpenLARP's understanding. Service-enabled beta builds may first offer Apple, Google, or device-only entry; local-only public builds begin the career questions directly.

The review is a product trust boundary, not a cosmetic summary:

- User-entered facts remain pending until the person approves the understanding.
- AI suggestions must appear separately as hypotheses and require explicit confirm, edit, or reject action.
- Missing optional information stays visibly unknown; OpenLARP must not fill it with a plausible story.
- A goal, readiness check, and plan become durable only after approval.
- The exact reviewed records—and their identifiers, provenance, edits, confirmations, and rejections—cross the approval boundary; approval must not regenerate a cleaner replacement summary.
- If the service is unavailable, the same approved facts feed the deterministic local readiness and plan fallback.
- Account-enabled builds resolve the active protected workspace before accepting answers and clear an unfinished draft if the workspace owner changes.

Legacy saved goals migrate conservatively. Facts that existed in the old goal remain attributed to migration, while fields introduced later—such as urgency or daily commitment—remain unknown until reviewed.

Cloud mapping follows the same knownness rule. A compatibility default may keep old local behavior running, but it is omitted from downstream career-goal fields until the provenanced understanding says the user confirmed it.

Live adaptive questioning is the next service milestone. The client-side provenance contract is ready for it, but the current first-run questions are guided and deterministic.

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

1. Receives reminder.
2. Opens Today.
3. Completes quest.
4. Submits proof.
5. Sees progress.

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
