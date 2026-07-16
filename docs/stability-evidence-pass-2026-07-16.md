# Stability & Evidence Pass — 16 July 2026

## Scope

This pass freezes new product features. Its purpose is to make the existing
observer survivable, evidence-bound, and privacy-correct before it learns any
new behaviours.

## Crash baseline

The local macOS diagnostic folder contained 13 Observer crash reports from
10–15 July. Eight mention the episode/context-fabric close path; nine mention
the previous media/AppleScript path. These counts overlap.

## Changes applied

| Area | Change | Expected result |
| --- | --- | --- |
| Episode close | Empty or incomplete lineage produces an `episode` with `status=degraded_close`; context enrichment is skipped when there are no source events. | Closing an episode cannot be an all-or-nothing operation. |
| Duplicate lineage | Collision-prone `Dictionary(uniqueKeysWithValues:)` sites now merge duplicate IDs deterministically. | Duplicate events cannot trap the process during context construction. |
| Media | AppleScript and browser automation were removed. The app sends only the native system play/pause media command. | A player probe cannot crash the main process. |
| Restart safety | One process lock, heartbeat each minute while observing, exponential delayed sensor start after unclean restarts (maximum five minutes). | No duplicate observers or tight restart loops. |
| Focus intervals | Current interval flushes every minute; durations over 18 hours are rejected with `focusIntervalRejected`. | A stuck Chrome focus interval cannot poison baselines. |
| Privacy migration | Existing `contentContext` records for `message`, `email`, and `feed` have raw text fields removed. New writes enforce the same boundary. | These contexts remain semantic annotations, not a transcript archive. |
| Evidence gate | Candidate and causal event classes without source/evidence IDs move to `_quarantine_contract_violations`. | The active memory contains only traceable hypotheses. |
| Gemini status | The current build reads a 0600 local key file or environment variable, not Keychain. It writes one status-change event, not repeated missing-key noise. | No Keychain permission loop from this build. |
| Camera pressure | Attention samples require confidence >= 0.25, are stored only on state changes or every 30 seconds, and emit `sensorHealth` every five minutes. | High-rate frame telemetry becomes compact, inspectable state telemetry. |
| Content prior | Figma starts as `design_artifact`; mail surfaces start as `email`. | Generic text classification cannot relabel Figma as an email/feed. |

## Live database verification after migration

The checks below inspect only schema, event types, and aggregate counts; no
personal content was read.

| Check | Result |
| --- | ---: |
| `contentContext` message/email/feed with a raw fragment | 0 |
| Active gated candidates without any non-empty evidence/source ID | 0 |
| First clean launch after migration: camera evidence events | 1 |
| First clean launch after migration: attention events | 1 |
| First clean launch after migration: sensor health events | 1 |

The pre-pass historical count for the current day was 9,128 `cameraEvidence`
and 6,904 `attention` events. The target of <=3,000 camera events/day must be
judged after a full new observing day, not extrapolated from the first minutes.

## Media limitation and the honest contract

macOS does not provide a reliable public cross-application API that can read
the playing state and metadata of an arbitrary Chrome YouTube tab. The old
AppleScript workaround was the source of crashes and has been removed.

The automatic pause path now runs when Observer has both (1) active system
audio and (2) a confirmed headphones-removed transition. It sends the native
system play/pause media key, records `command_confirmed=false`, and resumes
only sources it previously commanded. This is intentionally an action command,
not a false claim that a specific player paused. Hardware validation is still
required for the user’s actual headphones and YouTube route.

## Acceptance status

- Build and test suite: passed, 153 tests.
- Migration and live aggregate database checks: passed.
- Three full crash-free observation days: pending observation time.
- Full-day camera budget: pending observation time.
- Headphones/YouTube physical pause-resume: pending an on-device trial.

No new detector, prediction, or user-facing insight feature should be enabled
until the pending observation acceptance is met.
