# Observer: intention hierarchy brief for Claude

Date: 2026-07-15  
Purpose: explain the desired mental model, show a small log slice, and identify why current reports/widget insights still feel too low-level.

## 1. Philosophy

Observer is not an app tracker and not a surveillance logger. It is a personal work-memory system that should reconstruct what the user was trying to do, why it mattered, which subtask was active, and which evidence supports that interpretation.

The central unit is not "Chrome", "Figma", "ChatGPT", or "Telegram". The central unit is intention:

> I need to do this task. This conversation, Figma section, research tab, AI prompt, code edit, or media reaction belongs to that task.

The product should climb from raw signals to human structure:

```text
life stream
  -> product / domain
    -> task
      -> subtask / decision plane
        -> action / research / communication / evidence
```

Concrete example:

```text
Work
  -> Libertex
    -> WhatToBuy
      -> Andrey Shevchishin
        -> feedback about upcoming dividends, teasers, badge copy, prioritization
      -> Figma execution
        -> updating card hierarchy and visible layout decisions
      -> AI assistance
        -> checking formulations, generating variants, validating structure
```

This is the mental model the dashboard must show. Communication with Andrey is not a separate "communication task". It is evidence and a sub-branch inside the WhatToBuy task, which itself belongs to Libertex, which belongs to Work.

Another example:

```text
Personal
  -> Communication
    -> Family
      -> wife
        -> music link, evening planning, household context
```

Personal communication can still matter for work if it has a measurable aftermath, but by default it should not pollute work-task baselines.

## 2. Current Data We Already Collect

From the local event database for 2026-07-15:

```text
cameraEvidence        7078
attention             4714
inputActivity          624
gazeCalibrationSample  593
breakpoint             324
appFocus               307
appFocusInterval       300
fusionHypothesis       266
behaviorCue            264
contentContext         188
attentionSpan          186
cognitiveState         141
boundReaction           22
mediaPlayback            7
episode                  3
```

Interpretation: the system has plenty of sensor-level data, but far fewer meaning-level records. The bottleneck is not observation volume. It is compression into stable human intentions.

## 3. Existing Schema Layers

Current meaningful event families include:

- `contentContext`: semantic annotation of visible/active content: kind, topic, sentiment, language, incoming/outgoing.
- `behaviorCue`: weak behavioral candidates, such as friction, strong reaction, steady focus.
- `fusionHypothesis`: cross-channel hypothesis, meant to combine camera, input, content, media, etc.
- `boundReaction`: behavior cue joined to nearby content.
- `attentionSpan`: cluster of related app switches.
- `cognitiveState`: flow, engaged, reading, wandering, overload, avoidance, idle, away.
- `episode`: longer unit of work/communication.
- `activityThread` and `contextSlice`: current attempt to group episodes into reportable work.

Good foundation. Weak point: `activityThread` still often names things by app/topic fragments rather than user-level intention.

## 4. Log Slice And Interpretation

### Raw-ish local event slice, redacted

```text
07:32 contentContext
app: ChatGPT
kind: prompt
topic: "Создать macOS assistant ..."
raw_fragment: local work context around Observer / dashboard / GitHub / Figma / Libertex

07:34 contentContext
app: Google Chrome
kind: message
topic: "приоритеты и что должно быть главным"
sentiment: neg

07:35 fusionHypothesis
cue: frustration_candidate
interpretation: frustrated_writing_tone
channels: camera, content, input

07:39 fusionHypothesis
cue: friction_candidate
interpretation: rapid_context_switching
channels: camera, content, input

08:30 episode
kind: ai_assisted_work
apps: Google Chrome -> ChatGPT -> Figma -> coreautha
duration: 28m 44s
goal: "улучшить смысловую глубину Observer"
topic: noisy browser/window string
span_count: 43
switches_within_span: 82

10:04 episode
kind: ai_assisted_work
apps: ChatGPT -> Figma -> Google Chrome -> Observer -> Finder -> Terminal
duration: 48m 22s
goal: "улучшить смысловую глубину Observer"
stage: blocked
span_count: 46
switches_within_span: 70
```

### Current weak interpretation

```text
AI-assisted work / Google Chrome / ChatGPT / Figma
Possible friction: rapid context switching
Possible goal: improve Observer semantic depth
```

This is technically true but not useful enough. It still describes tools and behavior, not the user's task structure.

### Desired interpretation

```text
Work -> Observer -> Reporting brain -> intention hierarchy

User is trying to force Observer to stop grouping by applications and start grouping by human task structure.

Subtasks:
- define the hierarchy model: Work -> Libertex -> WhatToBuy -> Andrey / Figma / research / AI
- fix dashboard so it shows nested intentions, not flat workstreams
- reject generic widget statuses because they do not prove understanding
- prepare a Claude-facing critique brief for the next design iteration

Evidence:
- repeated user corrections about "not apps, tasks"
- explicit example: Andrey Shevchishin is a lower-level branch of WhatToBuy, inside Libertex, inside Work
- dashboard code changes and GitHub Pages checks
- high switching between ChatGPT, dashboard, repo, browser, Figma is not task switching; it is one attention span inside the Observer/reporting task
```

The important distinction: high app switching can be focus, not fragmentation, when all switches belong to the same intention.

## 5. Current Main Mistakes

1. Flat grouping

The system still tends to group as:

```text
ChatGPT
Figma
Chrome
Andrey feedback
Observer dashboard
```

But the human structure is:

```text
Work -> Libertex -> WhatToBuy -> Andrey feedback -> Figma execution
Work -> Observer -> Dashboard/reporting -> task hierarchy model
```

2. Sanitary statuses

Examples the user rejects:

```text
Диалог с ИИ: читает
Веб-контекст: просматривает страницу
Коммуникация: отвечает
Исследование: отбираешь материал
```

These are activity labels, not insights. The widget should either show a second-level insight or stay in a neutral sensing state.

3. False certainty from camera

Repeated failures:

- user looks at phone, system says reading screen or Figma;
- user covers mouth, system says yawn;
- user smiles or does not smile, system sometimes misses or hallucinates positive reaction;
- user returns to computer, security media sometimes treats owner as unknown.

Camera evidence should be shadow unless fused with stronger context or calibrated owner/gaze evidence.

4. Context is collected but not bound deeply enough

`contentContext` exists, but the dashboard and pill often do not use it to infer task hierarchy. If visible text says "WhatToBuy", "Andrey", "Upcoming Dividends", "badge", "Figma section", the system should bind those as one branch.

5. Reports count what happened, not what the user intended

Old daily report has:

```text
Activity threads:
- AI-assisted work
- Design
Timeline:
- assigned / unassigned / app lists
```

The desired report has:

```text
Work -> Libertex -> WhatToBuy
  - Upcoming Dividends logic
  - Card hierarchy
  - Figma execution
  - Andrey feedback as evidence

Work -> Observer -> Dashboard/reporting
  - public dashboard
  - pill quality
  - intention hierarchy
```

## 6. Proposed Mental Model

### Entity types

```text
LifeStream
  examples: Work, Personal

Domain / Client / Product
  examples: Libertex, Observer, Family

Task
  examples: WhatToBuy, Observer dashboard, Nebius cover

Subtask / Decision Plane
  examples: Upcoming Dividends logic, Card hierarchy, Figma execution, PIN-gated public dashboard

Evidence Plane
  examples: communication, Figma canvas, AI prompt, Jira issue, browser research, code change, media playback, camera cue

Event
  raw local evidence with timestamp, app, content annotation, behavior cue, source ids
```

### Assignment rule

An episode should not choose a flat label. It should produce a path:

```json
{
  "path": ["Work", "Libertex", "WhatToBuy", "Upcoming Dividends logic"],
  "plane": "figma_execution",
  "evidence": ["Andrey feedback", "Figma selected section", "AI prompt"],
  "confidence": 0.78,
  "alternatives": [
    ["Work", "Libertex", "WhatToBuy", "Card hierarchy"]
  ]
}
```

### Attention rule

Switching apps is not automatically switching tasks.

If ChatGPT, Figma, Jira, Telegram/WhatsApp, and browser all share the same entity/topic/artifact, they are one attention span. The dashboard should show them as facets of a single task.

### Communication rule

Communication is not always a top-level task. It is usually evidence inside a task:

```text
Andrey message -> WhatToBuy evidence
Vitya call -> Oboard dashboard requirements
wife message -> Personal / Communication / Family
```

Only if communication has its own purpose does it become a task.

## 7. What The Dashboard Should Show

Default level:

```text
Work
  Libertex
    WhatToBuy — 4h 10m
    Trading Robot — 1h 20m
  Observer
    Dashboard/reporting — 3h 35m

Personal
  Communication
    Family — 38m
```

Drilldown:

```text
Work -> Libertex -> WhatToBuy
  Upcoming Dividends logic — 1h 14m
    - Andrey asked about short explanation under each product
    - User reframed it as teaser-level copy, not questionnaire-level copy
    - Figma badge/date logic was edited

  Card hierarchy — 1h 03m
    - user argued that prioritization is missing
    - task shifted from adding fields to deciding what is primary vs secondary

  Figma execution — 1h 53m
    - selected section / manual layout work
    - AI/Chrome used as supporting tools, not separate tasks
```

## 8. What The Pill Should Show

Bad:

```text
ChatGPT: reads
Chrome: browsing
Communication: replying
```

Better:

```text
WhatToBuy: Andrey's feedback is becoming Figma changes
Observer: you're forcing reports from app tracking into task hierarchy
Nebius cover: image direction is not matching the quiet data-center style
```

If confidence is low:

```text
Sensing: collecting context for current task
```

But this should be temporary. It should not hang for minutes as a pseudo-insight.

## 9. Major Achievements So Far

- Local event store exists and captures many channels: attention, input, content, media, app focus, fusion, states.
- Privacy posture is sane: raw content mostly local; secret scrubber; frames should not be retained by default.
- Episode layer exists.
- Attention spans exist, which is the right bridge between app switching and task continuity.
- Public dashboard is live behind PIN and now starts showing nested intention paths.
- Work hierarchy code exists and can be evolved rather than started from zero.
- Reports now have the beginnings of project/task grouping.

## 10. Main Technical Gaps

1. Need a real `IntentionPathResolver`.

Current `WorkHierarchyBuilder` mostly uses keyword heuristics and generated names. It should infer and persist paths:

```text
life_stream -> domain/product -> task -> subtask -> evidence_plane
```

2. Need stable memory of user-corrected paths.

If the user says "Andrey is WhatToBuy under Libertex", that must become durable memory, not a one-off dashboard edit.

3. Need better entity/task binding.

Entity `Andrey Shevchishin` should link to:

```text
Work -> Libertex -> WhatToBuy
```

unless context shows otherwise.

4. Need evidence-first insight generation.

Every pill line should have hidden source ids and at least two evidence types, or be labeled as sensing.

5. Need camera humility.

Camera should disambiguate, not dominate. For phone/away/yawn/smile, publish only after calibration/fusion or explicit user validation.

6. Need report UI drilldown.

The public dashboard should support:

- date/range selection that actually changes data;
- tree drilldown;
- subtask minutes;
- evidence timeline;
- correction controls: "this belongs under X".

## 11. Suggested Next Implementation Order

1. Add persistent `intention_path` records:

```text
id, parent_id, type, name, aliases, source, confidence, user_locked, first_seen, last_seen
```

2. Add `episode_intention_assignment`:

```text
episode_id, intention_path_id, plane, evidence_event_ids, confidence, alternatives, user_locked
```

3. Add user correction memory:

```text
"Andrey Shevchishin" -> Work / Libertex / WhatToBuy
"WhatToBuy" -> Work / Libertex
"OBoard" -> Freelance or Work, depending on user's confirmed taxonomy
```

4. Update daily report and dashboard to render from this tree, not from apps.

5. Make the pill consume only fresh intention-level summaries, not raw `activityInsight`.

6. Add review loop:

```text
Was this correctly assigned?
Work -> Libertex -> WhatToBuy -> Andrey feedback
[yes] [move] [split]
```

## 12. Key Question For Claude

Given the current event layers and the user's correction:

> "Communication with Andrey Shevchishin is a lower step of WhatToBuy, which is a lower step of Libertex, which is a lower step of Work"

What is the best data model and resolver strategy for durable intention hierarchy?

The desired output is not another activity classifier. It is a personal semantic filesystem of work:

```text
Work / Libertex / WhatToBuy / Andrey feedback / evidence
```

with time, confidence, source events, and user corrections attached.

## 13. Fatigue / Workload Report Model

The user also wants a report of how much the work itself appears to tire him. This should be behavioral, not medical and not personality/diagnostic language.

Useful research framing:

- Work fragmentation: Mark, Gonzalez & Harris, "No Task Left Behind?" found information work is naturally fragmented, so switches must be interpreted as working-sphere/task-context switches, not raw app changes. Source: https://dl.acm.org/doi/10.1145/1054972.1055017
- Attention residue: Leroy, "Why is it so hard to do my work?" argues that switching between tasks can leave attention attached to the previous task, reducing performance on the next one. Source: https://www.sciencedirect.com/science/article/pii/S0749597809000399
- Resumption lag: Altmann & Trafton / interruption literature treats the time to resume a suspended goal as a measurable cost of interruption. Source: https://act-r.psy.cmu.edu/wordpress/wp-content/uploads/2012/12/6ema_jgt_2002_a.pdf

Observer should therefore estimate fatigue load from behavioral aftermath, not from a single facial cue.

### Inputs

```text
intention density:
  active minutes per intention, number of nested subtask loops, unresolved decisions

fragmentation:
  true task switches, not app switches; app switches inside one intention are allowed

resumption lag:
  time from interruption / communication / phone / break back to first stable useful output

friction loops:
  repeated AI -> Figma -> browser -> AI cycles around the same unresolved criterion

input dynamics:
  typing rhythm, pause length, deletion ratio, burst stability vs personal baseline

camera:
  PERCLOS, confirmed yawn trajectories, posture changes; weak evidence only

media / recovery:
  music repeat, volume changes, skips, post-music focus span; only useful through aftermath
```

### Output shape

```text
Fatigue Load
  Work -> Libertex -> WhatToBuy
    load: medium-high
    why:
      - high decision density
      - repeated design/AI loops
      - unresolved hierarchy question
      - return-to-output cost after communication
    not enough evidence:
      - camera yawn/smile alone
      - music effect until repeated across sessions

  Work -> Observer -> Dashboard/reporting
    load: high
    why:
      - many corrections to the same conceptual model
      - repeated mismatch between expected insight and system output
      - high cognitive reorientation: implementation + critique + product philosophy
```

### Rules

1. Do not say "you are tired" from one cue.
2. Say "this work block looks costly" only when there is evidence in the aftermath.
3. Separate productive intensity from harmful fatigue.
4. A dense same-intention loop can be good focus, not fragmentation.
5. Fatigue claims need evidence from at least two classes: input/activity + context/outcome, or resumption lag + repeated friction.
6. Camera events are supporting evidence, not primary proof.

### Dashboard representation

The dashboard should add a fatigue section per branch:

```text
Branch: Work -> Libertex -> WhatToBuy
Fatigue load: medium-high
Evidence:
  - 4 subtask loops
  - repeated design hierarchy dispute
  - AI/Figma iteration loop
  - negative/friction writing signals
Recovery:
  - measure next stable focus block after break/music/chat
```

This gives the user a practical answer: not just "you worked 4h", but "this branch consumed attention because the decision criteria were unstable."
