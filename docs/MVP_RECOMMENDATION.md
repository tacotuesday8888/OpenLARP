# OpenLARP MVP Recommendation

## Brutal Starting Point

OpenLARP is not yet a product. It is a compelling metaphor wrapped around a crowded career-help market.

The dangerous assumption is that users want another app for career improvement. They probably do not. They want anxiety reduction, proof that they are moving, and a credible path to a better identity: "I am becoming the kind of person who can get that internship, job, fellowship, or promotion."

The second dangerous assumption is that gamification creates retention. XP, levels, streaks, and quests are easy to copy and easy to ignore. They only matter if the daily action has real-world consequences and the user believes the app knows them better over time.

The third dangerous assumption is that an iPhone app is the MVP. It may not be. If the goal is to test whether users want this product, the MVP should test the core loop before building infrastructure.

## The Core Hypothesis

OpenLARP should test this:

> Users will return daily if OpenLARP gives them one specific, honest, career-advancing action that feels more doable, more personalized, and more emotionally motivating than asking ChatGPT.

This is not a resume-builder hypothesis. It is not a job-tracker hypothesis. It is not an AI-coach hypothesis. It is a behavior-change hypothesis.

## The Smallest 7-14 Day MVP

Build a concierge-style mobile-first web or no-code MVP, not a full iOS app.

The MVP is:

1. A short onboarding intake.
2. An "Am I Cooked?" diagnostic.
3. A personalized 14-day questline.
4. One daily quest delivered by SMS, email, Discord, or a simple web page.
5. A lightweight proof check-in.
6. A progress page showing the user's gap shrinking.
7. A weekly "level up" report.

This tests the most important behavior: whether users come back and complete uncomfortable career actions.

## What Not To Build Yet

Do not build these in the first MVP:

- Native SwiftUI app.
- Firebase auth, database, analytics, and push notifications.
- RevenueCat subscriptions.
- Resume builder.
- LinkedIn optimizer.
- Interview simulator.
- Job tracker.
- Auto-apply.
- Full XP economy.
- Social network.
- Public profiles.
- Marketplace.
- Employer features.

These are expensive distractions before retention is proven.

## MVP Positioning

The first version should position itself as:

> A daily career leveling system that turns who you are now into who you need to become, without lying.

The product promise should be concrete:

> In 14 days, you will know your career gaps, complete 10-14 small proof-building actions, and have a more credible story for your target path.

## MVP User Segment

Start with one narrow user segment. Do not launch to all listed audiences.

Recommended first segment:

> College students and new graduates targeting their first serious internship or entry-level job.

Why:

- High pain.
- High anxiety.
- Weak career identity.
- More open to gamified language.
- More likely to share socially.
- Less entrenched in existing career tools.
- Easier to help without complex senior-career nuance.

Avoid starting with ambitious professionals. They are more skeptical, have more complex constraints, and are less likely to tolerate playful framing unless the product is extremely credible.

## MVP Core Flow

### 1. Intake

Ask only what is needed to create a useful plan:

- Current status: high school, college, new grad, switcher.
- Target role or field.
- Current resume or profile text.
- Current experience.
- Skills.
- Projects.
- Network strength.
- Application history.
- Confidence level.
- Time available per day.
- Biggest fear.

The intake should feel like a judgment-free career confession, not a form.

### 2. "Am I Cooked?" Diagnostic

This is the hook, but it must be honest.

The output should include:

- Cooked score: playful but not cruel.
- Main gap: skills, proof, story, network, targeting, execution, interview readiness.
- Why the gap matters.
- What would make the user less cooked in 7 days.
- What would make the user meaningfully stronger in 30 days.

Avoid fake precision. A 73/100 score is less credible than "You are not cooked, but your proof is too weak for product analyst roles."

### 3. 14-Day Questline

Create a personalized plan with daily quests. Each quest should be small enough to complete in 15-45 minutes.

Examples:

- Find 5 job descriptions for your target role and paste the repeated requirements.
- Rewrite one project bullet with a measurable outcome.
- Send one low-pressure message to an alum.
- Build a tiny proof artifact.
- Record a 90-second answer to "Tell me about yourself."
- Add one missing keyword honestly by doing a micro-project, not inventing experience.
- Identify one backup role that uses the same strengths.

The MVP must avoid quests that reward fake output. "Add Python to your resume" is bad. "Complete a 30-minute Python notebook and write what you learned" is closer to the philosophy.

### 4. Daily Check-In

Each day:

- Show today's quest.
- Explain why it matters.
- Ask for proof of completion.
- Reflect back progress.
- Unlock the next step.

Proof can be pasted text, a screenshot, a link, or a short written reflection.

### 5. Progress

The progress view should not only show XP. It should show reduced gaps:

- Proof gap.
- Target clarity gap.
- Resume credibility gap.
- Network gap.
- Interview readiness gap.
- Application execution gap.

The user should feel: "I am actually less behind than I was."

## Recommended MVP Feature Set

### Must Have

- Intake.
- Diagnostic.
- Daily quest.
- Proof submission.
- Manual or semi-manual personalization.
- 14-day plan.
- Progress/gap shrink view.
- Weekly summary.
- Basic retention tracking.

### Nice To Have

- Streaks.
- XP.
- Levels.
- Backup targets.
- Shareable progress card.
- Simple reminder notifications.

### Avoid

- Full resume export.
- ATS scoring.
- Auto-apply.
- Real-time interview copilot.
- Complex AI agents.
- Social feed.
- Employer marketplace.

## How To Build The MVP Without Overbuilding

The fastest credible MVP could use:

- Typeform, Tally, or a simple form for intake.
- Airtable, Notion, or Google Sheets for user state.
- Manual LLM-assisted diagnosis by the founder.
- SMS/email/Discord delivery for daily quests.
- A simple Carrd/Webflow/Framer page for the promise and signup.
- Stripe payment link only if testing willingness to pay.

The product can look less polished if the daily advice feels deeply personal. A polished generic app will lose to ChatGPT quickly.

## What To Measure

The MVP should measure behavior, not compliments.

Primary metrics:

- Day 1 quest completion.
- Day 3 return.
- Day 7 return.
- Day 14 completion.
- Proof submission rate.
- Number of quests completed per user.
- Number of users who ask for another 14-day cycle.

Secondary metrics:

- Users who invite a friend.
- Users who pay or join a waitlist after day 7.
- Users who say the product helped them do something they were avoiding.
- Users who complete networking quests.
- Users who improve an artifact: resume bullet, project, LinkedIn section, interview answer.

Do not overvalue:

- Signup count.
- "This is cool" feedback.
- Waitlist emails.
- Time spent in app.
- Generated plans that are not acted on.

## Pass/Fail Criteria

The MVP passes if, with 30-50 users:

- At least 50% complete the first quest.
- At least 30% return on day 7.
- At least 20% complete 7 or more quests in 14 days.
- At least 20% ask for another cycle or join a paid plan waitlist.
- At least 10 users provide concrete before/after proof.

The MVP fails if:

- Users love the diagnostic but do not complete quests.
- Users only use resume help.
- Users say ChatGPT can do the same thing.
- Users return only when applying to jobs, not daily.
- Users do not trust the scores.
- Users feel judged, overwhelmed, or manipulated by gamification.

## Pricing Test

Do not start free forever. Free users may praise the product while not needing it.

Test one of these:

- $19 for a 14-day guided sprint.
- $29 for a 30-day career questline.
- $49 for a founder-reviewed plan and weekly report.

The strongest early signal is not app retention alone. It is whether users pay for accountability and personalization.

## Recommended MVP

Build the "OpenLARP 14-Day Career Level-Up Sprint."

It should be a guided, semi-manual program for one narrow segment: college students and new grads trying to become credible for one target role.

The product should deliberately avoid pretending to be a complete career platform. It should test whether the daily transformation loop works:

Current State -> Gap Analysis -> Personalized Plan -> Daily Quest -> Proof -> Progress -> Level Up.

If this loop does not retain users manually, automation will not fix it.

