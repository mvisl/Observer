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
- context: `screenContext`, `ocrContext`
- attention: `attention`
- interpretation: `activityInsight`
- camera lifecycle: `cameraPermission`, `cameraAttentionStarted`, `cameraAttentionStopped`
- memory: `localSummary`, `researchDigest`, `userNote`
- external reasoning: `externalLLMRequest`, `geminiInsight`, `localInsight`
- secrets: `geminiKeyUpdated`, `geminiKeyDeleted` record only key lifecycle metadata, never key material
- privacy: `privacyAllowlistAdded`, `privacyExclusionAdded`
- product: `detectorFired`, `hintCandidate`
- lifecycle: `appLaunch`, `appShutdown`, `observingStarted`, `observingPaused`, `sessionBoundary`
