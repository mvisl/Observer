export type DashboardTotals = {
  observedSeconds: number;
  activeSeconds: number;
  attributableSeconds: number;
  assignedSeconds: number;
  unassignedSeconds: number;
  idleSeconds: number;
  sensorGapSeconds: number;
  coverage: number;
};

export type TimelineSegment = {
  id: string;
  start: string;
  end: string;
  activeSeconds: number;
  elapsedSeconds: number;
  userAttributableSeconds: number;
  agentExecutionSeconds: number;
  primaryActor: string;
  engagementMode: string;
  agencyConfidence: number;
  threadId?: string;
  threadName: string;
  episodeId?: string;
  summary: string;
  applications: string[];
  artifact?: string;
  activityKind: string;
  confidence: number;
  evidenceChannels: string[];
  state: "assigned" | "unassigned" | string;
  sourceEventIds: string[];
};

export type ThreadSummary = {
  id: string;
  name: string;
  status: string;
  activeSeconds: number;
  firstSeen?: string;
  lastSeen?: string;
  episodes: number;
  artifacts: string[];
  applications: string[];
  confidence: number;
  hasConflicts: boolean;
  sourceEventIds: string[];
};

export type ReviewItem = {
  id: string;
  type: string;
  segmentId?: string;
  title: string;
  affectedSeconds: number;
  confidence: number;
  supportingEvidence: string[];
  contradictingEvidence: string[];
  alternatives: string[];
  sourceEventIds: string[];
};

export type SensorChannel = {
  id: string;
  name: string;
  status: string;
  coverage: number;
  freshnessSeconds?: number;
  events: number;
  lastEventAt?: string;
};

export type ArtifactRole =
  | "primary_artifact"
  | "current_result"
  | "decision_input"
  | "communication"
  | "implementation"
  | "reference"
  | "previous_version";

export type ArtifactRelation = {
  id: string;
  taskId: string;
  role: ArtifactRole;
  artifactKind: string;
  sourceIcon: string;
  title: string;
  roleSummary: string;
  directLink?: string;
  lastUsedAt: string;
  relatedEpisodeCount: number;
  confidence: number;
  aliases: string[];
  evidenceEventIds: string[];
};

export type DayDashboardSnapshot = {
  schemaVersion: string;
  snapshotId: string;
  generatedAt: string;
  date: string;
  timezone: string;
  pipelineVersion: string;
  dataRevision: string;
  valid: boolean;
  invariantErrors: string[];
  totals: DashboardTotals;
  confidenceDistribution: { high: number; medium: number; low: number };
  timelineSegments: TimelineSegment[];
  threadSummaries: ThreadSummary[];
  reviewSummary: {
    total: number;
    unassigned: number;
    lowConfidence: number;
    conflictingEvidence: number;
    sensorGaps: number;
    items: ReviewItem[];
  };
  sensorSummary: { channels: SensorChannel[] };
  causalSummary: {
    hypotheses: Array<{
      id: string;
      transition: string;
      mechanism: string;
      maturity: string;
      confidence: number;
      evidenceEventIds: string[];
    }>;
  };
  readinessSummary: {
    status: string;
    blockers: string[];
    metrics: Record<string, string>;
  };
  artifactRelations: ArtifactRelation[];
};
