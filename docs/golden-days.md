# Golden Days

Golden days are replay fixtures used to protect Observer from repeating known bad interpretations.

## 12 July

Purpose: mixed Chrome contexts and poor task attribution.

Expected:

- Hierarchy is built by intention, not foreground app.
- Chrome is evidence only.
- Weak or mixed areas remain partially assigned/unassigned.

Forbidden:

- Treating Chrome duration as a top-level task.
- Treating generic web context as a user goal.

## 15 July

Purpose: false presence, phantom/family attribution, system intervals, and broken day edges.

Expected:

- Phantom activity is quarantined or marked as observation gap.
- Security/away observations are separated from normal work.
- Long impossible intervals are rejected.
- Personal communication is not merged into work unless later evidence proves work aftermath.

Forbidden:

- Loginwindow/Chrome all-day intervals.
- Family/personal chat as top-level work task without evidence.
- Camera-only emotion conclusions.

## 16 July

Purpose: distinguish user focus from agent execution.

Ground truth:

- Main user focus was Observer.
- Libertex Mobile DSL was mostly executed by Codex in the background.
- User supervised/checked DSL intermittently.
- Strong DSL artifact identity did not mean user active work.

Expected:

- Observer is the main user focus.
- Libertex Mobile DSL is identified as project/artifact with primary actor Codex.
- Engagement splits into formulating, reviewing, supervising, and delegated background.
- Agent time is separate from user time.
- If evidence is insufficient, confidence is medium/low and the segment goes to review.

Forbidden:

- Reporting 111 minutes of DSL as user active time.
- Letting one strong artifact determine user intention.
- Hiding partially assigned or globally unassigned intervals.

## Replay Triggers

Run golden replay when changing:

- episode segmentation;
- context linker;
- artifact resolver;
- agency scorer;
- report builder;
- fusion;
- time accounting.
