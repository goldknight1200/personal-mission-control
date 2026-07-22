# Personal Mission Control product contract

## Product mission

Personal Mission Control is a native, voice-first iPhone personal operating system for one primary user. It converts goals, fixed obligations, recurring responsibilities, routines, workouts, food needs, projects, and changing daily input into a realistic week plan and a precise current-day execution plan.

The product reduces decision fatigue. It is strict about important outcomes, flexible about execution, and calm when reality changes. The user keeps final authority.

## Product principles

- Prefer consistency and current relevance over theoretical optimization.
- Keep the deterministic product useful offline and without an AI provider.
- Protect recovery, sleep, meals, relationships, music, creativity, and genuine free time.
- Replan the smallest affected future range; do not churn a stable schedule unnecessarily.
- Show preparation and travel because they consume real time, but style them more quietly than primary missions.
- Use direct, concise language such as “Gym starts in 15 minutes. Get ready now.” Avoid shame, childish gamification, and excessive motivation.
- Treat every personal value in this document as an editable seed default.

## Core experience

### Home

- A top-right menu opens a right-side panel for profile, nutrition, training, history/statistics, calendar, health, notifications, AI behavior, appearance, and app settings.
- The upper quarter of the screen gives the current time visual priority. A progress ring represents the current schedule block and may show time remaining.
- The expanded current-mission card is the largest card and shows its time plus visible mini-goals or checklist.
- Upcoming missions appear chronologically as smaller rounded cards. “Next” remains clear; later work becomes progressively quieter.
- The timeline scrolls continuously to the final item of the day.
- Bottom navigation is Home, Goals, an elevated central Microphone action, Lists, and Plan.
- Lists contains Today one-offs, Shopping, and Routines. Plan contains Day, Week, and Month. Goals contains long-term goals, projects, priorities, and approved training programs.
- The visual base is minimal and neutral. User-configurable category colors provide restrained accents; the active category may set the current accent.

### Voice-first input

The baseline flow is press and hold microphone, record, release, transcribe, show an editable transcript, then offer Send, Edit, and Retry. Nothing becomes an action before Send.

Every processed command records:

- raw and user-confirmed transcripts;
- detected intents and confidence per intent;
- extracted entities, times, and dates;
- proposed structured mutations;
- affected schedule range;
- consequences or warnings;
- whether explicit confirmation is required.

Natural language may create or complete work, change urgency or priorities, report a delay or late start, report pain or fatigue, change inventory, add shopping, enter shifts, or request replanning. Ambiguous or consequential proposals remain unapplied until confirmed.

## Planning and execution

### Planning horizons

- Maintain a general adaptive plan across seven days.
- Produce a detailed, chronological current-day timeline.
- Use a 30-minute minimum useful focused-project block.
- Generated flexible blocks may snap to five-minute boundaries. Imported fixed events retain exact times.

### Mission classification

Every schedulable mission supports:

- category, title, and optional mini-goals;
- rigidity: fixed, protected, flexible, deferrable, or droppable;
- importance, urgency, deadline, and due window;
- estimated duration, minimum useful block, actual duration, and split permission;
- recurrence or source routine;
- consistency and backlog cost;
- energy/cognitive demand, physical load, and body-area tags;
- preparation and travel before/after;
- location or context;
- dependencies and prerequisites;
- external-management state and user priority overrides.

The durable model also covers UserProfile/Preferences, Goal, Project, ScheduleBlock, FixedCommitment, Routine, Checklist/ChecklistItem, ShoppingListItem, InventoryItem, MealTemplate, PlannedMeal, NutritionTarget, WorkoutProgram, WorkoutSessionTemplate, ExercisePrescription, WorkoutLog, CompletionRecord, DailyCheckIn, RecoveryContext/PainFlag, notification/check-in state, ExternalCalendarItem metadata, and explainable SchedulingDecision records.

Project status is active priority, maintained, or backlog. Storage is unlimited; scheduling exposure is deliberate rather than one hour per project per day.

### Deterministic planning order

Apply hard constraints before ranked soft constraints and explainable tie-breakers:

1. Load fixed commitments and immutable external events.
2. Protect adequate sleep and required transitions.
3. Ensure plausible meal coverage and essential food blocks.
4. Place football, approved workout requirements, and protected recurring commitments subject to recovery constraints.
5. Place deadline-sensitive and highest-priority project work.
6. Place maintained-project exposure and routines within due windows.
7. Place chores, shopping, and optional activities in suitable windows.
8. Preserve reasonable unscheduled breathing room when the day allows it.

Soft decisions consider urgency, importance, deadline risk, backlog cost, consistency cost, recovery cost, context fit, alternative windows, transition overhead, and current user state. No single opaque score is the sole decision maker.

### Free time and overload

Unexpected availability is not automatically filled. Before inserting work, inspect surrounding commitments, coverage of important objectives, urgent or overdue work, and fragmentation. Use 10-30 minute gaps only for genuinely useful small or urgent work. Preserve free time when there is no strong reason to consume it.

There is no fixed mandatory buffer. Tight days may use most available time, but chronic overload moves or removes lower-value work instead of repeatedly sacrificing sleep.

### Replanning

- Freeze the past and completed history.
- Preserve in-progress work unless explicitly changed.
- Change only the remaining future timeline and minimize movement of unaffected blocks.
- A late start replans from the new available time.
- If the user resists important work, push back once with the concrete consequence and one or two alternatives, then accept the user’s decision.
- Skipping protected work or creating serious backlog requires consequence disclosure and explicit confirmation.
- Repeated misses trigger cause diagnosis—avoidance, bad timing, fatigue, unrealistic duration, changed priority, or disruption—before perpetual rescheduling.

### Completion and missed starts

Normal completion is one tap. Planned and actual durations remain separate; actual duration can be corrected when materially different.

Default check-ins occur 15 minutes before start, at start, around 15 minutes late, and around 30 minutes late while unresolved. Actions are Already Started, Start Now, Replan, and Skip. Already Started corrects actual start; Start Now replans the remaining day; Skip records the miss and evaluates consequences.

## Editable seed profile

- Time zone: Europe/Berlin; use 24-hour display.
- No regular university lectures for roughly two months unless changed.
- Work often occurs Monday, Wednesday, Friday, and Saturday; actual shifts are entered as fixed events.
- Football training is commonly Tuesday and Thursday evening; historical time is 18:30-20:30 but is not permanent.
- Football matches generally occur Saturday or Sunday at variable times.
- Gym target: four to five approved-program sessions per week.
- The highest-priority project has roughly a two-week progress/completion horizon.
- Planning horizon: seven days. Minimum focused-project block: 30 minutes.

Default transitions:

- work travel 10 minutes each way and preparation 10-15 minutes;
- football travel 10 minutes each way, preparation 10-15 minutes, and shower/change 25-30 minutes;
- gym travel about 16 minutes each way, preparation under 10 minutes, and shower/change 25-30 minutes;
- shopping travel about five minutes.

## Sleep, recovery, and training

- Target at least 7.5 hours of sleep; practical minimum is about 6.5 hours.
- Below about six hours, reconsider demanding physical work using context rather than automatically cancelling everything.
- Avoid heavy lower-body gym work in the 24 hours before a football match.
- Upper-body work may be suitable the day after a match; lower-body work depends on recovery.
- A pain or injury flag pauses exercises that materially load the affected area until explicit reassessment or clearance.
- The app preserves the user-approved workout program. It does not invent random sessions.
- Workout sessions support exercises, sets, rep targets/ranges, rest times, previous performance, actual weight/reps, later progression rules, and a current-set/rest-timer execution view.

## Nutrition and household

Nutrition seed targets are about 3,400 kcal, 180 g protein, and at least three substantial meals per day. The product estimates plausible adequacy without demanding obsessive exact tracking. Clear deficits cause a warning, practical suggestion, and eating block. Inventory supports quantities and low-friction states such as “low” or “three meals remaining,” predicts shortages, and proposes shopping before depletion.

Household seed cadence:

- light tidying daily;
- football laundry after sessions or matches, immediately or at the next viable window;
- groceries and meal preparation about every two to three days;
- trash about weekly, preferably Sunday evening;
- bedsheets about monthly.

Household work uses flexible due windows and combines compatible chores when useful.

## Daily and weekly reflection

The morning creates a provisional plan automatically and, when permitted, uses sleep as context. A lightweight “Anything changed?” prompt provides voice access without forcing a questionnaire.

The evening summary is passive unless unresolved items need a move-to-tomorrow, backlog, or drop decision.

Weekly consistency tracks football completed/planned, gym completed/target, project hours actual/planned, nutrition-target days, and sleep-target nights. Metrics reveal patterns; they do not shame.

## Privacy and integrations

- Local-first is the default.
- Calendar, Health, Speech, Notifications, and photo access each require an explicit purpose string and permission flow.
- Raw voice recordings are discarded when no longer needed unless retention is explicitly enabled.
- Never send raw HealthKit history, entire calendars, raw recordings, or unnecessary schedule context to a third party.
- Secrets live in secure platform storage and never in source control.
- EventKit, HealthKit, Speech, UserNotifications, App Intents/App Shortcuts, iCal, and optional image/OCR remain protocol-backed integrations.

## Product success

The first meaningful milestone is a local vertical slice that turns structured inputs into a coherent day, makes the current mission unmistakable, records progress, and minimally replans future work after a late start. Integrations do not substitute for this core usefulness.
