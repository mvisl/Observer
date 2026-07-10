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
- interpretation: `activityInsight`, `behaviorCue`, `gazeCalibrationSample`
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

Attention payloads:

- face/head: `face_present`, `face_position`, `face_center_x`, `face_center_y`, `head_yaw`, `head_pitch`, `head_roll`
- eye contact: `eye_contact_score`, `eye_contact_candidate`, `eye_signal_source`
- pupil landmarks when available: `left_pupil_x`, `left_pupil_y`, `right_pupil_x`, `right_pupil_y`
- `eye_signal_source=pupil_landmarks` means Vision exposed pupil landmarks; `head_pose_only` is a weaker fallback

Behavior cue payloads:

- `cue`: `steady_focus`, `friction_candidate`, `strong_reaction_candidate`, or future weak cues
- `interpretation`: local explanation such as `sustained_single_context`, `rapid_context_switching`, `sudden_posture_change`, `frustrated_writing_tone`
- posture metrics when available: `motion_score`, `face_area_ratio`
- text markers when available: `markers`, for example `strong_negative_language`, `uppercase_emphasis`, `repeated_punctuation`
- likely cause when available: `likely_cause`, for example `visual_design_cacophony`
- context metadata: `activity_insight`, `app_name`, `app_id`, optional `display_role`
- cues are behavioral candidates, not definitive emotion labels

Gaze calibration sample payloads:

- `target_source`: `typing_caret_proxy`, `mouse_click_proxy`, or `mouse_motion_proxy`
- `target_display_role`, `target_screen_index`: inferred target display from typing focus or pointer location
- head/face measurements: `head_yaw`, `head_pitch`, `head_roll`, `face_center_x`, `face_center_y`
- context metadata: `app_name`, `app_id`, `activity_insight`, optional `mouse_display_role`
- samples calibrate rough gaze/head mapping over time; they are not exact eye-tracking points

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
