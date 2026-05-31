# OpenLARP Founder Decisions

## Locked Decisions

- OpenLARP starts as an iOS-first daily career action app.
- The product should feel like "Duolingo for LinkedIn" or "Duolingo for careers."
- The long-term vision remains a persistent AI career agent.
- V0 is not a manual concierge product.
- V0 is not a generic AI career chatbot.
- V0 is native iOS plus a simple web waitlist.
- Android is ignored until there is meaningful traction.
- The website should explain the product, show an app preview, collect waitlist signups, and collect creator applications.
- The first user segment is college students and new grads, while still allowing other users.
- The first goal category is internships and entry-level jobs.
- The main acquisition hook is "Am I Cooked?" on TikTok and Instagram.
- After the hook, the product should explain itself as a serious daily career leveling app.
- The first app experience starts with goal setup.
- The core loop is goal -> cooked diagnostic -> daily quest -> proof/self-report -> XP/streak/progress -> next quest.
- V0 progress emphasizes goal readiness.
- V0 includes Today quest and a seven-day map.
- V0 accepts text, links, photos, and screenshots as proof.
- V0 uses AI for diagnostics, quests, proof quality checks, and progress summaries.
- There is no human review in the product flow.
- Users get one main quest with a limited swap option.
- Quest difficulty adapts over time.
- Streaks should be forgiving, with recovery quests or recovery mechanics.
- Badges are mainly for streaks, progress, proof milestones, and outcomes.
- Badges should not pretend to be official credentials.
- The product is private by default.
- Users can choose to share cooked cards, streaks, badges, and outcomes.
- V0 has no community or social feed.
- The first 14-day sprint is free.
- After the free sprint, users convert into a monthly subscription.
- The target standard subscription price is $29/month.
- There should be a student discount.
- The first-month priority is viral growth, then subscription conversion.
- The first validation window is one month.

## Product Rules

- "Career hack" means the fastest legitimate path to real proof, confidence, and job readiness.
- OpenLARP can package real experience aggressively.
- Users can choose conservative, balanced, aggressive, or AI-decided wording.
- The app must not invent substantial facts.
- Hard bans: no fake employers, schools, certificates, job titles, dates, projects, or ownership claims.
- No auto-apply in early versions.
- No live interview copilot.
- Agent behavior is draft-for-approval.
- No external sending, publishing, applying, or messaging without user approval.
- Memory-off chats should not be saved to long-term memory.
- Direct LinkedIn or job-board integrations are long-term only and should wait for reliable official paths.

## Roadmap Decisions

- V0: iOS career level-up beta with goal setup, cooked diagnostic, Today quest, seven-day map, proof/self-report, AI proof check, XP, streaks, badges, progress, push notifications, share cards, waitlist, and creator application.
- V1: Quest-linked resume and LinkedIn help based on real proof.
- V2: Interview prep and cloud agent search.
- V2 search defaults to courses, certificates, and projects.
- V2 search lets users filter by fastest, free/cheap, best-quality, jobs, networking, or resource type.
- V3: Persistent career agent with long-term memory, weekly progress checks, and adaptive recommendations.
- V4: Proactive autonomous career agent with approved monitoring, alerts, and draft-for-approval workflows.

## Launch Decisions

- Use TikTok and Instagram as the main early channels.
- Lead with "Am I Cooked?" content.
- Use cooked cards as the first viral unit.
- Later social proof should include streaks, badges, and user stories.
- Use AI-tool creators, AI study/productivity creators, and campus creators.
- Creators apply through the website.
- Creator applications should ask for past AI promotion links, audience, rates, and contact email.
- Accepted creators receive beta access, hook assets, talking points, and invite links.
- Creator payment is case by case.
- The hook experience must feel polished before broad creator promotion.

## Open Questions

- Should chat be a dedicated tab, a floating agent button, or both?
- Should OpenLARP have a mascot?
- What is the exact student discount price?
- What exact first-month growth numbers define success?
- What does the cooked-card design look like?
- What are the first badge names and badge rules?
- How much of the seven-day map should be locked, previewed, or editable?
- What exact push notification cadence is useful without becoming annoying?

## Technical Planning Defaults

- Use minimal profile first, then ask for more information only when needed.
- Let AI infer urgency, but allow the user to override it.
- Let users paste job descriptions or job links before building integrations.
- Store goals, quests, proof, streaks, XP, badges, outcomes, and subscription state from the beginning.
- Keep proof storage simple in V0: text, links, photos, and screenshots.
- Keep resume help out of V0.
- Keep interview prep out of V0.
- Keep cloud agent search out of V0.
- Keep community out of V0.
