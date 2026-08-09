# Wondering Product Audit and OpenLARP Translation

## Purpose

This document is a durable product reference for OpenLARP. It records the Wondering product as directly observed in a logged-in account, separates verified behavior from inference, and translates the strongest ideas into the OpenLARP thesis: a focused, AI-personalized system that helps a user become ready for a real job through daily action, honest evidence, practice, and visible progress.

The goal is not to clone Wondering. The goal is to understand its complete product system well enough to make deliberate OpenLARP decisions.

## Research Scope and Evidence

- Direct account audit performed on August 9, 2026.
- Wondering web product version shown in Settings: `0.23.10`.
- The audit covered onboarding, plan selection, course discovery, custom course creation, adaptive AI personalization, course generation, lesson maps, lesson pages, contextual definitions, AI tutoring, notes, saved pages, knowledge cards, practice, XP, streaks, friend streaks, analytics, podcasts, profiles, course management, source imports, personalization memory, account settings, privacy, and the free/Pro paywall.
- A sample course was created: **Landing Your First APM Role**.
- One lesson was completed, several practice questions were attempted, one note and one page were saved, and progress/reward flows were observed.
- No subscription was purchased, no private source material was uploaded, no friend was contacted, and no account or course was deleted.
- Screenshots from this audit are stored locally in the Codex visualization artifact folder and are not committed to the repository.

## Executive Conclusion

Wondering is not merely an AI course generator. Its actual product is a layered learning loop:

1. Learn enough about the user to personalize the experience.
2. Let the user state an open-ended learning goal.
3. Ask adaptive questions before generating the course.
4. Convert the goal into a visible learning map.
5. Deliver short, structured lesson pages.
6. Place AI help inside the lesson rather than making chat the whole product.
7. Turn lesson content into practices, notes, saved pages, knowledge cards, podcasts, and review sessions.
8. Reward completion with XP, streaks, collections, reports, and social accountability.
9. Monetize limits, memory, breadth, and speed rather than the first moment of value.

The equivalent OpenLARP opportunity is:

> Wondering helps a user learn anything. OpenLARP should help a user become ready for a real job.

The right translation is not “AI courses about careers.” It is an AI-generated, evidence-backed career journey in which every lesson becomes a real career action, every practice improves a real capability, and every reward represents credible progress.

## What AI Models Does Wondering Use?

### Verified

Wondering's public privacy policy does **not** name the model or provider used for its general course generation, lesson generation, practice generation, contextual explanations, podcasts, or AI chat.

The privacy policy does verify the following:

- Selected Gmail content for the optional Gmail-summary feature is sent to **Google Vertex AI**.
- AI service providers receive submitted learning materials to generate courses, practices, and learning content.
- Wondering uses **Supabase** for cloud infrastructure.
- Wondering uses **PostHog** for product analytics.
- Wondering uses the **FSRS spaced-repetition algorithm** for personalized review.
- Subscription infrastructure can involve **Apple, RevenueCat, and Stripe**.

### Not Verified

There is no reliable product or policy evidence identifying the general-purpose model as Gemini, GPT, Claude, or another model. The generated writing style is not sufficient evidence. Model names must remain “unknown” until Wondering publishes them or they are verified through an authoritative disclosure.

### What the product behavior suggests

This is a behavioral inference, not a provider claim. Wondering appears to use several AI jobs or prompt modes rather than one undifferentiated chatbot:

- onboarding recommendation generation;
- adaptive course-intake questioning;
- course title, objective, outline, and cover generation;
- lesson content generation;
- contextual term explanations;
- lesson-grounded tutoring;
- suggested follow-up questions;
- practice generation and grading;
- knowledge-card extraction;
- “Magic Insights” from saved content and chat;
- podcast generation;
- personalization-fact extraction.

That job-oriented separation is more important to OpenLARP than the specific base model. OpenLARP can change providers later if its contracts, evaluation, fallbacks, and user state are designed correctly.

## Product Positioning

Wondering's repeated promise is effectively:

> Tell us what you want to learn and we will build a personalized learning journey around you.

Its product language emphasizes:

- learning anything;
- personalization;
- short lessons;
- progress without overwhelm;
- habit formation;
- memory and review;
- gentle encouragement rather than academic pressure.

OpenLARP's analogous promise should be more outcome-specific:

> Tell us the job you want. OpenLARP will show how ready you are, build the path, give you one meaningful action at a time, help you prove the work, and prepare you to earn the opportunity honestly.

## End-to-End Wondering Journey

### 1. Onboarding welcome

The first screen promises “5 short questions” and a learning journey designed for the user. The flow uses a single strong CTA, a visible progress bar, generous empty space, and playful character art.

### 2. Work-type personalization

The user chooses from:

- Product Manager
- Business/Management
- Designer/Creative
- Student
- Developer/Engineer
- Research/Academic
- Finance/Investment
- Other

Wondering states that it will use examples relevant to the user's role and expertise and that the setting can be changed later.

### 3. Topic interests

Observed options included:

- AI
- Business
- Psychology
- Science
- Philosophy
- Economics
- History
- Investing
- Design
- Self-Improvement
- Strategy
- Learning
- Longevity
- Decision Making
- Software Engineering
- custom topics

The app then explains that it will recommend relevant courses and that the user can still make a course about any topic.

### 4. Learning preferences

Observed options included:

- bite-sized lessons;
- visual explanations;
- practice exercises;
- clear learning path;
- regular review;
- real-world examples;
- hands-on projects;
- personalized difficulty;
- custom preference.

Wondering explicitly discloses capability status. In the audited flow it said that bite-sized lessons, practices, paths, real-world examples, personalized difficulty, visual explanations, and regular review were supported, while hands-on projects were still being developed.

This is an unusually honest onboarding pattern: ask the user what they want, then say what the product can and cannot currently provide.

### 5. Learning goals

Observed options included:

- make better use of time;
- build new skills;
- boost a career;
- understand complex topics;
- explore new topics;
- learn for fun;
- remember important learning;
- custom goal.

### 6. Daily commitment

Observed commitments were:

- 5 minutes — “A toilet break”;
- 10 minutes — “A bus ride”;
- 15 minutes — “A lunch break”;
- more than 20 minutes — “I'm SERIOUS.”

The app translates the chosen daily time into a concrete monthly learning claim and a first-week lesson count. This reframes a small daily commitment as a larger identity-building result.

### 7. Free versus Pro choice

Before entering the product, the user chooses between:

- Wondering Pro — faster progress, no limits;
- Learn for free — core learning features with limits.

The free path is explicit and usable rather than hidden behind a trial wall.

### 8. Personalized home/create surface

The main surface asks “What do you want to learn?” and offers:

- an open text prompt;
- source-material import;
- voice input;
- curated personalized recommendations;
- a full course library.

Recommendations include a short explanation of why each course matches the user's interests or goals.

### 9. Course creation decision

After submitting a topic, Wondering asks whether the user wants to:

- personalize the course first; or
- create it directly.

It clearly states that personalization can be changed later in course settings.

### 10. Adaptive AI course interview

For the sample goal, Wondering dynamically asked:

- current professional or academic background;
- target product-management industry;
- the desired role outcome.

It offered generated answer chips plus a free-text/voice/source-material response area. Questions changed based on previous answers.

### 11. Editable course brief

Before generation, Wondering produced an editable brief containing:

- course name;
- learning goal;
- background knowledge.

The user could edit fields directly or ask the AI to change the plan conversationally before confirming.

### 12. Course generation

Generation has a dedicated progress screen with:

- current generation phase;
- course name;
- playful animation;
- expectation-setting copy.

The generated result included a title, description, visual cover, achievement bullets, learning sections, lessons, advanced lessons, and section reviews.

### 13. Learning map

The sample course contained three sections and nine standard lessons:

1. Product Sense
   - User Empathy
   - Feature Prioritization
   - Product Sense advanced lesson
   - section review with two sessions
2. Execution Skills
   - Success Metrics
   - Problem Solving
   - Execution Skills advanced lesson
   - section review with two sessions
3. Interview Strategy
   - Portfolio Building
   - Case Interviews
   - Interview Strategy advanced lesson
   - section review with two sessions

The course surface also exposed:

- Learning Map
- Podcast
- Quick Exercise
- View Saved
- Share
- Settings
- recommendations for what to learn next
- course-level helpful/not-helpful feedback

### 14. Lesson experience

The observed lesson used six pages:

1. lesson question/title and topic;
2. explanation plus a three-step interactive block;
3. additional conceptual explanation plus steps;
4. a structured table;
5. interview application plus a contextual definition;
6. an applied scenario recap with per-step explanation controls.

Common lesson tools included:

- visible page progress;
- Back and Next controls;
- Notes;
- Save Page;
- Check My Understanding;
- worked-well/needs-work feedback;
- Ask a Question;
- clickable definitions;
- contextual “Explain” actions.

### 15. Contextual AI tutoring

Clicking a term opened a short definition. Clicking “Explain” opened an AI tutor grounded in that term and lesson context.

Observed chat capabilities included:

- lesson-grounded explanation;
- analogies matched to the inferred user background;
- suggested follow-up questions;
- streaming answers;
- conversation history;
- save conversation;
- new chat;
- save individual response;
- create a lesson from a response;
- response feedback;
- voice input;
- chat settings.

There is also a global learning assistant available throughout the application. It offers:

- questions about lessons;
- product feedback;
- past conversations;
- voice input;
- Pro-gated AI memory.

The strongest product decision is contextual placement: AI is available exactly when the user encounters confusion. Chat supports the structured journey; it does not replace the journey.

### 16. Notes and saved pages

Users can create page-linked notes. Saved pages are collected in a searchable, filterable course library.

The saved-items surface can contain:

- notes;
- lesson pages;
- saved practices;
- knowledge cards;
- dates and lesson associations.

Wondering says saved pages will be summarized and used for future reminders.

### 17. Lesson completion review

Before the lesson is fully complete, Wondering presents:

- the user's notes;
- Magic Insights;
- extracted knowledge cards;
- lesson feedback.

Magic Insights are described as AI-generated notes based on chat and saved content. The feature unlocks after the first completed lesson.

### 18. Knowledge cards

The first lesson produced cards for:

- Product Empathy;
- User Advocacy;
- User Pain Points;
- User Personas.

Each card included a definition and example. Cards were animated into a collection after completion. The saved library also exposed cards from later course material, including concepts such as RICE, Reach, Impact, Confidence, and Effort.

### 19. Practice system

Observed practice types included:

- two-option fill-in-the-blank;
- multiple choice;
- drag-to-order sequencing.

Practice feedback included:

- correct/incorrect state;
- answer comparison;
- save practice;
- worked-well/needs-work feedback;
- Discuss with the AI tutor;
- Continue.

Practice can be launched:

- after a lesson;
- from the course's Quick Exercise control;
- from the course-library Review action.

An unfinished practice is resumed from those shortcuts. The exit dialog can let a user keep learning, mark a lesson complete and return later, or quit.

### 20. Check My Understanding

The per-page knowledge-check feature is initially locked. Completing the first lesson unlocks it. Wondering explains the unlock after the lesson, making progressive disclosure part of the reward sequence.

### 21. Reward sequence

The observed reward flow included:

- calculated score/progress;
- a one-day streak screen;
- weekly streak calendar;
- 10 XP;
- four collected knowledge cards;
- invitation to continue or dive deeper;
- an iOS download interstitial for web users.

### 22. Streak system

Observed streak features included:

- daily streak count;
- day-of-week history;
- two starting streak freezes;
- explanation that freezes cover a missed day after the user practices again;
- friend streaks;
- up to three friend-streak slots;
- friend discovery and follow relationships.

### 23. XP

XP appears beside streaks in the persistent sidebar and in reports. The completed sample lesson earned 10 XP. XP is not the only progress metric; it is paired with lessons, practices, time, cards, notes, and course progress.

### 24. Analytics and reports

The weekly report included:

- lessons completed;
- questions practiced;
- learning time;
- XP earned;
- cards collected;
- active days;
- a seven-day activity breakdown;
- best day of the week;
- courses worked on.

Detailed learning statistics included today's and lifetime values for:

- lessons;
- questions;
- learning time;
- streak;
- XP;
- active learning days.

Course statistics included:

- Done, In Progress, and Not Started filters;
- last completion date;
- time spent;
- saved practices;
- saved pages;
- notes;
- knowledge cards.

### 25. Podcasts

Podcast mode was marked Beta. A 3:20 episode had been generated for the completed lesson.

Observed podcast capabilities included:

- play/pause;
- 15-second skip backward and forward;
- playback speed;
- timeline/remaining duration;
- episode feedback;
- persistent mini-player after closing the full panel;
- per-lesson episodes;
- generation for unlocked lessons;
- locked future episodes;
- custom instructions for host focus and speaking style.

### 26. Curated course library

The full catalog included:

- search by title, author, or tag;
- personalized “For You” filtering;
- broad topical filters;
- category sections;
- Most Popular and Top Pick badges;
- original/technical courses and courses based on well-known books or talks;
- cover illustrations, descriptions, and authors.

Observed topical categories included AI, Business, Self-Improvement, Learning, philosophy, analytics, architecture, art, computer science, creativity, design, economics, finance, leadership, product management, programming, psychology, science, software engineering, startups, strategy, systems thinking, UX, writing, and others.

### 27. Source-material import

Course creation can use:

- pasted URL;
- pasted text;
- PDF up to 50 MB;
- up to 10 images at 10 MB each;
- voice input.

The privacy policy also describes an optional Gmail context feature in which a user can search Gmail and select messages for a learning summary. The policy says the access is read-only, selected message bodies are not persisted, and selected content is sent only to Google Vertex AI for the requested summary. This feature was disclosed in policy but was not visible in the audited settings account.

### 28. Course management

The Courses page is a table with:

- course name;
- status;
- completed lesson count;
- total lesson count;
- creation date;
- status and count filters;
- View Saved;
- Review;
- edit course name;
- delete course.

### 29. Course settings

Per-course settings included:

- lesson-depth Auto mode tied to the daily goal;
- Quick lessons, about three minutes;
- Standard lessons, about five minutes;
- Deep lessons, about ten minutes;
- personalization on/off;
- editable learning goal;
- editable background knowledge;
- custom lesson/practice instructions;
- AI-assisted instruction setup;
- practice-after-lessons toggle;
- Intense Mode for more practices.

### 30. Profile and social layer

The profile included:

- display name;
- optional username;
- optional bio up to 160 characters;
- days/streak;
- XP;
- followers;
- following;
- streak freezes;
- add friends;
- share profile;
- public/private account mode;
- public visibility controls for courses;
- friend streaks;
- progress reports;
- visible learning courses.

The account defaults observed in the audit were private, requiring follow approval before others can see learning activity.

### 31. Personalization memory

“Facts About You” is Wondering's explicit memory layer. Users can:

- add a fact manually;
- extract facts from pasted text;
- find candidate facts from onboarding preferences and course personalization;
- review and select facts before adding them.

The interface explains that facts can shape lessons, practices, and conversations.

### 32. Account settings

Observed account settings included:

- Facts About You;
- content language;
- private/public account mode;
- subscription plan and upgrade;
- Discord community;
- app version;
- account deletion;
- sign out.

### 33. iOS and notifications

The product promotes the iOS app after a completed web lesson and says the app provides on-the-go learning plus gentle streak reminders. The privacy policy says the app can use push notifications and local device storage for offline functionality and performance.

## Monetization

### Free plan

Verified free value includes:

- personalized course creation;
- at least one complete course/lesson flow;
- limited lessons;
- limited AI chats;
- limited podcast generation;
- normal profile, progress, note, practice, and streak foundations.

### Pro features shown in the paywall

- personalized courses;
- unlimited lessons;
- unlimited AI chats;
- up to 15 courses per month;
- jump ahead in courses;
- unlimited podcast episodes;
- AI memory messaging elsewhere in the product.

### Pricing observed on August 9, 2026

- Annual: 7-day free trial, then `$99.99/year`, displayed as `$8.33/month`, with “Save 44%.”
- Monthly: `$14.99/month`.

Pricing is time-sensitive and should be reverified before being used in a market or pricing decision.

## Privacy and Technical Product Architecture

According to Wondering's privacy policy updated July 25, 2026:

- authentication supports Google and Apple;
- optional Gmail connection is separate from Google sign-in;
- Gmail access is read-only;
- selected Gmail content is sent to Google Vertex AI for requested summaries;
- learning data includes courses, materials, practices, answers, accuracy, review history, streaks, and analytics;
- chats and feedback are stored as user-generated content;
- PostHog is used for analytics;
- FSRS is used for spaced repetition;
- Supabase is named as cloud infrastructure;
- Apple, RevenueCat, and Stripe can participate in subscriptions;
- data is stored in the United States;
- account data is generally deleted within 30 days after deletion, while billing records may be retained longer;
- the service is not intended for children under 13;
- public project sharing exposes project content by link but not name, email, or progress data;
- the iOS app and web app use the same backend services.

Official sources:

- [Wondering](https://wondering.app/)
- [Wondering Privacy Policy](https://wondering.app/privacy)
- [Wondering Terms](https://wondering.app/terms)

## Visual and Interaction System

### Strong patterns

- warm cream background rather than clinical white;
- a restrained black, gray, blue, green, and orange palette;
- playful rotating character illustrations;
- one primary blue CTA at the bottom of focused flows;
- bold, compact display type for actions and headings;
- wide cards with soft borders and subtle shadows;
- generous spacing and low information density during onboarding;
- more information-dense panels only after the user has context;
- visual progress dots/bars at the top of lessons and onboarding;
- celebratory full-screen transitions after meaningful actions;
- progressive feature unlocks rather than exposing every tool immediately;
- clear loading states for AI generation;
- immediate access to help through the floating assistant.

### Product personality

Wondering combines serious learning structure with deliberately odd, friendly characters and lightly irreverent copy. The characters function as emotional pacing: they appear during loading, celebration, help, and commitment moments.

### OpenLARP implication

OpenLARP should not copy the characters or visual identity. It should adopt the principle of emotional pacing. “Cooked” reactions, quest completion, proof approval, streak recovery, readiness changes, and offers can each have a distinct but coherent emotional treatment.

## Observed Quality and UX Risks

### 1. Incorrect user-background inference

The most serious issue occurred in personalization memory.

During the work-type onboarding, Developer/Engineer was temporarily selected and then replaced with Student. Later, “Find Facts” proposed “Works as a Developer/Engineer.” The generated course also shifted from the selected recent-graduate background to language about transitioning from engineering.

This suggests stale interaction state or generated assumptions can be treated as user truth.

OpenLARP must never turn an AI inference into a durable career fact without:

- provenance;
- confidence;
- explicit user confirmation;
- editing and deletion;
- separation between user-provided fact and model hypothesis.

This is especially important because OpenLARP facts may affect cooked diagnostics, readiness scores, quests, resume claims, and interview stories.

### 2. Course-generation contradiction

The editable course brief correctly described the user as a recent graduate/student, but the final generated overview referred to transitioning from engineering. The course title also changed during generation.

OpenLARP needs a post-generation validator that checks generated output against confirmed profile facts and hard constraints.

### 3. Selection semantics

Multi-select options were visually selected with blue borders, but the accessibility tree often exposed only the most recently focused item as active. Selected state was not consistently communicated semantically.

OpenLARP should use real toggle semantics, checked state, clear labels, and VoiceOver verification.

### 4. Unlabeled controls

At least one important send/continue control in the adaptive course interview had no accessible name.

### 5. Notes-panel behavior

The Notes panel's Close action did not reliably close the panel during the audit. Repeated interaction also produced unintended empty notes. The Notes toggle itself closed the panel successfully.

### 6. Raw interactive markup leak

The saved-page view displayed raw lesson markup beginning with `{{interactive:lesson-stepper ...}}` instead of rendering or sanitizing the interactive component.

OpenLARP needs a stable, versioned content schema and safe renderer for generated structured content. Raw model markup must never leak into user-facing proof, reports, or saved artifacts.

### 7. Loading-state flicker

Several views temporarily reported zero progress, empty content, disabled settings, or failure text before resolving to the correct state. The app recovered, but the intermediate state could undermine trust.

### 8. Content depth and repetition

The sample lesson was coherent but several pages followed the same “three paragraphs plus three steps” structure. Without strong source grounding or applied work, AI-generated lessons can feel templated.

### 9. Generic business claims

Some lesson text connected empathy to engagement or metrics without evidence or source citation. OpenLARP should distinguish coaching heuristics from verified labor-market facts, employer requirements, or user evidence.

### 10. Hidden content in the accessibility tree

The practice DOM exposed correct/incorrect feedback before the user submitted an answer. Even if visually hidden, this may create accessibility confusion and could expose answers to assistive technologies.

### 11. Dense desktop overlays

Saved-items, catalog, podcast, and settings panels are capable but become large modal layers over an already complex page. Native iOS design should use clear navigation destinations or sheets with intentional hierarchy rather than copying desktop overlays.

### 12. Ambiguous progress precision

XP and counts are concrete, but generated career readiness cannot be treated like an objectively measured learning answer. OpenLARP should avoid importing the apparent certainty of educational scoring into inherently uncertain job-market evaluation.

## What OpenLARP Should Adopt, Adapt, and Avoid

### Adopt

- open-ended goal input as the primary creation action;
- a short, high-empathy onboarding flow;
- adaptive follow-up questions generated from the user's target;
- editable AI brief before creating the journey;
- visible map with sections, milestones, and reviews;
- short daily units;
- contextual AI help inside the current task;
- user notes, saved evidence, and durable extracted cards;
- varied practices;
- daily commitment translated into an achievable path;
- progress reports that measure multiple meaningful behaviors;
- forgiving streaks and recovery mechanics;
- progressive feature unlocks;
- explicit user-editable personalization memory;
- clear loading, fallback, and retry states;
- free first value before the paywall.

### Adapt

| Wondering concept | OpenLARP version |
|---|---|
| What do you want to learn? | What job, internship, promotion, or career outcome do you want? |
| Personalized course | Personalized career mission |
| Course sections | Readiness gaps or mission chapters |
| Lesson | Career quest briefing or skill drill |
| Practice question | Application, networking, interview, targeting, or proof exercise |
| Knowledge card | Career evidence card, skill card, interview story, or reusable insight |
| Saved page | Saved advice, job requirement, proof receipt, or career asset |
| Notes | Reflections, draft bullets, story fragments, and follow-ups |
| Learning goal | Target role and desired outcome |
| Background knowledge | Confirmed profile, existing skills, constraints, and proof |
| Check My Understanding | Check My Readiness or Practice This |
| Podcast | Optional audio briefing for a commute or walk |
| Weekly learning report | Weekly career level-up report |
| XP | Momentum score, always secondary to real proof |
| Course completion | Reduced readiness gap and completed evidence |
| Friend streak | Optional accountability partner, not a public feed |
| Facts About You | Career memory with source, confidence, date, and user confirmation |

### Avoid

- generic AI chat as the main product;
- automatic inference becoming a durable user fact;
- large libraries before the core goal loop is excellent;
- rewarding app activity that does not improve a real career outcome;
- fake precision in cooked/readiness scoring;
- public-by-default career activity;
- social feeds;
- uncited employer or labor-market claims;
- AI-generated resume facts, employers, education, credentials, dates, ownership, or results;
- paywalling the first credible diagnosis or first useful daily action;
- building podcasts, community, or friend systems before the core evidence loop works.

## The “Wondering for Jobs” Product System

### North-star flow

1. **Name the outcome**
   - “Get an entry-level product role.”
   - “Land a summer software internship.”
   - “Move from marketing into product design.”
2. **Understand the user**
   - current stage;
   - existing experience and proof;
   - time available;
   - constraints;
   - confidence;
   - application timeline.
3. **Run the Cooked evaluation**
   - blunt but humane result;
   - confirmed facts versus unknowns;
   - main readiness gaps;
   - target and backup paths;
   - no fake percentage certainty.
4. **Review the mission brief**
   - target;
   - goal;
   - current state;
   - constraints;
   - ethical guardrails;
   - first milestone.
5. **Generate the map**
   - Target Clarity;
   - Role Fit;
   - Skill Proof;
   - Experience Proof;
   - Resume/LinkedIn Story;
   - Network;
   - Interview Readiness;
   - Application Execution.
6. **Do today's quest**
   - one 10–30 minute action;
   - why it matters;
   - clear definition of done;
   - optional AI help;
   - proof submission.
7. **Evaluate evidence**
   - complete, incomplete, or needs strengthening;
   - feedback tied to the actual artifact;
   - user override and appeal path;
   - no invented claims.
8. **Create durable career assets**
   - proof receipt;
   - skill/evidence card;
   - resume bullet candidate;
   - LinkedIn talking point;
   - interview story fragment;
   - follow-up quest.
9. **Reward real progress**
   - XP and streak;
   - readiness-gap movement;
   - visible evidence count;
   - weekly report;
   - recovery if a day is missed.
10. **Prepare for the opportunity**
    - job-description analysis;
    - targeted gap sprint;
    - application readiness;
    - interview practice;
    - outcome log.

## Proposed Complete Feature Architecture

### A. Goal and identity

- target outcome creation;
- target role/field selection;
- current stage;
- deadline and urgency;
- primary and backup targets;
- time commitment;
- constraints;
- private career-memory controls.

### B. Cooked evaluation

- structured intake;
- evidence-aware evaluation;
- main gap;
- risk explanation;
- strengths;
- missing information;
- recommendation confidence;
- target alternatives;
- first mission;
- shareable private-safe result card.

### C. Career map

- readiness chapters;
- daily quests;
- milestones;
- locked/unlocked sequencing;
- visible future direction;
- section reviews;
- goal switching and archived missions.

### D. Quest engine

- one primary daily quest;
- difficulty/depth settings;
- expected time;
- why it matters;
- examples;
- contextual AI help;
- skip and recovery;
- adaptive next quest;
- generated quests constrained by templates and safety rules.

### E. Evidence and proof

- text;
- link;
- screenshot/photo;
- file later;
- reflection;
- proof quality feedback;
- receipts;
- source and timestamp;
- private cloud-sync consent;
- delete/archive controls;
- evidence-to-readiness linkage.

### F. Career practice

- targeting decisions;
- job-description comprehension;
- resume-bullet practice;
- networking-message practice;
- interview multiple choice only where appropriate;
- short-answer coaching;
- ordering/prioritization exercises;
- recorded interview practice later;
- AI discussion grounded in the user's goal and proof.

### G. Career memory and assets

- facts explicitly provided by user;
- inferred hypotheses awaiting confirmation;
- provenance for every fact;
- confidence and last-updated date;
- saved advice;
- notes;
- evidence cards;
- skill cards;
- resume story fragments;
- interview stories;
- application materials later;
- export and deletion.

### H. Progress and retention

- streak;
- streak recovery/freezes;
- XP;
- readiness categories;
- proof count and quality;
- quest completion;
- time spent;
- active days;
- weekly level-up report;
- evidence collected;
- milestone celebrations;
- optional accountability partner later.

### I. AI assistant

- contextual quest help;
- explain why a quest matters;
- brainstorm an honest approach;
- evaluate submitted proof;
- connect evidence to a future resume/interview story;
- suggest next steps;
- retain only confirmed memory;
- fallback when AI is unavailable;
- user-visible correction path;
- clear distinction between advice, inference, and fact.

### J. Monetization

The first useful loop should remain accessible. A paid plan can eventually sell:

- longer or multiple active career missions;
- deeper personalization and memory;
- more AI evaluations;
- job-specific sprints;
- resume/LinkedIn asset generation based on real proof;
- interview practice;
- advanced reports;
- audio briefings;
- higher source and attachment limits.

## Recommended Build Order

### Rich V0: the complete first product

The first public-quality version should feel complete, not like an engineering demo. It should include:

1. polished onboarding;
2. goal creation;
3. working AI Cooked evaluation with deterministic fallback;
4. editable mission brief;
5. seven- or fourteen-day career map;
6. daily quest;
7. proof submission;
8. proof feedback;
9. XP, forgiving streak, readiness movement, and completion celebration;
10. notes/evidence cards;
11. weekly report;
12. push reminders;
13. account/privacy controls;
14. robust loading, offline, retry, empty, and error states.

This is the smallest version that can credibly deliver the “Wondering for jobs” promise.

### V1: turn proof into job assets

- resume and LinkedIn improvements based only on confirmed proof;
- job-description import;
- evidence-to-bullet and evidence-to-story conversion;
- saved career-asset library;
- deeper progress reports;
- subscription.

### V2: opportunity preparation

- job-specific mission mode;
- role-specific interview practice;
- interview story builder;
- audio briefings;
- deeper review/spaced repetition;
- approved external resource search;
- optional accountability partner.

### Later

- friend streaks;
- broader social discovery;
- course/quest marketplace;
- community;
- autonomous opportunity search;
- school/employer products.

## Product Principles Derived From the Audit

1. **The map creates trust; the daily action creates value.**
2. **AI should ask before it generates.**
3. **The user must approve the model's understanding before it becomes durable state.**
4. **Chat belongs inside structured work, not at the center of the app.**
5. **Every reward should connect to a real capability, artifact, or action.**
6. **Progress needs multiple signals; XP alone is decorative.**
7. **A playful identity can coexist with serious outcomes.**
8. **Feature unlocks can teach the product gradually.**
9. **Generated content needs structured schemas, validation, and safe rendering.**
10. **Career claims require stricter truth controls than general educational content.**
11. **The first useful outcome must arrive before monetization pressure.**
12. **OpenLARP should be private transformation before public professional performance.**

## Open Questions for Future Validation

- Which general LLM provider and model does Wondering currently use?
- Are different jobs routed to different models?
- How are course sources grounded and cited?
- Does FSRS schedule knowledge-card reviews, practices, or both?
- What are the exact free-plan limits for lessons, chats, courses, and podcast episodes?
- How does the iOS experience differ from the web product?
- What part of the podcast is generated text-to-speech versus scripted multi-host dialogue?
- How does Gmail summary become learning content in the visible product?
- How are public shared projects represented and revoked?
- How does Wondering evaluate content quality and hallucinations?
- Does the app maintain distinct confirmed facts, inferred facts, and course-specific assumptions internally?

These should be treated as unknown until verified through the iOS app, official documentation, or authoritative technical disclosure.
