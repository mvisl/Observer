# Observer Dashboard Read Model v0

The web UI consumes versioned DTO snapshots built by Observer Core.

Current snapshot:

- `DayDashboardSnapshot`
- `DashboardTimelineSegment`
- `DashboardThreadSummary`
- `DashboardReviewItem`
- `DashboardSensorChannel`
- `DashboardCausalHypothesis`
- `DashboardReadinessSummary`

The browser must not:

- read SQLite directly;
- compute day totals from raw events;
- segment episodes;
- assign activity threads;
- compute cognitive state;
- call LLMs.

Snapshot invariants enforced in Core:

- `assignedSeconds + unassignedSeconds == attributableSeconds`
- `activeSeconds <= observedSeconds`
- `attributableSeconds <= activeSeconds`
- `timeline segment total == attributableSeconds`

If an invariant fails, the snapshot remains visible but is marked invalid and includes
diagnostic errors.
