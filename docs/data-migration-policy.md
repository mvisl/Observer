# Data Migration Policy

Observer v2 uses a hybrid migration.

## Decision

Use option D:

- Backfill ProcessRun and IntervalEpoch where reliable lifecycle evidence exists.
- Backfill ArtifactIdentity from stable IDs and canonical URLs.
- Backfill intention and agency only for golden days and for new data after the v2 pipeline switch date.
- Keep old data available through legacy-read views, but do not mix old and new models silently.

## Rules

Every backfilled object must carry:

- `source = migration`;
- limited confidence;
- migration pipeline version;
- source evidence IDs where available.

Legacy `activityInsight` is not a source of truth. It may be archived as historical raw interpretation, but cannot feed task hierarchy, agency, daily report, prediction, or causal claims.

## Raw Content

Raw fragments for `message`, `email`, and `feed` are removed or compressed into annotations. Raw storage remains allowed only for configured working artifact kinds: `prompt`, `code`, and `doc`.

## Switch Boundary

Until the live Wave 0 switch is accepted, the current production event stream is considered mixed. Dashboard and daily report must show confidence/coverage and avoid pretending old inferred intervals are clean v2 slices.

## Backfill Confidence

- Deterministic lifecycle and artifact IDs: high if source IDs are stable.
- URL/title aliases: medium.
- Intention/agency from historical content: low to medium unless user-labeled.
- Camera emotion claims: not backfilled as truth.

## Audit Requirement

Any migration that changes counts, totals, assignments, or raw content retention must produce:

- row counts before/after;
- quarantine counts;
- deleted/redacted raw fields count;
- affected date range;
- migration marker.
