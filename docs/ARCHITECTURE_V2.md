# Observer Architecture v2

Observer is an intention system, not an app timer. Its job is to explain what result the user was trying to produce, who actually did the work, what evidence supports that interpretation, and where the system is uncertain.

## Core Formula

Observer understanding = intention + actor + engagement + evidence + time + uncertainty.

It is not foreground application + duration + a polished LLM summary.

## Pipeline

Sensors -> Raw Observations -> Normalized Evidence -> Artifact Identity -> Intention Anchors -> Context Slices -> Episodes -> Intention Hierarchy -> Agency Attribution -> Cross-episode Context Linking -> State Transitions -> Causal Hypotheses -> Personal Patterns -> Daily Report -> future predictive capabilities.

The web dashboard is only a read/review surface:

Intention Hierarchy + Agency Attribution + Context Slices -> Daily Activity Tracker -> Web Dashboard.

The dashboard must not build episodes, compute totals from raw events, determine intention or agency, call an LLM, or mutate SQLite directly. Core provides consistent snapshots.

## Truth Layers

### Deterministic Substrate

Stores facts that do not require interpretation: timestamps, process runs, interval epochs, lock/sleep/restart, canonical artifact IDs, URLs, repo roots, Figma/Jira/chat IDs, input activity, app focus, content snapshots, user prompts/corrections, coverage.

LLMs do not write facts into this layer.

### Probabilistic Layer

Stores interpretations: episode boundaries, intention assignment, agency, semantic links, fusion, causal candidates, activity-thread linking. Every object must carry confidence, supporting and contradicting evidence, alternatives, scorer/model version, and revision history.

### LLM Layer

Produces names, summaries, mechanisms, alternatives, and narratives only. It cannot be the source of time, count, status, identity, agency, causal truth, readiness, or confidence. Numbers come from aggregates. Claims without evidence are removed or marked uncertain.

## Intention Hierarchy

The hierarchy is:

Stream -> Project -> Workstream/Deliverable -> Intention -> Attempt/Step -> Episode -> ContextSlice.

Apps are metadata, not nodes. Activity kind is a characteristic, not the task.

Example: Work -> Libertex -> WhatToBuy -> PD-43661 Deposit page redesign -> Dividend logic -> Figma execution. A chat with Andrey is evidence or a sub-step inside that tree, not the top-level task if a stable Jira/Figma artifact exists.

## Artifact Identity

Stable artifact IDs outrank pretty semantic labels. Priority:

1. Provider/app ID.
2. Canonical path.
3. Repo + relative path.
4. Stable doc/thread/conversation ID.
5. Canonical URL.
6. URL hash.
7. AX title.
8. OCR/title fallback.

OCR and window titles are alias evidence, not primary identity.

Artifacts can be related as references, created_from, revises, discusses, implements, verifies, linked_from, same_as, or alias_of. Every relation needs evidence IDs, confidence, source, revision, and pipeline version.

## Context Slice

ContextSlice is the minimal temporal attribution unit. Episodes are semantic containers. Slices are non-overlapping chunks with user time and agent time separated.

A slice cuts on intention change, dominant artifact change, semantic topic shift, new user prompt, AI phase, engagement mode, lock/sleep/restart, idle, project switch, agent foreground/background transition, or meeting/call transition. A short app switch alone does not cut the slice when intention and agency remain stable.

Required time axes:

- Unique user time: active/formulating/reviewing/supervising time, never double counted.
- Agent execution time: can run in parallel and must not be counted as user active time.

## Agency

WorkActor values: user, Codex, ChatGPT, Claude, Gemini, localModel, automation, unknownAgent.

EngagementMode values: active, formulating, reviewing, supervising, delegatedForeground, delegatedBackground, waiting, passiveObservation, meetingParticipation, unknown.

A strong artifact match is not proof of user active work. An agent commit or visible output is not proof of a user decision unless there is evidence of user review, acceptance, execution, or correction.

## Evidence Fusion

Evidence groups are screen, input, camera, audio, media, artifact, prompt, history, and user_label. Some groups are not independent: OCR and AX from the same screen, app focus and interval, multiple camera cues from one frame, or multiple rules from the same content snapshot.

Fusion must track effective independence. One sensor group cannot publish a strong user-facing conclusion. History is a prior, not evidence by itself.

## Anti-Sanitary Output

The user-facing layer must not publish bare activity statements like "reads", "looks", "switches tabs", "works with AI", "opened Chrome", "high activity", "friction", or "positive reaction".

A publishable insight needs these slots:

- intention/goal;
- change, obstacle, loop, transfer, or decision;
- concrete artifact/work node;
- evidence refs;
- confidence.

If those slots are missing, the correct fallback is quiet or "no verified insight", not a sanitary status.

## Camera Layer

Camera data is split into physical features and interpretations.

Physical features: face presence, head pose, gaze candidate, body pose, hand pose, phone, headphones, cup/bottle/can, food, hand near mouth, eyes closed, posture, and FACS/AU descriptors.

Interpretations are candidates only. AU4 is not irritation. Smile is not joy. Camera cues remain shadow until calibrated and fused with other evidence.

Camera health is reported hourly: captured/processed/dropped frames, face share, confidence, AU quality, lighting, absent share, model version, and CPU. Health is not a user state.

## Corrections

User corrections are ground truth and create versioned assignments. They must support same/different context, project/workstream/intention/attempt assignment, unassign, rename, active/formulating/reviewing/supervising/agent background/mixed/wrong actor, and undo.

User-renamed nodes become locked and automation must not overwrite them.

## Daily Report Contract

Daily Report starts with intentions, not logs or sensors:

1. Coverage warning.
2. Projects and intentions.
3. User unique time.
4. Delegated agent work.
5. Timeline by intentions.
6. Partially assigned time.
7. Global unassigned.
8. Confirmed loops/transitions.
9. Open intentions.
10. Diagnostics appendix.

Main focus ranking is based on user involvement: active/formulating = 1, reviewing = 0.8, meeting = 0.7, supervising = 0.6, waiting = 0.1, delegatedBackground = 0.

## Causal Layer

Causal hypotheses are built from state transitions, antecedent candidates, causal role, mechanism, supporting and contradicting evidence, alternatives, cross-episode validation, and maturity.

Causal roles: trigger, enabling condition, maintaining factor, blocker, resolution, consequence.

Maturity: sequence, association, plausible mechanism, repeated pattern, counterfactual support.

Causal hypotheses are not published in the pill in Wave 0.

## Readiness

Each capability has its own stage: S0 collect, S1 shadow, S2 calibrated shadow, S3 trusted limited, S4 full.

Readiness gates block user-facing use and future actions. They do not disable sensors, context linking, daily reports, or shadow causal collection.

## Forbidden Shortcuts

- App focus -> task.
- Artifact ID -> user active work.
- Camera cue -> emotion.
- Agent execution -> user time.
- LLM output -> numeric/factual truth without deterministic check.
- Tracker -> causal truth, prediction, or action.
