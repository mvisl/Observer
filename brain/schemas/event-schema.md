# Event Schema

Persistent local events have:

- `id`
- `timestamp`
- `type`
- `source`
- `platform`
- `display_role`
- `app_id`
- `confidence`
- `payload_json`
- `workspace_topology_version`

Syncable schema knowledge may live in GitHub. Real event rows should stay local by default.

Core event families:

- focus: `appFocus`, `appFocusInterval`
- context: `screenContext`, `ocrContext`, `writingContext`
- attention: `attention`
- interpretation: `activityInsight`, `behaviorCue`
- camera lifecycle: `cameraPermission`, `cameraAttentionStarted`, `cameraAttentionStopped`
- memory: `localSummary`, `researchDigest`, `userNote`
- external reasoning: `externalLLMRequest`, `geminiInsight`, `localInsight`
- media: `mediaPlayback`, `mediaReaction`
- secrets: `geminiKeyUpdated`, `geminiKeyDeleted` record only key lifecycle metadata, never key material
- privacy: `privacyAllowlistAdded`, `privacyExclusionAdded`
- product: `detectorFired`, `hintCandidate`
- lifecycle: `appLaunch`, `appShutdown`, `observingStarted`, `observingPaused`, `sessionBoundary`

Media reaction payloads:

- `reaction`: `quick_skip`, `volume_up`, or later higher-level reactions
- `preference`: `negative_candidate`, `positive_candidate`, or `neutral`
- `source`: media source, with Apple Music recorded as `Music`
- `source_family`: `apple_music`, `youtube`, or future source group
- `content_type`: `music`, `unknown_youtube_media`, or future learned content type
- track metadata: `previous_title`, `previous_artist`, `current_title`, `current_artist`
- context metadata: `activity_insight`, `app_name`, optional `confounder`
- `preference_recorded`: `true` only when the user appears present enough to treat the action as feedback

Behavior cue payloads:

- `cue`: `steady_focus`, `friction_candidate`, `strong_reaction_candidate`, or future weak cues
- `interpretation`: local explanation such as `sustained_single_context`, `rapid_context_switching`, `sudden_posture_change`
- posture metrics when available: `motion_score`, `face_area_ratio`
- context metadata: `activity_insight`, `app_name`, `app_id`, optional `display_role`
- cues are behavioral candidates, not definitive emotion labels

External LLM request payloads:

- `provider`, `model`, `request_kind`
- `status`: `started`, `failed`, or `blocked_budget`
- `estimated_cost_eur`, `spent_today_eur`, `daily_budget_eur` when a cost estimate is available

Writing context payloads:

- `context_kind`: `active_writing`
- `focused_element_value` or `selected_text`: compact redacted text from the active field
- emitted only for content-allowlisted apps, while keyboard input is recent, and only when the text changes
- intended for task understanding, not keystroke logging
- if Accessibility cannot expose the active field, an `ocrContext` may be emitted with `context_kind=writing_fallback`
