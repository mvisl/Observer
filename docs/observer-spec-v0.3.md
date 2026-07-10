# Local Work Observer for macOS - Spec v0.3

Status: working product and engineering spec.

This version removes any dependency on a specific app such as Figma. The system observes a workspace, not a tool. Any display can be the main workbench, and any app can become the current task context.

## 1. Philosophy

Observer is not an activity tracker and not a reporting tool. It is a local working companion that helps the user recover context, notice patterns, and prepare better context for AI assistance.

The product should collect many signals but store very little noise. Raw screen, camera, and interaction data are temporary. Persistent storage contains events, summaries, calibration state, and user-confirmed labels.

The first useful feature is not automatic advice. The first useful feature is context recovery: "what was I doing?", "where did I stop?", and "collect context for the task I am in right now."

## 2. Current User Setup

The initial setup has two displays.

- One display is the main workbench. Today this may be Figma, but the system must not treat Figma as special in the core model.
- One display is used for productivity, reference, communication, or operational tools.
- The camera is mounted on the secondary/productivity display and sees the user slightly from the side.
- Voice is secondary. The main signals are screen state, active windows, cursor behavior, input timing, and workspace changes.

The camera position matters. A side-mounted camera means head angle and gaze cannot be interpreted as if the camera were centered above the main display.

## 3. Workspace Topology Profile

The app stores an explicit profile of the physical workspace.

The profile includes:

- device role: `laptop_primary_device`, `laptop_secondary_device`, `desktop_host`, `unknown`;
- display roles: `main_workbench`, `productivity`, `reference`, `communication`, `unknown`;
- display positions relative to the user: `left`, `center`, `right`, `above`, `below`, `unknown`;
- camera mount: which display the camera belongs to and whether it is centered or side-mounted;
- primary input source: built-in keyboard, external keyboard, mouse, trackpad, unknown;
- workspace topology version.

This profile is configuration, not machine learning. It prevents the system from silently assuming that the camera is centered on the user's main visual target.

When the setup changes, the system creates a new `workspace_topology_version`, lowers confidence for camera-derived assumptions, and asks for a short recalibration only if needed.

## 4. Core Principle: Roles, Not Apps

The data model must not contain app-specific assumptions.

Bad model:

- "Figma screen";
- "browser is reference";
- "secondary screen is less important".

Good model:

- `display_role: main_workbench | productivity | reference | communication | unknown`;
- `current_context.app_id`;
- `current_context.window_title`;
- `current_context.project_hint`;
- `attention_zone: main_workbench | productivity | off_screen | unknown`.

Specific apps can have optional adapters, but Core must work without them.

## 5. Architecture

The system is split into Sensors and Core.

Sensors are platform-specific:

- screen capture;
- window/app focus;
- accessibility text;
- OCR fallback;
- cursor and idle state;
- camera pose and gesture extraction;
- widget UI.

Core is portable:

- event schema;
- event filtering;
- summaries;
- memory search;
- calibration state;
- detector definitions;
- insight provider adapters;
- context pack generation.

Sensors produce normalized events. Core decides what those events mean.

## 6. Signal Priority

Text and structure should be collected in this order:

1. App-specific adapters, if available and explicitly enabled.
2. Accessibility API.
3. OCR fallback.

OCR is useful, but it should not be the first choice when structured text is available.

## 7. Screen Signals

The app observes both displays.

It tracks:

- active app;
- active window title;
- display role of focused window;
- cursor display and cursor region;
- clicks, scrolls, long hover;
- screen diff at low resolution;
- accessibility text or OCR summary for allowlisted apps.

Raw screen frames are never written to disk. They live only long enough to extract features.

## 8. Input Signals

The system tracks input timing, not typed content.

Allowed:

- idle time;
- typing activity as a binary/timing signal;
- click timing;
- scroll timing;
- cursor movement shape.

Not allowed:

- keylogging;
- storing typed characters;
- global input hooks that capture text.

## 9. Camera Signals

The camera is used as a behavior and attention signal, not as a precise eye tracker.

The system extracts:

- face present or absent;
- head yaw, pitch, and roll;
- rough attention zone;
- blink rate;
- leaning closer or away;
- looking away;
- stillness;
- nod or shake gestures when confidence is high enough.

The system stores points and aggregates, not images or video.

For this user's setup, attention zones are categorical:

- `main_workbench`;
- `productivity`;
- `off_screen`;
- `unknown`.

The model should not claim that the user looked at a specific button, text line, or pixel.

## 10. Calibration

Calibration has three layers.

Explicit calibration:

- user looks at each display and away from displays;
- system learns the rough ranges for attention zones;
- calibration is tied to a workspace topology version.

Implicit calibration:

- active typing or clicking on a display is weak evidence that attention is near that display;
- cursor and input are used as soft labels, never absolute truth.

Drift detection:

- if camera signals contradict input/display signals for long enough, lower confidence;
- ask for recalibration only after persistent mismatch.

## 11. Privacy Model

Privacy is based on allowlists.

Content extraction runs only in explicitly allowed apps. Non-allowed apps can still produce coarse focus events, but no content is captured.

Raw screen frames, camera frames, and typed text are not stored.

The user must have:

- visible observing status;
- pause/resume in one click;
- private-current-app action;
- event and summary browser;
- deletion by period, app, or project;
- full reset;
- log of every external LLM request.

External LLMs receive only summaries and aggregates, never raw frames or full OCR dumps.

## 12. Event Model

Persistent event types:

- `app_focus`;
- `window_focus`;
- `screen_context`;
- `input_activity`;
- `attention`;
- `gesture`;
- `voice_note`;
- `detector_fired`;
- `hint_shown`;
- `hint_response`;
- `user_label`;
- `calibration_change`;
- `workspace_topology_change`;
- `session_boundary`.

Each event includes:

- id;
- timestamp;
- type;
- source;
- platform;
- display role;
- app id;
- confidence;
- payload JSON;
- calibration version when relevant;
- workspace topology version;
- links to related events.

## 13. Memory

Raw buffers are temporary.

Events live for a configurable period, for example 90 days. After that they can be compressed into summaries.

Summaries are kept longer:

- 15 minute summary;
- session summary;
- day summary;
- project or topic summary.

The database should be encrypted locally.

## 14. Detectors

Detectors are deterministic first. LLMs should not be called for every small signal.

Initial detectors:

- return loop: repeated returns to the same context;
- ping-pong: frequent switching between two contexts;
- stuck state: little progress plus repeated focus on the same area/context;
- task shift: dominant context changes for several minutes;
- reading/thinking: static screen plus attention on screen plus no input;
- absence: face absent or no input for a threshold;
- fatigue: softer daily-summary signal, not an interruption.

Detector outputs are hypotheses, not facts.

## 15. UI

The app starts as a menu bar app with a small floating widget later.

The widget has two modes:

- collapsed pill: observing status, current context, session duration;
- expanded panel: current context, attention confidence, context collection, privacy action, note action.

The app should use pull before push. The user should ask for context more often than the app interrupts.

## 16. MVP-0

MVP-0 should avoid camera complexity.

It includes:

- menu bar app;
- workspace topology config;
- two-display awareness;
- active app/window tracking;
- idle/input timing without keylogging;
- allowlisted accessibility text;
- OCR fallback only if simple;
- local event log;
- context pack button;
- pause/resume;
- privacy exclusion for current app.

MVP-0 success condition:

The generated context pack is useful enough that the user actually wants to use it with external AI chats.

## 17. MVP-1

MVP-1 adds camera as an attention confidence layer.

It includes:

- camera permission;
- face landmarks;
- categorical attention zones;
- explicit calibration;
- implicit calibration;
- drift detection;
- attention events;
- no image/video storage.

## 18. Later Stages

After MVP-0 and MVP-1:

- detector validation period;
- quiet hints in widget;
- local summaries and semantic search;
- external LLM insight provider;
- weekly pattern review;
- optional voice notes;
- app-specific adapters where they prove useful.

## 19. Success Metrics

The product succeeds if:

- context recovery is genuinely useful;
- the user continues using it by week 4;
- the event log remains readable and compact;
- the app does not heat the Mac;
- summaries reconstruct the working day without raw screen storage;
- camera-derived assumptions remain humble and confidence-scored;
- the system gets more useful without becoming more intrusive.

## 20. Guiding Sentence

Observer should not know everything. It should know enough to help the user recover the thread of work and prepare better context at the moment it matters.
