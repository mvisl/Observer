# Camera Action Understanding Audit - 2026-07-16

## Current production path

| Requirement | Status | Evidence / decision |
| --- | --- | --- |
| Tier 1 face landmarks | Working | `CameraAttentionService` runs a Vision face-landmark request in the live camera stream. |
| Tier 1 smile candidate | Working, unsafe proxy | It is still based on `outer_lips_aspect_ratio`; it remains shadow-only and cannot surface by itself. |
| Tier 1 mouth-open / yawn candidate | Working, unsafe proxy | It is a mouth-open trajectory, not a confirmed yawn; it remains shadow-only. |
| OpenFace 3 sidecar | Not connected | Parser, payload model and Unix-socket configuration exist; the sidecar is disabled and no live frame transport/inference is wired. |
| Personal AU z-score baseline | Partial | Normalizer and baseline builder exist, but receive no tier-2 samples until the sidecar is live. |
| Temporal cascade | Partial | Trajectory model and tests exist, but the live tier-1 path did not use it. |
| Fusion gate | Working for published output | Tier-1 cue payloads declare `display_eligible=false` and require tier 2 + fusion. |
| Pose / hands | Not implemented | No live pose or hand landmarks are currently sampled. |
| Object layer | Partial shadow | Vision classification runs with the camera snapshots and can create shadow `objectPresence`; it has no bbox/hand intersection or episode duration yet. |

## Observed noise before the guard

Query window: the preceding 24 hours of the local event store.

| Cue | Tier-1 candidates |
| --- | ---: |
| `positive_reaction_candidate` | 288 |
| `energy_drop_candidate` | 73 |
| `cameraTier2Sample` | 0 |

This confirms that the former stream was dominated by Tier-1 geometry proxies, not validated facial action units.

## Guard added in this revision

- Frame-quality gate for emotional candidates: face area, brightness and image-detail proxy must pass. Camera presence and attention continue even if this gate rejects an emotion candidate.
- Per-cue refractory period: 60 seconds. Repeated candidates merge into the same in-memory episode instead of generating new log rows.
- Per-cue hourly budget: 12. Further candidates remain shadow events but have their confidence multiplied by 0.55 and carry `self_throttled=true`.
- Every new threshold lives in `cameraDetectorSettings`; no camera action is allowed into the pill directly.

## Next implementation order

1. Wire a real OpenFace sidecar and collect a two-week A/B sample before changing the published facial-cue path.
2. Add body and hand landmarks at low frequency in shadow mode.
3. Replace classifier-only object presence with object boxes + hand intersection, then derive action episodes such as phone break, drinking and stretching.
