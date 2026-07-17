# Wave 0 Foundation

Wave 0 is the foundation pass for Observer Architecture v2. It does not enable predictions, proactive actions, fatigue alerts, music recommendations, notification blocking, billing, public reporting, or causal claims in the pill.

## Current Acceptance State

This repository now contains the Wave 0 architecture contract, migration policy, golden-day contract, and first typed foundation models for ProcessRun, IntervalEpoch, ArtifactIdentity, IntentionAnchor, ContextSlice, Agency, and PredictionLog schema.

Wave 0 is not fully accepted yet. Live acceptance still requires stable Apple Development signing, five rebuilds without repeated TCC/Keychain prompts, golden-day replay against live data, and user acceptance of rebuilt reports.

## Strict Order

1. Stable Apple Development signing.
2. IntervalEpoch + ProcessRun.
3. Migration boundary.
4. Golden-day replay harness.
5. ArtifactRegistry.
6. IntentionAnchor.
7. ContextSlice + revised Episode schema.
8. Agency schema + shadow scorer.
9. Coverage-aware task-first Daily Report.
10. Camera hourly health + AU evidence schema.
11. Ground-truth correction UI.
12. Live validation for 12, 15, and 16 July.

## Implemented in This Foundation Slice

- Architecture v2 document.
- Wave 0 document.
- Data migration policy document.
- Golden-day definitions document.
- Typed Swift contracts for:
  - ArtifactIdentity;
  - ArtifactRelation;
  - IntentionAnchor;
  - ContextSlice;
  - WorkActor;
  - EngagementMode;
  - IntervalEpoch;
  - ProcessRun;
  - PredictionLog schema, inactive by default.
- Event types for `intervalEpoch`, `processRun`, and `predictionLog`.
- Tests for:
  - user/agent time separation;
  - phantom interval rejection;
  - prediction schema remaining unshown;
  - Jira artifact identity as stable task anchor.

## Acceptance Gates Still Open

- Apple Development certificate is not confirmed in the local keychain.
- Five rebuilds without repeated permission prompts are not proven.
- Gemini key persistence after rebuild is not proven.
- Golden-day replay harness is not yet wired into CI.
- Existing EventStore still uses a generic events table; dedicated normalized tables are not yet migrated.
- ContextSlice is modeled, but not yet the only production attribution path.
- Agency scorer exists in the old flow, but the v2 typed model is not yet the sole source of Daily Report.
- Camera hourly health is not yet the only camera aggregate path.

## Non-Goals

- No proactive pill insights.
- No predictions shown.
- No automatic media actions changed by this pass.
- No new camera emotion claims.
- No external sending.
- No dashboard-side interpretation.

## Live Acceptance Checklist

- Commit and push are complete.
- Build path/version recorded.
- Stable signing identity recorded.
- Five rebuild table recorded.
- Gemini persistence result recorded.
- Migration and golden-day definitions linked.
- 12 July, 15 July, and 16 July reports regenerated.
- User active, supervising, reviewing, delegated foreground, and delegated background totals shown separately.
- Partially assigned and globally unassigned intervals visible.
- Apps appear only as evidence/metadata.
- No sanitary wording in daily report.
