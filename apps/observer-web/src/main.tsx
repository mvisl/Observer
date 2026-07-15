import React, { useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { NavLink, RouterProvider, createBrowserRouter, useLocation, useSearchParams } from "react-router-dom";
import { getDailyMarkdown, getDaySnapshot, getSession, pairDevice, submitCorrection } from "./api";
import type { DayDashboardSnapshot, SensorChannel, ThreadSummary, TimelineSegment } from "./types";
import "./styles.css";

const queryClient = new QueryClient();
const publicDashboardMode = import.meta.env.VITE_OBSERVER_PUBLIC_DASHBOARD === "1" || window.location.hostname.endsWith("github.io");
const publicAccessCode = "2501";

function todayString() {
  return new Date().toISOString().slice(0, 10);
}

function fmtDuration(seconds: number) {
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}м`;
  return `${Math.floor(minutes / 60)}ч ${minutes % 60}м`;
}

function fmtTime(value?: string) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("ru", { hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

function useSelectedDate() {
  const [params, setParams] = useSearchParams();
  const date = params.get("date") ?? todayString();
  const setDate = (next: string) => {
    params.set("date", next);
    setParams(params, { replace: true });
  };
  return [date, setDate] as const;
}

function useSnapshot() {
  const [date] = useSelectedDate();
  return useQuery({
    queryKey: ["v1", "day", date],
    queryFn: () => getDaySnapshot(date),
    refetchInterval: 30_000
  });
}

function AuthGate({ children }: { children: React.ReactNode }) {
  const session = useQuery({ queryKey: ["session"], queryFn: getSession, retry: false });
  const [code, setCode] = useState("");
  const pair = useMutation({
    mutationFn: pairDevice,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["session"] })
  });

  if (session.isLoading) return <div className="center">Подключаюсь к Observer Core…</div>;
  if (session.data?.authenticated) return children;
  return (
    <main className="pairing">
      <div>
        <p className="eyebrow">Private Observer Dashboard</p>
        <h1>Введите pairing code</h1>
        <p className="muted">Код копируется из меню Observer на Mac. Секрет не хранится в URL и не попадает в localStorage.</p>
        <form onSubmit={(event) => { event.preventDefault(); pair.mutate(code); }}>
          <input value={code} onChange={(event) => setCode(event.target.value)} placeholder="6 цифр" autoFocus />
          <button>Pair device</button>
        </form>
        {pair.isError && <p className="danger">Код неверный или истёк.</p>}
      </div>
    </main>
  );
}

function AppShell() {
  const [date, setDate] = useSelectedDate();
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">Observer</div>
        <nav>
          <NavLink to={`/today?date=${date}`}>Today</NavLink>
          <NavLink to={`/timeline?date=${date}`}>Timeline</NavLink>
          <NavLink to={`/contexts?date=${date}`}>Contexts</NavLink>
          <NavLink to={`/review?date=${date}`}>Review</NavLink>
          <NavLink to={`/causal?date=${date}`}>Causal</NavLink>
          <NavLink to={`/sensors?date=${date}`}>Sensors</NavLink>
          <NavLink to={`/readiness?date=${date}`}>Readiness</NavLink>
          <NavLink to={`/report?date=${date}`}>Report</NavLink>
        </nav>
      </aside>
      <main className="main">
        <header className="topbar">
          <div>
            <p className="eyebrow">Local Core API</p>
            <h1>Observer Web Dashboard</h1>
          </div>
          <label className="date-picker">
            Date
            <input type="date" value={date} onChange={(event) => setDate(event.target.value)} />
          </label>
        </header>
        <PageSwitch />
      </main>
      <nav className="bottom-nav">
        <NavLink to={`/today?date=${date}`}>Today</NavLink>
        <NavLink to={`/timeline?date=${date}`}>Timeline</NavLink>
        <NavLink to={`/review?date=${date}`}>Review</NavLink>
        <NavLink to={`/sensors?date=${date}`}>More</NavLink>
      </nav>
    </div>
  );
}

function PageSwitch() {
  const { pathname: path } = useLocation();
  if (path.startsWith("/timeline")) return <TimelinePage />;
  if (path.startsWith("/contexts")) return <ContextsPage />;
  if (path.startsWith("/review")) return <ReviewPage />;
  if (path.startsWith("/causal")) return <CausalPage />;
  if (path.startsWith("/sensors")) return <SensorsPage />;
  if (path.startsWith("/readiness")) return <ReadinessPage />;
  if (path.startsWith("/report")) return <ReportPage />;
  return <TodayPage />;
}

function PublicAccessGate() {
  const [code, setCode] = useState("");
  const [status, setStatus] = useState<"idle" | "checking" | "allowed" | "blocked">(
    () => sessionStorage.getItem("observer_public_access") === "ok" ? "allowed" : "idle"
  );
  const [message, setMessage] = useState("");

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (code.trim() !== publicAccessCode) {
      setStatus("blocked");
      setMessage("Wrong PIN.");
      return;
    }

    setStatus("checking");
    const result = await checkMontenegroAccess();
    if (result.allowed) {
      sessionStorage.setItem("observer_public_access", "ok");
      setStatus("allowed");
      setMessage("");
    } else {
      sessionStorage.removeItem("observer_public_access");
      setStatus("blocked");
      setMessage("Access unavailable.");
    }
  }

  if (status === "allowed") {
    return <PublicDashboardShell />;
  }

  return (
    <main className="pairing public-gate">
      <div>
        <p className="eyebrow">Observer Dashboard</p>
        <h1>Enter PIN</h1>
        <form onSubmit={submit}>
          <input
            value={code}
            onChange={(event) => setCode(event.target.value)}
            placeholder="PIN"
            inputMode="numeric"
            autoFocus
          />
          <button disabled={status === "checking"}>{status === "checking" ? "Checking…" : "Unlock"}</button>
        </form>
        {message && <p className={status === "blocked" ? "danger public-note" : "muted public-note"}>{message}</p>}
      </div>
    </main>
  );
}

async function checkMontenegroAccess(): Promise<{ allowed: boolean; reason: string }> {
  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 2500);
  try {
    const response = await fetch("https://ipapi.co/json/", {
      cache: "no-store",
      signal: controller.signal
    });
    const data = await response.json() as { country_code?: string; country_name?: string };
    if (data.country_code === "ME") {
      return { allowed: true, reason: "ok" };
    }
    if (timeZone === "Europe/Podgorica") {
      return { allowed: true, reason: "ok" };
    }
    return { allowed: false, reason: "blocked" };
  } catch {
    if (timeZone === "Europe/Podgorica") {
      return { allowed: true, reason: "ok" };
    }
    return { allowed: false, reason: "blocked" };
  } finally {
    window.clearTimeout(timeout);
  }
}

function PublicDashboardShell() {
  const workstreams = [
    {
      name: "Freelance / WhatToBuy board",
      time: "4h 10m",
      confidence: "high",
      outcome: "Turn product feedback into a clearer market card system.",
      subthreads: [
        "Upcoming Dividends: replace raw ex-dividend date with a safer buy-by date.",
        "Card hierarchy: move from question-level copy to teaser-level product signals.",
        "Figma execution: translate the conversation with Andrey into visible layout decisions."
      ]
    },
    {
      name: "Observer brain and dashboard",
      time: "3h 35m",
      confidence: "medium",
      outcome: "Push Observer from app-tracking toward intention tracking.",
      subthreads: [
        "Public dashboard: PIN gate, Pages deploy, app icon, simple access route.",
        "Pill quality: reject stale sanitary statuses and bind insight to the current screen.",
        "Reporting model: group the day by tasks, sub-tasks, decisions and evidence."
      ]
    },
    {
      name: "Product communication",
      time: "1h 20m",
      confidence: "medium",
      outcome: "Use chats as source material for product decisions, not as separate noise.",
      subthreads: [
        "Andrey feedback becomes a design task, not just a message thread.",
        "Personal chats stay personal unless they leave a measurable work effect.",
        "Repeated disagreement becomes a decision backlog instead of emotional labels."
      ]
    }
  ];
  const timeline = [
    ["Read", "Andrey's feedback", "Extracted requirement: the badge should reduce user calculation."],
    ["Decide", "Dividend card logic", "Shifted from ex-date data display to buy-by date guidance."],
    ["Apply", "Figma section", "Worked inside Upcoming Dividends card structure and labels."],
    ["Review", "Observer dashboard", "Rejected app-based reporting; demanded intention-based task hierarchy."]
  ];
  const decisions = [
    "A dashboard must answer what problem was advanced, not which app was open.",
    "Every episode needs intent, evidence, output, next decision and uncertainty.",
    "Tracker views should show task → subtask → episode, with apps only as supporting evidence."
  ];
  const weakSignals = [
    "Current public page cannot yet stream local Core data from GitHub Pages.",
    "Daily report still needs task taxonomy and merge logic across chat + Figma + AI.",
    "Pill insight staleness needs stronger expiry when the screen context changes."
  ];
  const musicSignals = [
    {
      title: "Repeat / sustained listening",
      detail: "A repeated or long-held track becomes a positive candidate only when you are present and do not skip it."
    },
    {
      title: "Work aftermath",
      detail: "The useful question is whether input rhythm, focus span or output quality improves after the track starts."
    },
    {
      title: "Confounders",
      detail: "If a message, call or visual task caused the reaction, the music signal stays uncertain until repeated."
    }
  ];
  const attentionSwitches = [
    {
      type: "Within-task transition",
      signal: "Chat → Figma → Chat around the same dividend-card question.",
      meaning: "Not a task switch. Same intention, different evidence surfaces.",
      measure: "Count inside one attention span; do not penalize as fragmentation."
    },
    {
      type: "True task switch",
      signal: "Dominant intention changes and the previous thread stops producing output.",
      meaning: "Attention residue is likely: part of the old task remains active.",
      measure: "Mark closure quality and time to stable output in the new task."
    },
    {
      type: "Interruption + resumption",
      signal: "External message/call/system event breaks an active work span.",
      meaning: "The cost is not the interruption itself, but the lag before useful work resumes.",
      measure: "Track resumption lag: return time → first meaningful edit/decision."
    },
    {
      type: "Research scanning",
      signal: "Many sources, tabs and short reads, all tied to one unresolved question.",
      meaning: "High switching can still be one task if the question stays stable.",
      measure: "Group by question/topic, not by browser tab count."
    },
    {
      type: "Drift / avoidance candidate",
      signal: "Repeated unrelated jumps with no artifact change and no decision output.",
      meaning: "Only a candidate; needs evidence from context, input rhythm and return pattern.",
      measure: "Surface only after repeated loops and failed resumption."
    }
  ];
  const researchSources = [
    ["Fragmented work", "Mark, Gonzalez & Harris: work is fragmented across working spheres, so switches must be interpreted by task context."],
    ["Attention residue", "Leroy: switching tasks can leave attention attached to the previous goal, hurting the next task."],
    ["Resumption lag", "Altmann & Trafton: interruption cost is measurable as time needed to collect the suspended goal and resume."]
  ];
  return (
    <main className="public-shell">
      <section className="public-hero">
        <p className="eyebrow">Observer Intelligence Dashboard</p>
        <h1>Work by intention, not by app</h1>
        <p>
          A daily tracker should reconstruct the work as connected intentions: what you tried to move forward,
          which conversations shaped it, what changed in the artifact, and what remains unresolved.
        </p>
        <div className="public-actions">
          <a href="http://127.0.0.1:43127/">Open Local Core</a>
          <a href="https://github.com/mvisl/Observer/tree/main/apps/observer-web">Dashboard Code</a>
          <a href="https://github.com/mvisl/Observer/tree/main/core/dashboard-api">Core API</a>
        </div>
      </section>

      <section className="public-kpi-grid" aria-label="Daily summary">
        <article>
          <span>Primary intention</span>
          <strong>Freelance product design</strong>
          <p>Turning feedback into a clearer board/card system.</p>
        </article>
        <article>
          <span>Context bridge</span>
          <strong>Chat → Figma</strong>
          <p>Andrey's notes became the dividend badge design task.</p>
        </article>
        <article>
          <span>Tracker principle</span>
          <strong>Intent first</strong>
          <p>Apps are evidence; tasks and decisions are the report unit.</p>
        </article>
      </section>

      <section className="public-section">
        <div className="section-head">
          <h2>Workstreams</h2>
          <span>task → subtask → evidence</span>
        </div>
        <div className="workstream-list">
          {workstreams.map((stream) => (
            <article key={stream.name} className="workstream-card">
              <div>
                <h3>{stream.name}</h3>
                <p>{stream.outcome}</p>
              </div>
              <div className="workstream-meta">
                <b>{stream.time}</b>
                <span>{stream.confidence}</span>
              </div>
              <ul>
                {stream.subthreads.map((item) => <li key={item}>{item}</li>)}
              </ul>
            </article>
          ))}
        </div>
      </section>

      <section className="public-two-column">
        <article className="public-section">
          <div className="section-head">
            <h2>Episode Chain</h2>
            <span>semantic sequence</span>
          </div>
          <div className="episode-chain">
            {timeline.map(([phase, title, detail]) => (
              <div key={`${phase}-${title}`} className="episode-step">
                <span>{phase}</span>
                <div>
                  <h3>{title}</h3>
                  <p>{detail}</p>
                </div>
              </div>
            ))}
          </div>
        </article>

        <article className="public-section">
          <div className="section-head">
            <h2>Decision Ledger</h2>
            <span>what changed</span>
          </div>
          <ol className="decision-list">
            {decisions.map((decision) => <li key={decision}>{decision}</li>)}
          </ol>
        </article>
      </section>

      <section className="public-section">
        <div className="section-head">
          <h2>Weak Signals</h2>
          <span>next improvements</span>
        </div>
        <div className="signal-grid">
          {weakSignals.map((signal) => <p key={signal}>{signal}</p>)}
        </div>
      </section>

      <section className="public-section">
        <div className="section-head">
          <h2>Music Influence</h2>
          <span>preference + productivity aftermath</span>
        </div>
        <div className="signal-grid">
          {musicSignals.map((signal) => (
            <article key={signal.title}>
              <h3>{signal.title}</h3>
              <p>{signal.detail}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="public-section">
        <div className="section-head">
          <h2>Attention Switch Model</h2>
          <span>attention, not window focus</span>
        </div>
        <div className="attention-switch-list">
          {attentionSwitches.map((item) => (
            <article key={item.type}>
              <div>
                <h3>{item.type}</h3>
                <p>{item.signal}</p>
              </div>
              <p>{item.meaning}</p>
              <small>{item.measure}</small>
            </article>
          ))}
        </div>
      </section>

      <section className="public-section research-strip">
        {researchSources.map(([title, detail]) => (
          <article key={title}>
            <h3>{title}</h3>
            <p>{detail}</p>
          </article>
        ))}
      </section>
    </main>
  );
}

function SnapshotState({ snapshot, children }: { snapshot?: DayDashboardSnapshot; children: (snapshot: DayDashboardSnapshot) => React.ReactNode }) {
  if (!snapshot) return <div className="empty">Нет snapshot. Проверь, запущен ли Observer Core.</div>;
  return children(snapshot);
}

function TodayPage() {
  const { data, isLoading, error } = useSnapshot();
  if (isLoading) return <div className="empty">Собираю день…</div>;
  if (error) return <div className="empty">Core недоступен или сессия истекла.</div>;
  return (
    <SnapshotState snapshot={data}>
      {(snapshot) => (
        <>
          <MetricStrip snapshot={snapshot} />
          <DayOverview snapshot={snapshot} />
          <section className="two-column">
            <TimelineList segments={snapshot.timelineSegments} />
            <ThreadBreakdown snapshot={snapshot} />
          </section>
        </>
      )}
    </SnapshotState>
  );
}

function MetricStrip({ snapshot }: { snapshot: DayDashboardSnapshot }) {
  const metrics = [
    ["Observed", snapshot.totals.observedSeconds],
    ["Active", snapshot.totals.activeSeconds],
    ["Assigned", snapshot.totals.assignedSeconds],
    ["Unassigned", snapshot.totals.unassignedSeconds],
    ["Sensor gaps", snapshot.totals.sensorGapSeconds]
  ];
  return (
    <section className="metric-strip" aria-label="Day metrics">
      {metrics.map(([label, value]) => (
        <div className="metric" key={String(label)}>
          <span>{label}</span>
          <strong>{fmtDuration(Number(value))}</strong>
        </div>
      ))}
      <div className="metric">
        <span>Coverage</span>
        <strong>{Math.round(snapshot.totals.coverage * 100)}%</strong>
      </div>
    </section>
  );
}

function DayOverview({ snapshot }: { snapshot: DayDashboardSnapshot }) {
  const total = Math.max(1, snapshot.totals.attributableSeconds);
  return (
    <section className="overview" aria-label="Day overview">
      <div className="overview-track">
        {snapshot.timelineSegments.map((segment) => (
          <span
            key={segment.id}
            className={`overview-segment ${segment.state}`}
            style={{ flexGrow: Math.max(1, segment.activeSeconds / total * 100), background: threadColor(segment.threadId ?? "unassigned") }}
            title={`${fmtTime(segment.start)}–${fmtTime(segment.end)} · ${segment.threadName} · ${Math.round(segment.confidence * 100)}%`}
          />
        ))}
      </div>
      {!snapshot.valid && <p className="warning">Snapshot invariant issue: {snapshot.invariantErrors.join("; ")}</p>}
    </section>
  );
}

function TimelineList({ segments }: { segments: TimelineSegment[] }) {
  return (
    <section className="panel">
      <div className="section-head">
        <h2>Detailed timeline</h2>
        <span>{segments.length} segments</span>
      </div>
      <div className="timeline-list">
        {segments.length === 0 && <p className="muted">No context slices yet. Core needs more episode assignments.</p>}
        {segments.map((segment) => (
          <article className="timeline-item" key={segment.id}>
            <time>{fmtTime(segment.start)}–{fmtTime(segment.end)}</time>
            <div>
              <h3>{segment.threadName}</h3>
              <p>{segment.summary}</p>
              <small>{segment.applications.join(" · ") || "no app"} · {segment.activityKind} · confidence {Math.round(segment.confidence * 100)}%</small>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}

function ThreadBreakdown({ snapshot }: { snapshot: DayDashboardSnapshot }) {
  const max = Math.max(...snapshot.threadSummaries.map((thread) => thread.activeSeconds), snapshot.totals.unassignedSeconds, 1);
  return (
    <section className="panel">
      <div className="section-head">
        <h2>Activity threads</h2>
        <span>Review-first</span>
      </div>
      <div className="bars">
        {snapshot.threadSummaries.map((thread) => <ThreadBar key={thread.id} thread={thread} max={max} />)}
        <div className="bar-row">
          <span>Unassigned</span>
          <div className="bar"><i style={{ width: `${snapshot.totals.unassignedSeconds / max * 100}%`, background: "var(--unassigned)" }} /></div>
          <b>{fmtDuration(snapshot.totals.unassignedSeconds)}</b>
        </div>
      </div>
      <div className="review-callout">
        <b>{snapshot.reviewSummary.total}</b>
        <span>items need review</span>
      </div>
    </section>
  );
}

function ThreadBar({ thread, max }: { thread: ThreadSummary; max: number }) {
  return (
    <div className="bar-row">
      <span>{thread.name}</span>
      <div className="bar"><i style={{ width: `${thread.activeSeconds / max * 100}%`, background: threadColor(thread.id) }} /></div>
      <b>{fmtDuration(thread.activeSeconds)}</b>
    </div>
  );
}

function TimelinePage() {
  const { data } = useSnapshot();
  return <SnapshotState snapshot={data}>{(snapshot) => <TimelineList segments={snapshot.timelineSegments} />}</SnapshotState>;
}

function ContextsPage() {
  const { data } = useSnapshot();
  return (
    <SnapshotState snapshot={data}>
      {(snapshot) => (
        <section className="panel">
          <h2>Contexts</h2>
          <div className="table-list">
            {snapshot.threadSummaries.map((thread) => (
              <article key={thread.id}>
                <h3>{thread.name}</h3>
                <p>{fmtDuration(thread.activeSeconds)} · {thread.episodes} episodes · {thread.applications.join(", ")}</p>
              </article>
            ))}
          </div>
        </section>
      )}
    </SnapshotState>
  );
}

function ReviewPage() {
  const { data } = useSnapshot();
  const queryClient = useQueryClient();
  const correction = useMutation({
    mutationFn: ({ kind, itemId }: { kind: string; itemId: string }) => submitCorrection(kind, { itemId }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["v1", "day"] })
  });
  return (
    <SnapshotState snapshot={data}>
      {(snapshot) => (
        <section className="panel">
          <h2>Review</h2>
          {snapshot.reviewSummary.items.length === 0 && <p className="muted">No review items for this day.</p>}
          {snapshot.reviewSummary.items.map((item) => (
            <article className="review-item" key={item.id}>
              <h3>{item.title}</h3>
              <p>{item.type} · {fmtDuration(item.affectedSeconds)} · confidence {Math.round(item.confidence * 100)}%</p>
              <div className="actions">
                <button onClick={() => correction.mutate({ kind: "same-context", itemId: item.id })}>Same context</button>
                <button onClick={() => correction.mutate({ kind: "different-context", itemId: item.id })}>Different</button>
                <button onClick={() => correction.mutate({ kind: "unassign", itemId: item.id })}>Leave unassigned</button>
              </div>
            </article>
          ))}
        </section>
      )}
    </SnapshotState>
  );
}

function CausalPage() {
  const { data } = useSnapshot();
  return <SnapshotState snapshot={data}>{(snapshot) => (
    <section className="panel">
      <h2>Causal hypotheses</h2>
      {snapshot.causalSummary.hypotheses.length === 0 && <p className="muted">No causal hypotheses in this day yet.</p>}
      {snapshot.causalSummary.hypotheses.map((hypothesis) => (
        <article className="review-item" key={hypothesis.id}>
          <h3>{hypothesis.transition}</h3>
          <p>{hypothesis.mechanism}</p>
          <small>{hypothesis.maturity} · confidence {Math.round(hypothesis.confidence * 100)}%</small>
        </article>
      ))}
    </section>
  )}</SnapshotState>;
}

function SensorsPage() {
  const { data } = useSnapshot();
  return <SnapshotState snapshot={data}>{(snapshot) => <SensorTable channels={snapshot.sensorSummary.channels} />}</SnapshotState>;
}

function SensorTable({ channels }: { channels: SensorChannel[] }) {
  return (
    <section className="panel">
      <h2>Sensors</h2>
      <div className="sensor-table">
        {channels.map((channel) => (
          <article key={channel.id}>
            <h3>{channel.name}</h3>
            <p>{channel.status} · {channel.events} events · coverage {Math.round(channel.coverage * 100)}%</p>
            <small>Last event: {channel.lastEventAt ? fmtTime(channel.lastEventAt) : "none"}</small>
          </article>
        ))}
      </div>
    </section>
  );
}

function ReadinessPage() {
  const { data } = useSnapshot();
  return <SnapshotState snapshot={data}>{(snapshot) => (
    <section className="panel">
      <h2>Readiness</h2>
      <p className={`badge ${snapshot.readinessSummary.status}`}>{snapshot.readinessSummary.status}</p>
      {snapshot.readinessSummary.blockers.map((blocker) => <p key={blocker} className="muted">{blocker}</p>)}
    </section>
  )}</SnapshotState>;
}

function ReportPage() {
  const [date] = useSelectedDate();
  const report = useQuery({ queryKey: ["v1", "report", date], queryFn: () => getDailyMarkdown(date) });
  return (
    <section className="panel">
      <div className="section-head">
        <h2>Daily report</h2>
        <button onClick={() => report.data && navigator.clipboard.writeText(report.data)}>Copy Markdown</button>
      </div>
      <pre className="markdown">{report.data ?? "Loading report…"}</pre>
    </section>
  );
}

function threadColor(id: string) {
  const colors = ["--thread-01", "--thread-02", "--thread-03", "--thread-04", "--thread-05", "--thread-06", "--thread-07", "--thread-08", "--thread-09", "--thread-10", "--thread-11", "--thread-12"];
  let hash = 0;
  for (const char of id) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return `var(${colors[hash % colors.length]})`;
}

const router = createBrowserRouter(
  [{ path: "*", element: <AuthGate><AppShell /></AuthGate> }],
  { basename: import.meta.env.BASE_URL === "/" ? undefined : import.meta.env.BASE_URL.replace(/\/$/, "") }
);

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      {publicDashboardMode ? <PublicAccessGate /> : <RouterProvider router={router} />}
    </QueryClientProvider>
  </React.StrictMode>
);
