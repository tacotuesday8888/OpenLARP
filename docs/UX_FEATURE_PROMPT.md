# UX + Feature Prompt

Use this as a follow-up prompt after Open Design already has a visual direction.

```text
I like the current visual direction. Do not redesign the product from scratch.

Now refine the product UX, interaction design, feature relationships, button placement, navigation, screen states, and interaction logic.

The goal is to make the existing design feel like a real iOS app that a user can actually use every day.

Do not focus on visual exploration.
Do not make a marketing site.
Do not make a roadmap.
Do not invent a different product.

Keep the current visual style, but make the UX correct, complete, clear, and internally consistent.

Product Summary

OpenLARP is an iOS-first "Duolingo for careers / LinkedIn" app.

The user is trying to become a stronger job candidate through small daily career actions.

The app is not primarily a chatbot.
The app is quest-first.

The main loop is:

Goal setup -> Am I Cooked? diagnostic -> daily quest -> proof or self-report -> AI quality check -> XP/streak/progress -> next quest -> optional sharing

The product should always answer:

"What should I do today to become less cooked?"

Core UX Principle

Every screen must have:
- One clear main user goal
- One obvious primary action
- Clear secondary actions
- Clear next screen
- Clear feedback after action
- No dead ends
- No confusing CTA hierarchy
- No random dashboard clutter

The app should always guide the user toward the next useful career action.

Feature System And How Everything Connects

1. Goal Setup

The user starts by choosing a career goal.

Goal setup controls almost everything else in the app:
- The cooked diagnostic
- The daily quest plan
- The 7-day map
- Progress categories
- AI feedback
- Share cards
- Future recommendations

Goal setup should collect only what is needed:
- Current status: student, new grad, career switcher, unemployed, employed
- Target role or field
- Timeline
- Current background
- Existing projects/proof
- Confidence level
- Biggest blocker

Interaction logic:
- User answers quickly with chips, sliders, and short text fields.
- The app should avoid long profile forms.
- Each answer should make the diagnostic feel more personalized.
- After setup, the user immediately moves into the cooked diagnostic.

UX requirement:
The user should feel like they are getting an answer, not filling out paperwork.

Required actions:
- Primary: "Check If I'm Cooked"
- Secondary: "Skip for Now" only if safe
- Secondary: "Back"

2. Am I Cooked? Diagnostic

This is the viral hook and first major value moment.

The diagnostic uses goal setup answers to produce:
- Cooked score
- Goal-readiness score
- Biggest gap
- Strongest existing signal
- Fastest fix
- Recommended first quest

How it connects:
- The cooked score becomes the emotional hook.
- The biggest gap determines the first quest.
- The readiness score becomes the progress baseline.
- The result can generate a share card.
- The diagnostic creates the first 7-day quest map.

Interaction logic:
- User completes goal setup.
- App shows loading/scanning state.
- App reveals cooked score.
- App explains what the score means.
- App gives one clear next action.
- Primary CTA starts the first quest.

Required buttons:
- Primary: "Start My First Quest"
- Secondary: "Share Cooked Card"
- Secondary: "Adjust Goal"
- Optional: "Why am I cooked?"

UX requirement:
The user should never leave the diagnostic thinking "okay, now what?"
The next step must be obvious.

3. Today Quest

This is the home screen and core daily habit.

Today Quest is the most important screen in the app.

It should show one main action, not a list of random tasks.

A quest includes:
- Quest title
- Why it matters
- Estimated time
- Difficulty
- Proof required
- XP reward
- Readiness impact
- Suggested steps
- Submit proof action
- Swap quest option
- Skip/recovery option

How it connects:
- The quest is generated from the user's goal, cooked score, and current gap.
- Completing the quest changes XP, streak, readiness, badges, and future quests.
- Proof submitted here feeds into AI quality check.
- Weak proof may generate an improvement quest.
- Strong proof may unlock a badge or share card.

Interaction logic:
- User lands on Today.
- User sees the one task that matters today.
- User taps "Start Quest."
- Quest expands into steps.
- User completes task outside or inside the app.
- User taps "Submit Proof."
- User submits text/photo/link/self-report.
- App runs AI quality check.
- App gives feedback and progress update.
- User returns to Today or sees tomorrow preview.

Required buttons:
- Primary before starting: "Start Quest"
- Primary after starting: "Submit Proof"
- Primary after proof: "Check My Proof"
- Secondary: "Swap Quest"
- Secondary: "Save for Later"
- Soft secondary: "Skip Today"
- Recovery state: "Save My Streak"

UX requirement:
Today should feel like the user's daily mission control.
It should not feel like a dashboard full of random widgets.

4. 7-Day Quest Map

The map shows the short-term comeback plan.

It turns the product from "one AI answer" into a program.

The 7-day map should include:
- Today's quest
- Upcoming quest themes
- Locked/flexible future quests
- Weekly milestone
- Expected readiness improvement
- Streak status

How it connects:
- Created after the diagnostic.
- Updates after proof checks.
- Adjusts if user swaps/skips quests.
- Shows how today fits into the larger comeback plan.
- Helps retention by giving the user a reason to return tomorrow.

Interaction logic:
- User can view the map from Today.
- Today is highlighted.
- Completed days show proof/XP.
- Missed days show recovery options.
- Future days are visible but not overly detailed.
- User can tap a day to preview the quest theme, but today remains the main action.

Required buttons:
- "View Today"
- "Preview"
- "Recover Streak"
- "Swap This Day" if allowed

UX requirement:
The map should motivate consistency without overwhelming the user.

5. Proof Submission

Proof is the backbone of the product.

The app should make the user prove progress, but it should not feel heavy or intimidating.

Proof types:
- Text summary
- Screenshot/photo
- Link
- Self-report
- Later: file, resume bullet, job post, interview answer

How it connects:
- Proof feeds AI quality check.
- Strong proof increases readiness more.
- Weak proof gives lower XP or asks for improvement.
- Proof becomes part of the user's career evidence over time.
- Proof can later feed resume help, interview prep, and agent memory.

Interaction logic:
- User taps "Submit Proof."
- App shows simple proof options.
- User picks one or more proof types.
- App previews the submission.
- User submits.
- App checks quality.
- User either earns XP or gets improvement guidance.

Required buttons:
- "Add Text"
- "Add Screenshot"
- "Paste Link"
- "I Did It"
- "Save Draft"
- "Submit Proof"

UX requirement:
Proof should feel like sending a receipt, not writing an essay.

6. AI Quality Check

The AI quality check decides whether the action was meaningful.

It should not feel like a harsh grade.
It should feel like coaching.

The result should include:
- Accepted / needs improvement
- Quality score
- Reason
- One specific improvement
- XP earned
- Readiness change
- Next action

How it connects:
- Updates XP
- Updates streak
- Updates readiness
- Updates the 7-day map
- May unlock badge
- May generate share card
- May affect tomorrow's quest

Interaction logic:
- User submits proof.
- App shows checking animation.
- App gives clear result.
- If accepted, user gets XP/progress.
- If weak, user can improve proof or accept lower XP.
- User always has a next step.

Required buttons:
- If accepted: "Claim XP"
- If weak: "Improve Proof"
- If weak: "Accept Lower XP"
- After claiming: "See Progress"
- After claiming: "Share Win"
- After claiming: "Preview Tomorrow"

UX requirement:
Weak proof must not become a dead end.
The user should always know how to recover.

7. Self-Report

Self-report is the fallback when proof is hard.

It should count, but less than real proof.

How it connects:
- Keeps streak alive
- Gives partial XP
- Gives lower confidence progress
- May ask the user for more details
- May suggest stronger proof next time

Interaction logic:
- User selects "I Did It."
- App asks a few quick questions:
  - What did you do?
  - What changed?
  - What evidence could you add later?
- App gives partial credit.
- App may recommend adding proof for full XP.

Required buttons:
- "Self-Report"
- "Add Proof Instead"
- "Submit Self-Report"
- "Upgrade With Proof"

UX requirement:
Self-report should reduce friction without destroying product trust.

8. XP, Badges, And Streaks

These make the product sticky.

But they should reward real progress, not empty usage.

XP should be based on:
- Quest completion
- Proof quality
- Difficulty
- Consistency
- Improvement over time

Badges should reward meaningful behaviors:
- First proof submitted
- First networking action
- First improved project
- First profile upgrade
- First weekly streak
- First strong proof
- First share

Streaks should be forgiving:
- Missed day does not immediately destroy motivation.
- User can use streak freeze.
- User can complete recovery quest.
- Self-report gives partial streak support.

How it connects:
- XP appears after AI quality check.
- Badges appear after milestone events.
- Streak appears on Today and Map.
- Progress screen shows long-term impact.

Interaction logic:
- User completes quest.
- AI checks proof.
- App awards XP.
- App animates streak.
- App may unlock badge.
- App updates readiness.
- App gives tomorrow preview.

Required buttons:
- "Claim XP"
- "View Badge"
- "Share Badge"
- "Save Streak"
- "Do Recovery Quest"

UX requirement:
Rewards should feel tied to becoming a stronger candidate, not random game points.

9. Goal-Readiness Progress

This is the serious progress layer underneath the memes.

Progress should show that the user is becoming less cooked.

Progress categories:
- Overall readiness
- Proof strength
- Networking strength
- Profile strength
- Interview confidence
- Application readiness
- Consistency

For V0, keep it narrow:
- Overall readiness
- Proof strength
- Confidence
- Streak
- Weekly improvement

How it connects:
- Diagnostic creates baseline.
- Quest completion updates progress.
- Proof quality affects progress.
- Weekly review summarizes improvement.
- Future recommendations use progress gaps.

Interaction logic:
- User opens Progress tab.
- Sees readiness score over time.
- Sees strongest improvement.
- Sees weakest category.
- Sees next recommended action.

Required buttons:
- "View Proof"
- "Improve Weakest Area"
- "See Weekly Review"
- "Share Progress"

UX requirement:
Progress should be understandable at a glance.
The user should think: "I can see I'm getting better."

10. Share Cards

Sharing drives growth.

But sharing must be optional and privacy-safe.

Share card types:
- Cooked score card
- Less cooked than last week card
- Badge card
- Streak card
- Quest completed card
- Weekly comeback card

How it connects:
- Generated after diagnostic
- Generated after badge unlock
- Generated after weekly progress
- Generated after strong proof
- Can feed Instagram/TikTok growth

Interaction logic:
- App offers share at natural moments.
- User sees preview.
- Private details are hidden by default.
- User can edit caption.
- User can save image or share.
- Dismissing share should not punish the user.

Required buttons:
- "Share"
- "Edit Card"
- "Hide Details"
- "Save Image"
- "Not Now"

UX requirement:
The user should feel proud or amused, not exposed.

11. Paywall / 14-Day Sprint

The first experience is a 14-day free sprint.

The product should earn trust before asking for money.

How it connects:
- User starts free sprint after seeing value.
- Quest map becomes the sprint structure.
- Progress proves value before subscription.
- Subscription continues daily quests and progress tracking.

Interaction logic:
- User completes diagnostic.
- App offers "Start 14-Day Comeback Sprint."
- User gets access to quests.
- Near the end, app shows progress gained.
- Paywall asks user to continue.

Required buttons:
- "Start Free Sprint"
- "Continue My Plan"
- "See Student Discount"
- "Not Now" if allowed

UX requirement:
The paywall should feel like continuing a program, not unlocking random features.

12. Chat / Agent Helper

Chat is not the main app.

Chat can support the quest loop, but should not replace it.

Possible uses:
- Explain a quest
- Help draft a message
- Help improve proof
- Explain cooked score
- Help adjust goal
- Answer "why this quest?"

How it connects:
- Chat can be opened from specific contexts.
- Chat should know the current quest, goal, and progress.
- Chat should return the user back to action.

Interaction logic:
- User taps "Ask Agent."
- Chat opens with context.
- Agent helps with the current task.
- Agent suggests concrete next step.
- User returns to quest/proof flow.

Required buttons:
- "Ask Agent"
- "Use This Draft"
- "Back to Quest"
- "Save Suggestion"

UX requirement:
Chat should feel like support, not the entire product.

13. Future Agent Preview

The product eventually becomes a persistent career agent.

But V0 should only tease this.

Future agent capabilities:
- Search for opportunities
- Search for courses
- Search for certifications
- Search for projects
- Search for networking opportunities
- Track progress over months
- Recommend new quests automatically
- Draft messages or materials for approval
- Notify user about opportunities

How it connects:
- Future agent uses proof, goals, and progress history.
- User approvals are required before external actions.
- Memory/privacy controls matter.

UX requirement:
Show this as future direction, but do not make V0 depend on it.

Navigation Requirements

Design the actual app navigation.

Recommended V0 structure:
- Today
- Map
- Progress
- Profile

Optional:
- Agent helper as a floating/contextual action, not a main tab

Today:
Daily quest and main action.

Map:
7-day plan and streak recovery.

Progress:
Readiness, XP, proof strength, badges.

Profile:
Goal, settings, memory/privacy later, subscription.

Make sure:
- The user can always return to Today.
- Today feels like the center of the app.
- The tab bar does not become cluttered.
- Chat does not dominate the product.
- Important one-time flows use full-screen flows or modals, not permanent tabs.

Button Placement Requirements

Please audit button placement carefully.

For each screen:
- Put the primary button where the thumb naturally reaches on iPhone.
- Avoid multiple equal-looking primary buttons.
- Make secondary actions visually quieter.
- Put destructive or low-commitment actions away from the primary path.
- Use specific button labels.

Good labels:
- "Check If I'm Cooked"
- "Start My First Quest"
- "Start Quest"
- "Submit Proof"
- "Check My Proof"
- "Claim XP"
- "Improve Proof"
- "Accept Lower XP"
- "Save My Streak"
- "Preview Tomorrow"
- "Share Card"

Bad labels:
- "Continue"
- "Next"
- "Submit"
- "Done"

Only use vague labels if the context is extremely obvious.

Interaction States

For every major screen, define:

- Default state
- Empty state
- Loading state
- Success state
- Error state
- Completed state
- Already completed today state
- Missed day state
- Weak proof state
- Strong proof state
- Paywalled state
- Offline or failed AI check state

Important recovery flows:
- User skips a quest
- User misses a day
- User submits weak proof
- AI check fails
- User wants to change goal
- User does not want to share
- User hits paywall
- User self-reports instead of proof

Microcopy Requirements

Improve:
- Button labels
- Empty states
- Error states
- Loading copy
- Confirmation text
- AI feedback text
- Paywall copy
- Share prompts
- Streak recovery copy

Tone:
- Funny
- Blunt
- Supportive
- Not childish
- Not mean
- Not too corporate

Example tone:
- "You're cooked, but recoverable."
- "Your proof is currently a rumor."
- "This counts, but barely. Want full XP?"
- "Good move. This is actual candidate evidence."
- "You missed yesterday. Not fatal. Do one recovery quest."
- "LinkedIn lurking is not networking."

Required Output

Review the existing design and produce a UX refinement plan.

For every important screen, provide:

- Screen name
- User goal
- Main information shown
- Primary CTA
- Secondary actions
- Button placement recommendation
- What happens after tapping primary CTA
- What app state changes
- What feedback appears
- Empty/loading/success/error states
- Possible confusion
- Recommended UX fix

Also produce a feature interaction map showing how these features connect:

- Goal setup
- Cooked diagnostic
- Today quest
- 7-day map
- Proof submission
- AI quality check
- Self-report
- XP
- Streaks
- Badges
- Progress
- Share cards
- Paywall
- Agent helper
- Future autonomous agent

Also provide a full happy path flow:

New user opens app -> goal setup -> cooked diagnostic -> first quest -> proof submission -> AI check -> XP/streak/progress -> share card -> tomorrow preview

Also provide failure/recovery flows:

- User skips a quest
- User misses a day
- User submits weak proof
- AI check fails
- User wants to change goal
- User does not want to share
- User hits paywall
- User self-reports instead of proof

Finally, provide a UX audit table with:

- Screen
- Main user goal
- Primary CTA
- Secondary actions
- Next screen
- Required states
- Potential confusion
- Recommended fix

Do not redesign the visual style unless usability requires it.

Keep the design visually similar, but make the UX, interaction logic, feature connections, screen states, navigation, and buttons product-ready.
```
