# OpenLARP Agent Architecture Roadmap

## Architecture Thesis

OpenLARP should evolve from narrow AI-powered app flows into a persistent career agent. It should not begin as a generic chatbot, and it should not depend on human review.

The app should open like a daily quest product. Chat is agent support, not the center of the experience. The architecture should make the main action obvious: understand the user's goal, assign the next useful quest, check proof, update progress, and recommend what comes next.

## Level 0: Simple LLM Calls

### Capabilities

- Generate an "Am I Cooked?" diagnostic from a minimal profile and user goal.
- Generate the first daily quest.
- Estimate the user's urgency from available context, with user override.
- Produce a seven-day quest outline.
- Check submitted proof or self-report for relevance and usefulness.
- Summarize goal-readiness progress in plain language.
- Generate a funny but safe share-card summary.

### Architecture

- Native iOS app calls a backend API for AI tasks.
- Backend wraps direct LLM calls with prompt templates and output schemas.
- LLM output is used for diagnosis, quest generation, proof feedback, progress copy, and share-card text.
- User profile starts minimal and expands only when the app needs more context.
- Chat is not the main architecture surface; it is a helper entry point if the user asks questions or wants to adjust a goal.

### Required Infrastructure

- iOS app shell.
- Basic backend API.
- User authentication.
- Minimal user profile storage.
- Goal storage.
- Quest storage.
- Proof text, link, photo, and screenshot upload support.
- LLM API wrapper.
- Push notification setup.
- Basic analytics for growth, activation, proof activity, and conversion.
- Waitlist website and creator application form.

### Technical Risks

- AI diagnostics may feel random, harsh, or fake.
- Proof checks may overstate what the AI can verify.
- Minimal profiles may produce generic quests.
- Native iOS adds cost before retention is proven.
- Viral traffic may expose rough product areas quickly.
- Without human review, bad AI output can reach users directly.

### Cost Implications

Low to medium.

LLM usage is bounded to diagnostics, quest generation, proof checks, and progress summaries. The larger early cost is iOS development, image upload/storage, push notifications, and marketing traffic from creators.

## Level 1: Workflow System

### Capabilities

- Run repeatable goal setup, cooked diagnostic, quest, proof, streak, badge, and progress flows.
- Maintain a 14-day free sprint.
- Show Today quest and seven-day map.
- Accept proof and self-reports.
- Award XP from activity, proof, streaks, and major outcomes, with proof weighted more than passive activity.
- Support forgiving streaks through recovery quests or limited recovery mechanics.
- Let users log outcomes such as applied, interview, rejection, offer, or changed goal.
- Trigger a new diagnostic when users set a new goal.

### Architecture

- Deterministic workflow engine controls the core loop.
- LLM calls happen inside bounded workflow steps.
- Structured state tracks profile, goal, diagnostic, quest, proof, streak, XP, badge, outcome, and subscription state.
- AI can suggest the urgency and plan, but users can override.
- Share-card generation pulls only safe public fields.
- Memory controls allow users to keep sensitive chats out of long-term memory.

### Required Infrastructure

- Durable database for user state.
- Workflow orchestration or scheduled jobs.
- Quest assignment service.
- Proof quality-check service.
- XP, badge, and streak logic.
- Push notification service.
- Share-card generation.
- In-app purchase or subscription system.
- Student-discount support.
- Creator attribution or invite-link tracking.
- Analytics dashboard for growth, sprint completion, and subscription conversion.

### Technical Risks

- Workflow state can become messy if goals, quests, proof, and outcomes are not modeled cleanly.
- XP can reward empty behavior if proof is not weighted strongly enough.
- Strict streaks can cause churn, while overly forgiving streaks can feel meaningless.
- Share cards can accidentally expose sensitive information if not carefully designed.
- Subscription conversion may be weak if the first free sprint feels like the full product.
- Creator traffic can create spikes that stress backend and support processes.

### Cost Implications

Medium.

Costs include backend hosting, storage for proof images, AI calls for every active user, push notification infrastructure, subscription tooling, and analytics. Cost controls should start early because $29/month must support AI usage and app operations.

## Level 2: Tool-Using Assistant

### Capabilities

- Turn completed proof into resume and LinkedIn improvements.
- Compare pasted job descriptions or job links against the user's proof and assets.
- Generate interview practice questions tied to a role or job posting.
- Build interview stories from completed quests and proof.
- Search for courses, certificates, projects, jobs, and networking opportunities.
- Default search to courses, certificates, and projects because those create real proof.
- Let users filter search by fastest path, free/cheap path, best-quality path, jobs, networking, or specific resource type.
- Draft materials for user approval.

### Architecture

- Assistant operates through a controlled internal tool layer.
- Tools expose narrow actions such as reading goals, reading proof, comparing job text, creating resume suggestions, creating interview questions, searching resources, and drafting next quests.
- Retrieval pulls only relevant user context.
- Direct LinkedIn or job-board integrations are deferred until official and reliable integration paths are confirmed.
- Early job input uses pasted text or links.
- Chat can call these tools, but the app still remains quest-first.

### Required Infrastructure

- Tool registry and permission model.
- Asset store for proof, resume material, certificates, badges, interview stories, and outcomes.
- Retrieval layer.
- Search connectors or search API.
- Resource and certificate quality filters.
- Job-description parser.
- Resume/profile suggestion pipeline.
- Interview-prep pipeline.
- Audit logs for tool calls.
- Cost monitoring by tool and feature.

### Technical Risks

- Search results can be noisy, low quality, outdated, or irrelevant.
- Certificate recommendations can damage trust if they are not respected by employers.
- Job links may be hard to parse reliably across platforms.
- The assistant may produce strong-sounding resume language that overstates the facts.
- Tool traces make debugging recommendations harder.
- Users may expect direct job-platform integrations before the product is ready.

### Cost Implications

High.

Costs rise because tool-using flows require retrieval, multiple model calls, search APIs, ranking, and storage. Expensive agent search should be introduced only after V0/V1 prove active users and subscription potential.

## Level 3: Persistent Career Agent

### Capabilities

- Maintain long-term memory for goals, useful user context, proof, quests, outcomes, constraints, and preferences.
- Forget low-value or sensitive details when they are not needed.
- Let users disable memory for specific chats so those conversations are not saved.
- Update recommendations when goals change, outcomes are logged, or proof improves.
- Run weekly "Am I Cooked?" progress checks.
- Detect repeated missed days, rejections, stale goals, or weak proof.
- Recommend next quests, resume changes, interview prep, and resources from the user's history.
- Challenge unrealistic goals in a direct but helpful way.

### Architecture

- Persistent agent service runs on structured career memory and event history.
- Career graph connects goals, gaps, quests, proof, assets, outcomes, badges, resources, and recommendations.
- Background jobs update recommendations on a controlled schedule.
- Ranking layer decides which recommendations are worth showing.
- Notification layer stays separate from agent reasoning so alerts can be throttled.
- User-facing explanations show why the agent recommends an action.
- Memory controls are part of the product architecture, not hidden settings.

### Required Infrastructure

- Long-term memory model.
- Career proof graph.
- Event stream for quests, proof, outcomes, chat interactions, and subscription state.
- Background recommendation jobs.
- Recommendation ranking.
- Privacy controls for view, edit, delete, and memory-off behavior.
- Data export and deletion.
- Observability for agent runs.
- Offline evaluation using user behavior and outcomes.
- Cost quotas for background work.

### Technical Risks

- Persistent memory may store more sensitive career data than needed.
- Users may feel watched if memory and notifications are not clearly controlled.
- Bad recommendations become more damaging when repeated over time.
- Weekly cooked checks can become vanity scoring if not tied to real progress.
- The agent can optimize for engagement instead of stronger candidacy.
- Data model mistakes become expensive to migrate after users build history.

### Cost Implications

High.

Costs include storage, embeddings or retrieval indexes, background jobs, ranking, evaluation, observability, and scheduled AI usage. This level needs clear per-user budgets and subscription economics.

## Level 4: Proactive Autonomous Career Agent

### Capabilities

- Monitor approved sources for opportunities, deadlines, courses, certificates, projects, events, and networking openings.
- Send proactive alerts for daily quests, deadlines, and high-value opportunities.
- Draft outreach, follow-ups, application material, prep plans, and project plans for approval.
- Coordinate multi-week campaigns for internships, entry-level jobs, interviews, or longer-term prep.
- Use permissioned integrations only after explicit user approval.
- Act externally only after user approval.
- Learn from ignored, accepted, and completed recommendations.

### Architecture

- Autonomous agent scheduler runs monitoring and planning cycles.
- Permissioned integrations feed events into the career graph.
- Policy engine controls what the agent can read, draft, notify, or ask approval for.
- Approval gates are required before external action.
- Notification ranking chooses a small number of high-value alerts.
- Audit trail shows what the agent considered, recommended, drafted, or sent for approval.
- Safety layer enforces hard bans and non-deception rules.

### Required Infrastructure

- Agent scheduler.
- Integration permissions and OAuth flows where needed.
- Calendar, email, job board, learning, and networking connectors where reliable and allowed.
- Notification ranking and throttling.
- User approval workflow.
- Audit logs.
- Abuse and spam prevention.
- Privacy, deletion, and data-access controls.
- Cost quotas and runaway-agent prevention.
- Incident response process for bad recommendations or privacy failures.

### Technical Risks

- Proactive behavior can feel like spam.
- Integrations create privacy, security, and platform-policy risk.
- External platforms may block or limit automation.
- Autonomous drafting can cross ethical lines without strong controls.
- Too many opportunity alerts can overwhelm users.
- Background agent costs can grow invisibly.
- A single bad proactive recommendation can damage trust.

### Cost Implications

Very high.

This level requires ongoing background computation, external API usage, integration maintenance, monitoring, notification infrastructure, security work, and support. It should ship only after users clearly trust the persistent agent and pay for the ongoing value.

## Safety And Product Rules

- OpenLARP may package real experience aggressively.
- Users can choose conservative, balanced, aggressive, or AI-decided tone.
- The app must not invent substantial facts.
- Hard bans: no fake employers, schools, certificates, job titles, dates, projects, or ownership claims.
- Skill-style badges should be treated as progress and motivation, not official credentials.
- Agent actions are draft-for-approval by default.
- No external sending, publishing, applying, or messaging without user approval.
- Private by default; sharing is always user-chosen.

## Product-To-Architecture Mapping

| Product Version | Agent Level |
|---|---|
| V0 iOS Career Level-Up Beta | Level 0 and early Level 1 |
| V1 Quest-Linked Resume And Profile Help | Level 1 |
| V2 Interview Prep And Agent Search | Level 2 |
| V3 Persistent Career Agent | Level 3 |
| V4 Proactive Autonomous Career Agent | Level 4 |

The architecture should protect the core product shape: OpenLARP is a quest-first career agent, not a chatbot with points.
