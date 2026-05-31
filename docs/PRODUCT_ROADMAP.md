# OpenLARP Product Roadmap

## Roadmap Thesis

OpenLARP's long-term vision is a true career agent. The product should start as an iOS-first daily career action app with a viral hook, not as a generic career chatbot and not as a manual concierge service.

The simple product promise is:

> Duolingo for LinkedIn: a daily career leveling app that helps users become stronger candidates without faking credentials or experience.

The V0 bet is growth first, then conversion. The first month should test whether the "Am I Cooked?" hook can spread on Instagram and TikTok, pull users into a polished iOS beta, and convert enough serious users into a paid monthly subscription after a free 14-day sprint.

## V0: iOS Career Level-Up Beta

### Features

- Native iOS app, launched with a simple web waitlist.
- Waitlist website with a short explanation, app preview, email capture, student/new-grad status, and career goal.
- Creator application path on the website for AI-tool creators and campus creators.
- Goal setup as the first app experience.
- "Am I Cooked?" diagnostic tied to the user's goal.
- Funny, meme-friendly diagnostic surface that turns into practical guidance.
- Today screen with one primary quest.
- Seven-day quest map so the user can see the near-term path without being overwhelmed.
- Daily proof and self-report flow.
- Proof submission through text, links, photos, and screenshots.
- AI quality check that gives lightweight feedback on submitted proof.
- Goal-readiness progress view using XP, streaks, proof, and gap movement.
- Forgiving streaks with recovery quests or limited recovery mechanics.
- Badges for streaks, proof milestones, and major outcomes.
- Shareable "Am I Cooked?" cards that are funny and hopeful without exposing private details.
- Optional sharing for streaks, badges, and outcomes.
- Push notifications for useful quest reminders and goal-related nudges.
- Quick outcome log for major events such as applied, interview, rejection, offer, or changed goal.
- Minimal profile by default, with extra questions asked only when needed.
- Privacy controls for sensitive chat and memory.

Do not build in V0:

- Android.
- Full web app.
- Resume builder.
- Interview prep.
- Cloud agent search.
- Direct LinkedIn or job-board integrations.
- Full job tracker.
- Community or social feed.
- Human review workflow.
- Auto-apply.
- Live interview copilot.
- School dashboard.
- Employer dashboard.

### Goals

- Prove that the "Am I Cooked?" hook can generate attention, waitlist signups, app installs, and creator interest.
- Prove that users understand OpenLARP as "Duolingo for careers" after the initial meme hook.
- Prove that users complete daily quests and submit proof or meaningful self-reports.
- Prove that a sharp but narrow iOS app can support a 14-day free sprint.
- Prove that some users convert to a monthly subscription after the free sprint.

### Assumptions Being Tested

- College students and new grads are the best starting audience because the meme language and career anxiety match their behavior.
- Other users can still use the product, but the first growth and UX decisions should favor early-career users.
- Users want proof, confidence, and job readiness together, with proof as the foundation.
- A polished iOS hook matters more than a broad feature set.
- Users will tolerate minimal onboarding if the app asks more questions only when needed.
- AI can provide useful diagnostics, quests, proof checks, and progress summaries without human review.
- A free 14-day sprint creates enough value to support a paid monthly plan.

### Engineering Complexity

Medium.

V0 is intentionally narrow, but native iOS, AI diagnostics, proof uploads, push notifications, XP/streak logic, share cards, and payments still make it more complex than a manual MVP. The complexity is acceptable only because the chosen strategy is iOS-first and viral-growth-first.

### User Value

- A fast answer to "Am I cooked for this goal?"
- A clear daily quest instead of vague career advice.
- A visible path for the next seven days.
- Proof that the user is becoming more credible.
- A game-like sense of momentum through XP, streaks, and badges.
- Career preparation that feels funny at the hook but serious when it matters.

### Retention Impact

V0 should create habit through Today quests, a seven-day map, forgiving streaks, and progress toward goal readiness. The product should not judge success by app opens alone.

The first-month priority is:

1. Viral growth.
2. Waitlist and install conversion.
3. Free sprint completion.
4. Subscription conversion.

Key metrics:

- TikTok and Instagram views, shares, saves, and comments.
- Waitlist signups from social content.
- Creator applications and creator posts.
- App installs from waitlist and creators.
- Day 1 quest start.
- Day 7 proof activity.
- 14-day sprint completion.
- Subscription conversion after the free sprint, with 10%+ as an early promising signal.

## V1: Quest-Linked Resume And Profile Help

### Features

- Quest-linked resume help.
- Resume and LinkedIn bullet improvements based on real proof the user has completed.
- Asset area for proof, resume material, certificates, outcomes, and interview stories.
- Goal-specific resume suggestions from pasted job descriptions or links.
- Tone controls for conservative, balanced, or aggressive packaging.
- AI-decided packaging option that still obeys hard bans against fake claims.
- More detailed goal-readiness progress.
- Better badge and XP weighting so proof matters more than passive activity.
- Subscription paywall after the first free 14-day sprint.
- $29/month standard pricing with a student discount.

### Goals

- Convert completed quests into stronger career materials.
- Make resume help feel earned and specific, not like a generic rewrite tool.
- Give users a reason to keep paying after the first sprint.
- Strengthen the connection between proof, confidence, and job readiness.

### Assumptions Being Tested

- Resume help is more valuable when it is connected to completed proof.
- Users will pay monthly when OpenLARP keeps improving their materials and daily plan.
- Aggressive packaging can be useful if every claim remains true and defensible.
- Users prefer one subscription after the free sprint over paying for each sprint.

### Engineering Complexity

Medium.

V1 needs an asset model, resume/profile text handling, generated suggestions, proof-to-resume links, subscription management, and clearer controls for packaging tone. It should still avoid becoming a full resume builder.

### User Value

- Stronger resume and LinkedIn material.
- Less guesswork about what to say.
- Clear evidence behind each improved bullet.
- A feeling that daily quests are turning into real career assets.

### Retention Impact

V1 should improve post-sprint retention because users now see daily effort convert into useful application material. It also makes the monthly subscription easier to understand.

## V2: Interview Prep And Agent Search

### Features

- Role-specific interview prep.
- Interview story builder connected to proof and resume assets.
- Practice questions and AI feedback.
- Cloud agent search for resources, courses, certificates, projects, jobs, and networking opportunities.
- Default search mode focused on courses, certificates, and projects because these help users build real proof.
- User filters for fastest path, free/cheap path, best-quality path, jobs, networking, or specific resource types.
- Pasted job description or job link analysis.
- Specific-job goal mode where users can point OpenLARP at a dream job and receive a gap plan.
- No direct LinkedIn or job-board integration yet unless official, reliable integration paths are confirmed.

### Goals

- Help users prepare for interviews after their proof and resume story become stronger.
- Start the transition from daily app to tool-using career assistant.
- Let users find legitimate shortcuts: fast, real ways to build proof, credentials, projects, and readiness.
- Make OpenLARP more useful for users with urgent opportunities and users preparing months ahead.

### Assumptions Being Tested

- Users want interview prep after resume help because proof must become a spoken story.
- Agent search is more useful after OpenLARP knows the user's goals and proof history.
- Users want control over search priorities instead of one universal recommendation style.
- "Career hack" can mean the fastest legitimate path without encouraging deception.

### Engineering Complexity

High.

V2 needs cloud agent infrastructure, search and ranking, job-description analysis, resource evaluation, more expensive LLM workflows, and stronger cost controls. It also needs quality filters so recommended certificates and resources do not damage user trust.

### User Value

- Better interview answers.
- Clearer next steps for missing skills or credentials.
- Faster discovery of relevant courses, certificates, and projects.
- Support for both urgent job prep and long-term career preparation.

### Retention Impact

V2 should improve monthly retention because the product now helps with more scenarios: preparing for a target job, getting ready for interviews, finding proof-building resources, and staying on track over longer timelines.

## V3: Persistent Career Agent

### Features

- Long-term memory for goals, proof, quests, outcomes, constraints, preferences, and useful user context.
- Memory controls that let users view, edit, delete, or disable memory for sensitive chats.
- Persistent career plan that updates when the user changes goals or logs new outcomes.
- New diagnostic when users set a new goal, with the option to rebuild or adapt the current path.
- Weekly "Am I Cooked?" progress check tied to the user's active goal.
- Continuous recommendation updates for quests, resume/profile material, interview prep, resources, certificates, projects, and opportunities.
- Assistant available through chat as a helper, not the main app surface.
- Quest-first app navigation with chat placement still to be finalized.

### Goals

- Become the user's private career operating system.
- Make OpenLARP more valuable over time because it understands the user's history.
- Keep users engaged beyond the first 14-day sprint.
- Support both near-term job search and long-term preparation.

### Assumptions Being Tested

- Long-term memory makes OpenLARP harder to replace with a one-off ChatGPT conversation.
- Users trust the app with career memory if controls are clear.
- Weekly diagnostics remain motivating if they show progress, not just judgment.
- The chatbot is useful as support, but the app should still open to quests and progress.

### Engineering Complexity

High.

V3 needs durable memory, event history, privacy controls, recommendation pipelines, state migration, observability, and careful AI evaluation. It also needs product discipline so the app does not become a cluttered career toolbox.

### User Value

- Less repeated explanation.
- More personal quests and recommendations.
- Better recovery after missed days, rejections, or changed goals.
- A growing private record of proof, progress, and outcomes.

### Retention Impact

V3 should drive longer-term retention by making the product context-rich. Users should return not only for daily quests, but also for weekly progress checks, goal changes, interview prep, and new opportunities.

## V4: Proactive Autonomous Career Agent

### Features

- Proactive monitoring for user-approved opportunities, deadlines, courses, certificates, projects, events, and networking openings.
- Draft-for-approval behavior for outreach, follow-ups, application material, prep plans, and project plans.
- No external action without user approval.
- Permissioned integrations only when reliable and allowed.
- Direct job-platform integrations as a long-term goal, not an early dependency.
- Notification system for daily quests, deadlines, and opportunity alerts.
- Advanced filtering for speed, cost, quality, and relevance.
- Optional community or cohort features only if private usage and sharing data prove users want them.

### Goals

- Turn OpenLARP into a proactive career partner.
- Help users miss fewer relevant opportunities.
- Keep long-term progress alive even when users are busy.
- Build defensibility through user context, proof history, behavior data, and outcome learning.

### Assumptions Being Tested

- Users want proactive help if it is useful, controlled, and not spammy.
- Draft-for-approval creates leverage without crossing trust boundaries.
- Permissioned integrations are worth the privacy and engineering cost.
- Community should remain delayed unless it clearly improves accountability without harming privacy.

### Engineering Complexity

Very high.

V4 needs scheduled agents, integrations, permission management, notification ranking, audit logs, abuse prevention, safety rules, cost quotas, and incident response. It should not be built until earlier versions prove growth, retention, trust, and willingness to pay.

### User Value

- Timely reminders and opportunity alerts.
- Less missed career action.
- More help turning goals into real-world progress.
- A career agent that watches for useful next steps while still requiring user approval for external action.

### Retention Impact

V4 retention comes from timely usefulness, not nagging. The agent must send fewer, better alerts and remain easy to control.

## Launch Strategy

- Lead with "Am I Cooked?" content on TikTok and Instagram.
- Explain the actual product as Duolingo for careers or Duolingo for LinkedIn after the hook.
- Use funny, hopeful cooked cards as the first viral unit.
- Later use badges, streaks, and user outcome stories as social proof.
- Accept creator applications through the website.
- Prioritize creators who promote AI tools, AI study tools, AI productivity tools, or campus content.
- Ask creators for past AI promotion links, audience, rates, and contact email.
- Give accepted creators full beta access plus hook assets, talking points, and invite links.
- Pay creators case by case.
- Keep the public hook polished even if deeper beta features are still early.

## Business Model

- First 14-day sprint is free.
- After the free sprint, users convert into a monthly subscription.
- Standard price target is $29/month.
- Offer a student discount.
- The monthly subscription should unlock ongoing quests, agent help, more content, and advanced search as those features ship.

## Version Gate Summary

| Version | Build Only If |
|---|---|
| V0 | The iOS hook, waitlist, creator strategy, and daily quest loop are ready to test publicly. |
| V1 | V0 shows viral interest and enough quest activity to justify deeper resume/profile help. |
| V2 | V1 shows users value proof-linked career materials and need interview prep plus search. |
| V3 | V2 proves structured context improves recommendations and retention. |
| V4 | V3 proves users trust persistent agent behavior and want proactive support. |

OpenLARP can become a true career agent, but the first product must be a focused, viral, quest-first iOS app.
