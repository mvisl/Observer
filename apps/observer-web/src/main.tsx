import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { NavLink, RouterProvider, createBrowserRouter, useLocation, useSearchParams } from "react-router-dom";
import { getDailyMarkdown, getDaySnapshot, getSession, pairDevice, submitCorrection } from "./api";
import type { ArtifactRelation, ArtifactRole, DayDashboardSnapshot, SensorChannel, ThreadSummary, TimelineSegment } from "./types";
import "./styles.css";

const queryClient = new QueryClient();
const publicDashboardMode = import.meta.env.VITE_OBSERVER_PUBLIC_DASHBOARD === "1" || window.location.hostname.endsWith("github.io");
const publicAccessCode = "2501";
const publicAccessStorageKey = "observer_public_access_v1";
const publicAccessStorageValue = "pin-2501-ok";

function hasTrustedPublicAccess() {
  return (
    localStorage.getItem(publicAccessStorageKey) === publicAccessStorageValue ||
    sessionStorage.getItem("observer_public_access") === "ok"
  );
}

function rememberTrustedPublicAccess() {
  localStorage.setItem(publicAccessStorageKey, publicAccessStorageValue);
  sessionStorage.setItem("observer_public_access", "ok");
}

function clearTrustedPublicAccess() {
  localStorage.removeItem(publicAccessStorageKey);
  sessionStorage.removeItem("observer_public_access");
}

function todayString() {
  return localDateString();
}

function localDateString(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(date);
  const value = (type: string) => parts.find((part) => part.type === type)?.value ?? "00";
  return `${value("year")}-${value("month")}-${value("day")}`;
}

function fmtDuration(seconds: number) {
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}м`;
  return `${Math.floor(minutes / 60)}ч ${minutes % 60}м`;
}

function fmtMinutes(minutes: number) {
  const safeMinutes = Math.max(0, Math.round(minutes));
  const hours = Math.floor(safeMinutes / 60);
  const rest = safeMinutes % 60;
  return `${hours}:${String(rest).padStart(2, "0")}`;
}

function pluralRu(count: number, one: string, few: string, many: string) {
  const mod10 = count % 10;
  const mod100 = count % 100;
  if (mod10 === 1 && mod100 !== 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

function daysBetweenInclusive(startDate: string, endDate: string) {
  const start = new Date(`${startDate}T00:00:00`);
  const end = new Date(`${endDate}T00:00:00`);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return 1;
  const first = Math.min(start.getTime(), end.getTime());
  const last = Math.max(start.getTime(), end.getTime());
  return Math.max(1, Math.round((last - first) / 86_400_000) + 1);
}

function fmtTime(value?: string) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("ru", { hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

function formatSnapshotDay(date: string) {
  const today = localDateString();
  const yesterday = localDateString(new Date(Date.now() - 24 * 60 * 60 * 1000));
  const day = new Date(`${date}T12:00:00`);
  const words = new Intl.DateTimeFormat("ru", { weekday: "long", day: "numeric", month: "long" }).format(day);
  if (date === today) return `сегодня, ${words.replace(/^\S+,\s*/, "")}`;
  if (date === yesterday) return `вчера, ${words.replace(/^\S+,\s*/, "")}`;
  return words;
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

function shiftLocalDate(date: string, offsetDays: number) {
  const next = new Date(`${date}T12:00:00`);
  next.setDate(next.getDate() + offsetDays);
  return localDateString(next);
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
          <div className="date-navigation" aria-label="Dashboard date">
            <button className="icon-button" title="Previous day" aria-label="Previous day" onClick={() => setDate(shiftLocalDate(date, -1))}>‹</button>
            <label className="date-picker">
              Date
              <input type="date" value={date} onChange={(event) => setDate(event.target.value)} />
            </label>
            <button className="icon-button" title="Next day" aria-label="Next day" onClick={() => setDate(shiftLocalDate(date, 1))}>›</button>
          </div>
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
    () => hasTrustedPublicAccess() ? "allowed" : "idle"
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
      rememberTrustedPublicAccess();
      setStatus("allowed");
      setMessage("");
    } else {
      clearTrustedPublicAccess();
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


type PublicNodeKind = "root" | "stream" | "branch" | "intention" | "subtask";
type PublicFamily = "work" | "libertex" | "observer" | "personal" | "neutral";

type PublicNode = {
  id: string;
  name: string;
  minutes: number;
  kind: PublicNodeKind;
  family?: PublicFamily;
  question?: string;
  decisions?: number;
  unresolved?: number;
  evidenceKinds?: string[];
  status?: "neutral" | "warning";
  episodes?: PublicEpisode[];
  children?: PublicNode[];
};

type PublicEpisode = {
  id: string;
  nodeId: string;
  start: string;
  end: string;
  startMinute: number;
  endMinute: number;
  label: string;
};

type PublicArtifactRelation = ArtifactRelation & {
  nodeIds: string[];
};

const artifactRoleOrder: ArtifactRole[] = [
  "primary_artifact",
  "current_result",
  "decision_input",
  "communication",
  "implementation",
  "reference",
  "previous_version"
];

const artifactRoleLabel: Record<ArtifactRole, string> = {
  primary_artifact: "Главный артефакт",
  current_result: "Текущий результат",
  decision_input: "Вход для решения",
  communication: "Коммуникация",
  implementation: "Реализация",
  reference: "Справка",
  previous_version: "Предыдущая версия"
};

const publicReportDate = "2026-07-15";
const publicReportGeneratedAt = "2026-07-15T18:03:00+02:00";
// This is deliberately visible in the DOM so GitHub Pages clients receive a
// fresh asset when a stale static report rule is corrected.
const publicDashboardBuild = "2026-07-17-temporal-hygiene";
const publicDayStartMinute = 9 * 60;
const publicDayEndMinute = 21 * 60 + 6;

function minuteOfDay(value: string) {
  const [hours, minutes] = value.split(":").map(Number);
  return hours * 60 + minutes;
}

function fixtureEpisode(id: string, nodeId: string, start: string, end: string, label: string): PublicEpisode {
  return { id, nodeId, start, end, startMinute: minuteOfDay(start), endMinute: minuteOfDay(end), label };
}

function episodeMinutes(episodes: PublicEpisode[]) {
  return episodes.reduce((sum, episode) => sum + Math.max(0, episode.endMinute - episode.startMinute), 0);
}

function hydratePublicTree(node: PublicNode, inheritedFamily: PublicFamily = "neutral"): PublicNode {
  const family = node.family ?? inheritedFamily;
  const children = node.children?.map((child) => hydratePublicTree(child, family));
  const episodes = node.episodes ?? children?.flatMap((child) => child.episodes ?? []) ?? [];
  return { ...node, family, children, episodes };
}

function publicDashboardTree() {
  const andreyFeedback = fixtureEpisode("ep-andrey-feedback", "subtask-andrey-feedback", "09:00", "09:39", "Feedback -> decision");
  const dividends = fixtureEpisode("ep-dividends", "subtask-dividends", "09:39", "10:53", "Upcoming dividends logic");
  const cardHierarchy = fixtureEpisode("ep-card-hierarchy", "subtask-card-hierarchy", "10:53", "11:56", "Card hierarchy");
  const figmaExecution = fixtureEpisode("ep-figma-execution", "subtask-figma-execution", "11:56", "13:49", "Figma execution");
  const nebiusPrompts = fixtureEpisode("ep-nebius-prompts", "subtask-nebius-prompts", "13:49", "14:17", "Prompt candidates");
  const nebiusCriterion = fixtureEpisode("ep-nebius-criterion", "subtask-nebius-criterion", "14:17", "14:39", "Visual criterion");
  const nebiusReaction = fixtureEpisode("ep-nebius-reaction", "subtask-nebius-reaction", "14:39", "14:55", "Reaction binding");
  const jiraTriage = fixtureEpisode("ep-jira-triage", "subtask-jira-triage", "14:55", "15:29", "Jira issue triage");
  const research = fixtureEpisode("ep-research", "subtask-research", "15:29", "16:11", "Research for decision");
  const followup = fixtureEpisode("ep-followup", "subtask-followup", "16:11", "16:35", "Communication follow-up");
  const publicDashboard = [
    fixtureEpisode("ep-public-dashboard-a", "subtask-public-dashboard", "16:35", "17:00", "Dashboard structure"),
    fixtureEpisode("ep-public-dashboard-b", "subtask-public-dashboard", "17:56", "18:39", "Dashboard implementation")
  ];
  const personalCoordination = fixtureEpisode("ep-personal-coordination", "subtask-personal-coordination", "17:00", "17:56", "Personal coordination");
  const pillQuality = fixtureEpisode("ep-pill-quality", "subtask-pill-quality", "18:39", "19:51", "Pill quality");
  const reportingModel = fixtureEpisode("ep-reporting-model", "subtask-reporting-model", "19:51", "21:06", "Reporting model");

  return hydratePublicTree({
    id: "day",
    name: "День",
    kind: "root",
    minutes: 726,
    children: [
      {
        id: "stream-work",
        name: "Work",
        kind: "stream",
        family: "work",
        minutes: 670,
        children: [
          {
            id: "branch-libertex",
            name: "Libertex",
            kind: "branch",
            family: "libertex",
            minutes: 455,
            children: [
              {
                id: "intention-andrey",
                name: "Фидбек Андрея -> решения по WhatToBuy",
                kind: "intention",
                minutes: 289,
                question: "Как карточкам объяснять ценность без вычислений со стороны пользователя?",
                decisions: 5,
                unresolved: 1,
                evidenceKinds: ["чат", "Figma", "AI"],
                children: [
                  { id: "subtask-andrey-feedback", name: "Фидбек -> решение", kind: "subtask", minutes: 39, evidenceKinds: ["чат"], episodes: [andreyFeedback] },
                  { id: "subtask-dividends", name: "Dividends logic", kind: "subtask", minutes: 74, evidenceKinds: ["чат", "Figma"], episodes: [dividends] },
                  { id: "subtask-card-hierarchy", name: "Card hierarchy", kind: "subtask", minutes: 63, evidenceKinds: ["чат", "Figma"], episodes: [cardHierarchy] },
                  { id: "subtask-figma-execution", name: "Figma execution", kind: "subtask", minutes: 113, evidenceKinds: ["Figma"], episodes: [figmaExecution] }
                ]
              },
              {
                id: "intention-nebius",
                name: "Nebius cover visual direction",
                kind: "intention",
                minutes: 66,
                question: "Какой образ Nebius не превращается в generic neon cloud?",
                decisions: 2,
                unresolved: 1,
                evidenceKinds: ["Figma", "AI", "реакция"],
                children: [
                  { id: "subtask-nebius-prompts", name: "Prompt candidates", kind: "subtask", minutes: 28, evidenceKinds: ["AI"], episodes: [nebiusPrompts] },
                  { id: "subtask-nebius-criterion", name: "Visual criterion", kind: "subtask", minutes: 22, evidenceKinds: ["Figma"], episodes: [nebiusCriterion] },
                  { id: "subtask-nebius-reaction", name: "Reaction binding", kind: "subtask", minutes: 16, evidenceKinds: ["камера", "текст"], episodes: [nebiusReaction] }
                ]
              },
              {
                id: "intention-backlog",
                name: "Backlog / Jira prioritization",
                kind: "intention",
                minutes: 100,
                question: "Какие issue требуют решения сейчас, а какие просто шумят?",
                decisions: 3,
                unresolved: 2,
                evidenceKinds: ["Jira", "чат", "web"],
                children: [
                  { id: "subtask-jira-triage", name: "Jira issue triage", kind: "subtask", minutes: 34, evidenceKinds: ["Jira"], episodes: [jiraTriage] },
                  { id: "subtask-research", name: "Research for decision", kind: "subtask", minutes: 42, evidenceKinds: ["web"], episodes: [research] },
                  { id: "subtask-followup", name: "Communication follow-up", kind: "subtask", minutes: 24, evidenceKinds: ["чат"], episodes: [followup] }
                ]
              }
            ]
          },
          {
            id: "branch-observer",
            name: "Observer",
            kind: "branch",
            family: "observer",
            minutes: 215,
            children: [
              {
                id: "intention-observer-brain",
                name: "Brain / dashboard",
                kind: "intention",
                minutes: 215,
                question: "Как объяснять день намерениями, evidence и outcome вместо окон?",
                decisions: 6,
                unresolved: 3,
                evidenceKinds: ["Codex", "dashboard", "пилюля"],
                children: [
                  { id: "subtask-public-dashboard", name: "Public dashboard", kind: "subtask", minutes: 68, evidenceKinds: ["GitHub Pages"], episodes: publicDashboard },
                  { id: "subtask-pill-quality", name: "Pill quality", kind: "subtask", minutes: 72, evidenceKinds: ["пилюля"], episodes: [pillQuality] },
                  { id: "subtask-reporting-model", name: "Reporting model", kind: "subtask", minutes: 75, evidenceKinds: ["отчёт"], episodes: [reportingModel] }
                ]
              }
            ]
          }
        ]
      },
      {
        id: "stream-personal",
        name: "Личное",
        kind: "stream",
        family: "personal",
        minutes: 56,
        children: [
          {
            id: "branch-communication",
            name: "Общение",
            kind: "branch",
            minutes: 56,
            children: [
              {
                id: "intention-personal-coordination",
                name: "Личная координация",
                kind: "intention",
                minutes: 56,
                evidenceKinds: ["сообщения"],
                children: [
                  { id: "subtask-personal-coordination", name: "Личная координация", kind: "subtask", minutes: 56, evidenceKinds: ["сообщения"], episodes: [personalCoordination] }
                ]
              }
            ]
          }
        ]
      }
    ]
  });
}

function publicArtifactRelations(): PublicArtifactRelation[] {
  return [
    {
      id: "artifact-jira-whattobuy",
      taskId: "intention-andrey",
      nodeIds: ["stream-work", "branch-libertex", "intention-andrey", "subtask-andrey-feedback", "subtask-dividends", "subtask-card-hierarchy", "subtask-figma-execution"],
      role: "primary_artifact",
      artifactKind: "jira_issue",
      sourceIcon: "Jira",
      title: "PD-6455 — Contextual bottom navigation for MT users",
      roleSummary: "Рабочий якорь: задача задаёт предмет обсуждения и критерий готового решения.",
      directLink: "https://jira.fxclub.org/browse/PD-6455",
      lastUsedAt: "2026-07-15T15:29:00+02:00",
      relatedEpisodeCount: 4,
      confidence: 0.98,
      aliases: ["WhatToBuy", "задача из Jira"],
      evidenceEventIds: ["ep-andrey-feedback", "ep-jira-triage"]
    },
    {
      id: "artifact-figma-whattobuy",
      taskId: "intention-andrey",
      nodeIds: ["stream-work", "branch-libertex", "intention-andrey", "subtask-dividends", "subtask-card-hierarchy", "subtask-figma-execution"],
      role: "current_result",
      artifactKind: "figma_file",
      sourceIcon: "Figma",
      title: "WhatToBuy — market card system",
      roleSummary: "Текущий макет, где проверялись buy-by date, иерархия карточек и видимые сигналы.",
      directLink: "https://www.figma.com/",
      lastUsedAt: "2026-07-15T13:49:00+02:00",
      relatedEpisodeCount: 3,
      confidence: 0.94,
      aliases: ["Figma dividend section", "выбранная секция"],
      evidenceEventIds: ["ep-dividends", "ep-card-hierarchy", "ep-figma-execution"]
    },
    {
      id: "artifact-chat-andrey",
      taskId: "intention-andrey",
      nodeIds: ["stream-work", "branch-libertex", "intention-andrey", "subtask-andrey-feedback"],
      role: "communication",
      artifactKind: "chat_thread",
      sourceIcon: "Chat",
      title: "Обсуждение решения с Андреем",
      roleSummary: "Источник обратной связи, из которого были выделены требования к карточкам и приоритетам.",
      directLink: "https://mail.google.com/",
      lastUsedAt: "2026-07-15T09:39:00+02:00",
      relatedEpisodeCount: 1,
      confidence: 0.88,
      aliases: ["Andrey feedback"],
      evidenceEventIds: ["ep-andrey-feedback"]
    },
    {
      id: "artifact-ai-decision",
      taskId: "intention-andrey",
      nodeIds: ["stream-work", "branch-libertex", "intention-andrey", "subtask-card-hierarchy", "subtask-figma-execution"],
      role: "decision_input",
      artifactKind: "ai_conversation",
      sourceIcon: "AI",
      title: "Проверка формулировок и приоритетов",
      roleSummary: "Использовалась, чтобы проверить объяснение ценности карточек до применения в макете.",
      directLink: "https://chatgpt.com/",
      lastUsedAt: "2026-07-15T12:31:00+02:00",
      relatedEpisodeCount: 2,
      confidence: 0.72,
      aliases: [],
      evidenceEventIds: ["ep-card-hierarchy", "ep-figma-execution"]
    },
    {
      id: "artifact-repo-observer",
      taskId: "intention-observer-brain",
      nodeIds: ["stream-work", "branch-observer", "intention-observer-brain", "subtask-public-dashboard", "subtask-pill-quality", "subtask-reporting-model"],
      role: "primary_artifact",
      artifactKind: "repository",
      sourceIcon: "Code",
      title: "Observer repository",
      roleSummary: "Главный рабочий материал для изменений мозга, пилюли и отчётного интерфейса.",
      directLink: "https://github.com/mvisl/Observer",
      lastUsedAt: "2026-07-15T21:06:00+02:00",
      relatedEpisodeCount: 3,
      confidence: 0.97,
      aliases: ["Observer app", "dashboard code"],
      evidenceEventIds: ["ep-public-dashboard-a", "ep-public-dashboard-b", "ep-reporting-model"]
    },
    {
      id: "artifact-pages-dashboard",
      taskId: "intention-observer-brain",
      nodeIds: ["stream-work", "branch-observer", "intention-observer-brain", "subtask-public-dashboard"],
      role: "current_result",
      artifactKind: "browser_page",
      sourceIcon: "Web",
      title: "Observer dashboard preview",
      roleSummary: "Текущий внешний результат, на котором проверялись карта дня и читаемость иерархии.",
      directLink: "https://mvisl.github.io/Observer/",
      lastUsedAt: "2026-07-15T18:39:00+02:00",
      relatedEpisodeCount: 2,
      confidence: 0.91,
      aliases: ["GitHub Pages dashboard"],
      evidenceEventIds: ["ep-public-dashboard-a", "ep-public-dashboard-b"]
    },
    {
      id: "artifact-wife-chat",
      taskId: "intention-personal-coordination",
      nodeIds: ["stream-personal", "branch-communication", "intention-personal-coordination", "subtask-personal-coordination"],
      role: "communication",
      artifactKind: "chat_thread",
      sourceIcon: "Chat",
      title: "Личная координация",
      roleSummary: "Личная переписка, отделённая от рабочих веток и не используемая для рабочих выводов.",
      directLink: "https://web.whatsapp.com/",
      lastUsedAt: "2026-07-15T17:56:00+02:00",
      relatedEpisodeCount: 1,
      confidence: 0.84,
      aliases: [],
      evidenceEventIds: ["ep-personal-coordination"]
    }
  ];
}

function artifactRelationsForNode(
  node: PublicNode,
  relations: PublicArtifactRelation[],
  titleOverrides: Record<string, string>,
  roleOverrides: Record<string, ArtifactRole>,
  hiddenIds: Set<string>
) {
  return relations
    .filter((relation) => relation.nodeIds.includes(node.id) && !hiddenIds.has(relation.id))
    .map((relation) => ({ ...relation, title: titleOverrides[relation.id] ?? relation.title, role: roleOverrides[relation.id] ?? relation.role }))
    .sort((left, right) => artifactRoleOrder.indexOf(left.role) - artifactRoleOrder.indexOf(right.role) || right.lastUsedAt.localeCompare(left.lastUsedAt));
}

function flattenPublicNodes(node: PublicNode): PublicNode[] {
  return [node, ...(node.children ?? []).flatMap(flattenPublicNodes)];
}

function findPublicNode(root: PublicNode, id?: string | null): PublicNode | undefined {
  if (!id) return undefined;
  return flattenPublicNodes(root).find((node) => node.id === id);
}

function publicNodePath(root: PublicNode, targetId: string): PublicNode[] {
  const walk = (node: PublicNode, path: PublicNode[]): PublicNode[] | undefined => {
    const next = [...path, node];
    if (node.id === targetId) return next;
    for (const child of node.children ?? []) {
      const found = walk(child, next);
      if (found) return found;
    }
    return undefined;
  };
  return walk(root, []) ?? [root];
}

function formatDateWords(startDate: string, endDate: string, rangePreset: "today" | "7d" | "custom") {
  const formatter = new Intl.DateTimeFormat("ru", { day: "numeric", month: "long" });
  const start = new Date(`${startDate}T12:00:00`);
  const end = new Date(`${endDate}T12:00:00`);
  if (startDate === endDate) return rangePreset === "today" ? `сегодня, ${formatter.format(end)}` : formatter.format(end);
  return rangePreset === "7d" ? `неделя ${formatter.format(start)} - ${formatter.format(end)}` : `${formatter.format(start)} - ${formatter.format(end)}`;
}

function PublicDashboardShell() {
  const today = localDateString();
  const sevenDaysAgo = localDateString(new Date(Date.now() - 6 * 24 * 60 * 60 * 1000));
  const [rangePreset, setRangePreset] = useState<"today" | "7d" | "custom">("today");
  const [startDate, setStartDate] = useState(today);
  const [endDate, setEndDate] = useState(today);
  const [selectedNodeId, setSelectedNodeId] = useState("intention-andrey");
  const [selectedEpisodeId, setSelectedEpisodeId] = useState<string | null>(null);
  const [expandedIds, setExpandedIds] = useState<string[]>(["intention-andrey"]);
  const [openDrawer, setOpenDrawer] = useState<"decisions" | "evidence" | "digest" | null>(null);
  const [openDigestKey, setOpenDigestKey] = useState<string | null>(null);
  const [showAllArtifacts, setShowAllArtifacts] = useState(false);
  const [artifactDiagnostics, setArtifactDiagnostics] = useState(false);
  const [artifactTitles, setArtifactTitles] = useState<Record<string, string>>({});
  const [artifactRoles, setArtifactRoles] = useState<Record<string, ArtifactRole>>({});
  const [hiddenArtifactIds, setHiddenArtifactIds] = useState<Set<string>>(() => new Set());
  const [editingArtifactId, setEditingArtifactId] = useState<string | null>(null);
  const [editingArtifactTitle, setEditingArtifactTitle] = useState("");

  function applyPreset(next: "today" | "7d" | "custom") {
    setRangePreset(next);
    if (next === "today") {
      setStartDate(today);
      setEndDate(today);
    }
    if (next === "7d") {
      setStartDate(sevenDaysAgo);
      setEndDate(today);
    }
  }

  const rangeDays = daysBetweenInclusive(startDate, endDate);
  // A static report is valid only for its own calendar day. It must never
  // masquerade as a live "Today" view or as a seven-day aggregate.
  const hasSnapshot = startDate === publicReportDate && endDate === publicReportDate;
  const root = useMemo(publicDashboardTree, []);
  const artifactRelations = useMemo(publicArtifactRelations, []);

  const allNodes = useMemo(() => flattenPublicNodes(root), [root]);
  const selectedNode = findPublicNode(root, selectedNodeId) ?? findPublicNode(root, "intention-andrey") ?? root;
  const selectedPath = publicNodePath(root, selectedNode.id).filter((node) => node.kind !== "root");
  const detailChildren = selectedNode.children ?? [];
  const allEpisodes = useMemo(() => Array.from(new Map(allNodes.flatMap((node) => node.episodes ?? []).map((episode) => [episode.id, episode])).values()), [allNodes]);
  const selectedEpisode = allEpisodes.find((episode) => episode.id === selectedEpisodeId) ?? null;
  const isMultiDay = startDate !== endDate;
  const dateColumns = Array.from({ length: Math.max(1, Math.min(14, rangeDays)) }, (_, index) => {
    const date = new Date(`${startDate}T12:00:00`);
    date.setDate(date.getDate() + index);
    return date;
  });
  const sections = (root.children ?? []).flatMap((stream) => (stream.children ?? []).map((branch) => ({ stream, branch })));
  const dayIntentions = allNodes.filter((node) => node.kind === "intention");
  const rowEpisodes = (node: PublicNode) => node.episodes ?? [];
  const mergeCloseEpisodes = (items: PublicEpisode[]) => items
    .slice()
    .sort((a, b) => a.startMinute - b.startMinute)
    .reduce<Array<{ episodes: PublicEpisode[]; startMinute: number; endMinute: number }>>((groups, episode) => {
      const previous = groups.at(-1);
      if (previous && ((episode.startMinute - previous.endMinute) / (publicDayEndMinute - publicDayStartMinute)) * 100 < 0.4) {
        previous.episodes.push(episode);
        previous.endMinute = Math.max(previous.endMinute, episode.endMinute);
      } else {
        groups.push({ episodes: [episode], startMinute: episode.startMinute, endMinute: episode.endMinute });
      }
      return groups;
    }, []);
  const matrixMinutes = (node: PublicNode, dayIndex: number) => {
    const date = localDateString(dateColumns[dayIndex]);
    return date === publicReportDate ? node.minutes : 0;
  };
  const timingIssue = (node: PublicNode) => {
    const recorded = episodeMinutes(rowEpisodes(node));
    return node.minutes > 0 && (recorded === 0 || Math.abs(recorded - node.minutes) / node.minutes > 0.05);
  };
  const timingErrors = allNodes.filter((node) => node.kind !== "root" && timingIssue(node));
  const selectedDetailMinutes = Math.max(1, selectedNode.minutes);
  const selectedArtifacts = artifactRelationsForNode(selectedNode, artifactRelations, artifactTitles, artifactRoles, hiddenArtifactIds);
  const displayedArtifacts = showAllArtifacts ? selectedArtifacts : selectedArtifacts.slice(0, 6);
  const dateWords = formatDateWords(startDate, endDate, rangePreset);
  const generatedAt = new Date(publicReportGeneratedAt);
  const staleSnapshot = Date.now() - generatedAt.getTime() > 26 * 60 * 60 * 1000;
  const snapshotNotice = hasSnapshot
    ? `данные сформированы ${formatSnapshotDay(publicReportDate)} в ${fmtTime(publicReportGeneratedAt)} · наблюдалось ${fmtMinutes(root.minutes)} · coverage 94%`
    : "живые данные не публикуются в статической витрине";
  const digest = [
    { status: "warning", short: "2 плотные петли: WhatToBuy и Observer дают основную нагрузку", full: "Нагрузка идёт не от Chrome/Figma, а от повторного уточнения критериев: что считать хорошим результатом и как это доказать артефактом." },
    { status: "neutral", short: "Andrey chat является evidence внутри Libertex → WhatToBuy", full: "Коммуникация с Андреем не отдельный поток. Это нижний слой задачи WhatToBuy: Source → Decide → Apply в Figma." },
    { status: "warning", short: "Nebius cover: злость привязана к провалу визуального критерия", full: "Повторные генерации полезны только если система хранит, какой именно критерий не выполнен: спокойная дата-инфраструктура вместо generic neon cloud." },
    { status: "neutral", short: "Музыка пока кандидат влияния, нужен aftermath по темпу и фокусу", full: "Повтор песни — сильный сигнал предпочтения, но влияние на продуктивность нужно мерить по следующему устойчивому блоку работы." }
  ];
  const decisionLedger = [
    "WhatToBuy: показывать buy-by date вместо сырой ex-dividend даты.",
    "Andrey feedback входит в задачу Libertex / WhatToBuy, а не в общий communication bucket.",
    "В отчётах приложения не являются верхним уровнем: они только evidence.",
    "Nebius: фиксировать критерий провала генерации, а не просто факт раздражения.",
    "Пилюля не должна публиковать санитарку; лучше sensing/stale, чем ложный insight."
  ];

  useEffect(() => {
    const hydrateFromHash = () => {
      const params = new URLSearchParams(window.location.hash.replace(/^#/, ""));
      const node = params.get("node");
      const episode = params.get("episode");
      const expanded = params.get("expanded");
      const range = params.get("range");
      const start = params.get("start");
      const end = params.get("end");
      if (node && allNodes.some((item) => item.id === node)) setSelectedNodeId(node);
      if (episode && allEpisodes.some((item) => item.id === episode)) setSelectedEpisodeId(episode);
      if (expanded) setExpandedIds(expanded.split(",").filter((id) => allNodes.some((item) => item.id === id)));
      if (range === "day" || range === "today") setRangePreset("today");
      if (range === "7d" || range === "custom") setRangePreset(range);
      if (start) setStartDate(start);
      if (end) setEndDate(end);
    };
    hydrateFromHash();
    window.addEventListener("hashchange", hydrateFromHash);
    return () => window.removeEventListener("hashchange", hydrateFromHash);
    // Node ids are structural and fixed for the loaded snapshot. Re-running this
    // hydration whenever range scaling rebuilds the tree would overwrite a just
    // selected date range with the previous URL state.
  }, []);

  useEffect(() => {
    if (timingErrors.length) {
      console.error("Observer dashboard timing invariant failed", timingErrors.map((node) => ({ id: node.id, minutes: node.minutes, episodeMinutes: episodeMinutes(rowEpisodes(node)) })));
    }
  }, [timingErrors]);

  useEffect(() => {
    const params = new URLSearchParams();
    params.set("date", endDate);
    params.set("range", rangePreset);
    params.set("start", startDate);
    params.set("end", endDate);
    params.set("node", selectedNode.id);
    if (selectedEpisodeId) params.set("episode", selectedEpisodeId);
    if (expandedIds.length) params.set("expanded", expandedIds.join(","));
    const nextHash = `#${params.toString()}`;
    if (window.location.hash !== nextHash) window.history.replaceState(null, "", nextHash);
  }, [endDate, expandedIds, rangePreset, selectedEpisodeId, selectedNode.id, startDate]);

  function selectNode(node: PublicNode) {
    setSelectedNodeId((current) => current === node.id ? "day" : node.id);
    setSelectedEpisodeId(null);
    setOpenDrawer(null);
    setShowAllArtifacts(false);
    setEditingArtifactId(null);
  }

  function setPrimaryArtifact(relation: PublicArtifactRelation) {
    setArtifactRoles((current) => {
      const next = { ...current };
      for (const candidate of selectedArtifacts) {
        if (candidate.role === "primary_artifact") next[candidate.id] = "current_result";
      }
      next[relation.id] = "primary_artifact";
      return next;
    });
  }

  function beginArtifactRename(relation: PublicArtifactRelation) {
    setEditingArtifactId(relation.id);
    setEditingArtifactTitle(relation.title);
  }

  function saveArtifactRename(relation: PublicArtifactRelation) {
    const title = editingArtifactTitle.trim();
    if (title) setArtifactTitles((current) => ({ ...current, [relation.id]: title }));
    setEditingArtifactId(null);
  }

  function unbindArtifact(relation: PublicArtifactRelation) {
    setHiddenArtifactIds((current) => new Set([...current, relation.id]));
    setEditingArtifactId(null);
  }

  function toggleExpanded(node: PublicNode) {
    setExpandedIds((current) => current.includes(node.id)
      ? current.filter((id) => id !== node.id)
      : [...current, node.id]);
  }

  function activeFamily(node: PublicNode) {
    return node.family ?? "neutral";
  }

  function renderRow(rowNode: PublicNode, nested = false, mode: "time" | "proportions" = "time") {
    const items = rowEpisodes(rowNode);
    const groups = mergeCloseEpisodes(items);
    const hasChildren = Boolean(rowNode.children?.length);
    const isExpanded = expandedIds.includes(rowNode.id);
    const rowHasIssue = timingIssue(rowNode);
    const childrenUseTime = (rowNode.children ?? []).every((child) => !timingIssue(child));
    return (
      <React.Fragment key={rowNode.id}>
        <div className={`swimlane-row ${nested ? "subtask" : ""} ${selectedNode.id === rowNode.id ? "selected" : ""} ${rowHasIssue ? "timing-issue" : ""}`}>
          <div className="swimlane-name">
            {hasChildren && <button className="lane-chevron" onClick={() => toggleExpanded(rowNode)} aria-label={isExpanded ? "Свернуть подзадачи" : "Раскрыть подзадачи"}>{isExpanded ? "⌄" : "›"}</button>}
            <button onClick={() => selectNode(rowNode)} title={rowNode.name}>{rowNode.name}</button>
            {rowHasIssue && <span className="timing-warning" title="эпизоды не размечены по времени">⚠</span>}
          </div>
          {isMultiDay ? (
            <div className="swimlane-matrix" style={{ gridTemplateColumns: `repeat(${dateColumns.length}, 1fr)` }}>
              {dateColumns.map((_, index) => {
                const minutes = matrixMinutes(rowNode, index);
                return <button key={index} className={`matrix-cell family-${activeFamily(rowNode)} ${selectedNode.id === rowNode.id ? "selected" : ""}`} style={{ opacity: minutes ? 0.38 + (minutes / Math.max(1, rowNode.minutes)) * 0.62 : 0.08 }} title={`${rowNode.name} · ${fmtMinutes(minutes)} · ${new Intl.DateTimeFormat("ru", { weekday: "long", day: "numeric" }).format(dateColumns[index])}`} onClick={() => selectNode(rowNode)} />;
              })}
            </div>
          ) : mode === "proportions" ? (
            <div className="swimlane-proportion"><i><b className={`family-${activeFamily(rowNode)}`} style={{ width: `${Math.max(3, (rowNode.minutes / Math.max(1, selectedNode.minutes)) * 100)}%` }} /></i></div>
          ) : (
            <div className="swimlane-track">
              {groups.map((group) => {
                const left = ((group.startMinute - publicDayStartMinute) / (publicDayEndMinute - publicDayStartMinute)) * 100;
                const width = Math.max(0.45, ((group.endMinute - group.startMinute) / (publicDayEndMinute - publicDayStartMinute)) * 100);
                const selected = group.episodes.some((episode) => selectedEpisodeId === episode.id);
                const firstEpisode = group.episodes[0];
                const label = group.episodes.length === 1
                  ? `${rowNode.name} · ${firstEpisode.start}-${firstEpisode.end} · ${fmtMinutes(firstEpisode.endMinute - firstEpisode.startMinute)}`
                  : `${group.episodes.length} эпизода · ${firstEpisode.start}-${group.episodes.at(-1)?.end} · ${fmtMinutes(group.endMinute - group.startMinute)}`;
                return <button key={group.episodes.map((episode) => episode.id).join("-")} className={`episode-block family-${activeFamily(rowNode)} ${selected ? "selected" : ""}`} style={{ left: `${left}%`, width: `${width}%` }} title={label} onClick={() => { setSelectedNodeId(rowNode.id); setSelectedEpisodeId(firstEpisode.id); }} />;
              })}
            </div>
          )}
          <strong>{fmtMinutes(rowNode.minutes)}</strong>
        </div>
        {isExpanded && (rowNode.children ?? []).map((child) => renderRow(child, true, childrenUseTime ? "time" : "proportions"))}
      </React.Fragment>
    );
  }

  return (
    <main className="public-shell public-dashboard-app" data-build={publicDashboardBuild}>
      <header className="public-day-header">
        <div>
          <h1>{dateWords}</h1>
          <span>{staleSnapshot ? "⚠ " : ""}{snapshotNotice}</span>
        </div>
        <div className="dashboard-controls">
          <div className="compact-range" aria-label="Reporting range">
            <button className={rangePreset === "today" ? "selected" : ""} onClick={() => applyPreset("today")}>Today</button>
            <button className={rangePreset === "7d" ? "selected" : ""} onClick={() => applyPreset("7d")}>7 days</button>
            <button className={rangePreset === "custom" ? "selected" : ""} onClick={() => applyPreset("custom")}>Custom</button>
            {rangePreset === "custom" && (
              <>
                <input type="date" value={startDate} onChange={(event) => { setRangePreset("custom"); setStartDate(event.target.value); }} />
                <input type="date" value={endDate} onChange={(event) => { setRangePreset("custom"); setEndDate(event.target.value); }} />
              </>
            )}
          </div>
        </div>
      </header>

      {hasSnapshot ? <>
      <section className="dashboard-workbench" aria-label="Карта дня">
        <div className="structure-pane swimlane-map">
          <div className="day-strip-row" aria-label="Доля дня">
            <span>доля дня</span>
            <div className="day-strip">
              {dayIntentions.map((intention) => <button key={intention.id} className={`family-${activeFamily(intention)}`} style={{ flexGrow: intention.minutes }} title={`${intention.name} · ${fmtMinutes(intention.minutes)}`} onClick={() => selectNode(intention)} />)}
            </div>
            <strong>{fmtMinutes(root.minutes)}</strong>
          </div>
          {isMultiDay ? (
            <div className="swimlane-axis matrix-axis"><span>Интенция</span><div style={{ gridTemplateColumns: `repeat(${dateColumns.length}, 1fr)` }}>{dateColumns.map((date) => <b key={date.toISOString()}>{new Intl.DateTimeFormat("ru", { weekday: "short", day: "numeric" }).format(date)}</b>)}</div><span>H:MM</span></div>
          ) : (
            <div className="swimlane-axis"><span>Интенция</span><div>{Array.from({ length: 13 }, (_, hour) => <b key={hour}>{`${String(hour + 9).padStart(2, "0")}:00`}</b>)}</div><span>H:MM</span></div>
          )}
          <div className="swimlane-time-area">
            {!isMultiDay && <div className="swimlane-gridlines" aria-hidden="true">{Array.from({ length: 13 }, (_, index) => <i key={index} style={{ left: `${(index / 12) * 100}%` }} />)}</div>}
          <div className="swimlane-sections">
            {sections.map(({ stream, branch }) => {
              const intentions = [...(branch.children ?? [])].sort((a, b) => b.minutes - a.minutes);
              return (
                <section className={`swimlane-section family-${activeFamily(branch)}`} key={branch.id}>
                  <h2>{branch.name} · {fmtMinutes(branch.minutes)}</h2>
                  {intentions.map((node) => renderRow(node))}
                </section>
              );
            })}
          </div>
          </div>
        </div>

        <div className="detail-and-inspector">
        <section className="detail-panel" aria-label="Детали">
          <div className="detail-title-row">
            <h2>{selectedNode.name}</h2>
            <strong>{fmtMinutes(selectedNode.minutes)}</strong>
          </div>
          <p className="detail-path">
            {selectedPath.map((node) => node.name).join(" / ") || "День"}{selectedNode.question ? ` · ${selectedNode.question}` : ""}
          </p>
          {selectedEpisode && (
            <p className="selected-episode">Выбранный эпизод: <b>{selectedEpisode.start}-{selectedEpisode.end}</b> · {selectedEpisode.label}</p>
          )}
          {detailChildren.length > 0 ? (
            <div className="detail-grid" role="list">
              {detailChildren.map((child) => (
                <button key={child.id} className={`detail-row family-${activeFamily(child)}`} onClick={() => selectNode(child)} role="listitem">
                  <span>{child.name}</span>
                  <i><b style={{ width: `${Math.max(3, (child.minutes / selectedDetailMinutes) * 100)}%` }} /></i>
                  <strong>{fmtMinutes(child.minutes)}</strong>
                </button>
              ))}
            </div>
          ) : (
            <div className="detail-episodes" role="list">
              {rowEpisodes(selectedNode).sort((a, b) => a.startMinute - b.startMinute).map((episode) => (
                <button key={episode.id} className={selectedEpisodeId === episode.id ? "selected" : ""} onClick={() => { setSelectedNodeId(selectedNode.id); setSelectedEpisodeId(episode.id); }} role="listitem">
                  <b>{episode.start}–{episode.end}</b><span>{fmtMinutes(episode.endMinute - episode.startMinute)}</span><em>{episode.label}</em>
                </button>
              ))}
            </div>
          )}
          {Boolean((selectedNode.decisions ?? 0) || (selectedNode.unresolved ?? 0) || selectedNode.evidenceKinds?.length) && (
            <div className="detail-footer">
              {Boolean(selectedNode.decisions) && (
                <button onClick={() => setOpenDrawer(openDrawer === "decisions" ? null : "decisions")}>
                  {selectedNode.decisions} {pluralRu(selectedNode.decisions ?? 0, "решение", "решения", "решений")}
                </button>
              )}
              {Boolean(selectedNode.unresolved) && (
                <button className="warning" onClick={() => setOpenDrawer(openDrawer === "decisions" ? null : "decisions")}>
                  {selectedNode.unresolved} {pluralRu(selectedNode.unresolved ?? 0, "нерешённое", "нерешённых", "нерешённых")}
                </button>
              )}
              {Boolean(selectedNode.evidenceKinds?.length) && (
                <button className="evidence" onClick={() => setOpenDrawer(openDrawer === "evidence" ? null : "evidence")}>evidence: {selectedNode.evidenceKinds?.join(" · ")}</button>
              )}
            </div>
          )}
          {openDrawer === "decisions" && (
            <ol className="drawer-list">
              {decisionLedger.map((decision) => <li key={decision}>{decision}</li>)}
            </ol>
          )}
          {openDrawer === "evidence" && (
            <div className="episode-chain compact-chain">
              {rowEpisodes(selectedNode).slice(0, 5).map((episode) => <p key={episode.id}><b>{episode.start}-{episode.end}</b> {episode.label}</p>)}
            </div>
          )}
        </section>
        <aside className="artifact-inspector" aria-label="Связанные материалы">
          <div className="artifact-inspector-head">
            <div>
              <p className="eyebrow">Linked artifacts</p>
              <h2>Материалы задачи</h2>
            </div>
            <button className="artifact-diagnostics-toggle" onClick={() => setArtifactDiagnostics((value) => !value)} aria-pressed={artifactDiagnostics}>
              {artifactDiagnostics ? "Скрыть IDs" : "IDs"}
            </button>
          </div>
          <p className="artifact-inspector-note">Не список вкладок: только материалы, у которых есть роль в выбранном контексте.</p>
          {displayedArtifacts.length ? (
            <div className="artifact-list">
              {displayedArtifacts.map((relation) => (
                <article className="artifact-card" key={relation.id}>
                  <div className="artifact-card-topline">
                    <span className="artifact-source" title={relation.artifactKind}>{relation.sourceIcon}</span>
                    <span className="artifact-role">{artifactRoleLabel[relation.role]}</span>
                    <span className="artifact-confidence">{Math.round(relation.confidence * 100)}%</span>
                  </div>
                  {editingArtifactId === relation.id ? (
                    <form className="artifact-rename" onSubmit={(event) => { event.preventDefault(); saveArtifactRename(relation); }}>
                      <input value={editingArtifactTitle} onChange={(event) => setEditingArtifactTitle(event.target.value)} autoFocus />
                      <button type="submit">Save</button>
                    </form>
                  ) : relation.directLink ? (
                    <a href={relation.directLink} target="_blank" rel="noreferrer" className="artifact-title">{relation.title}</a>
                  ) : <h3 className="artifact-title">{relation.title}</h3>}
                  <p>{relation.roleSummary}</p>
                  <div className="artifact-meta">
                    <span>{fmtTime(relation.lastUsedAt)}</span>
                    <span>{relation.relatedEpisodeCount} {pluralRu(relation.relatedEpisodeCount, "эпизод", "эпизода", "эпизодов")}</span>
                  </div>
                  {relation.aliases.length > 0 && <p className="artifact-aliases">Также: {relation.aliases.join(" · ")}</p>}
                  {artifactDiagnostics && <p className="artifact-evidence">evidence: {relation.evidenceEventIds.join(" · ")}</p>}
                  <div className="artifact-actions">
                    <button onClick={() => beginArtifactRename(relation)}>Переименовать</button>
                    {relation.role !== "primary_artifact" && <button onClick={() => setPrimaryArtifact(relation)}>Сделать главным</button>}
                    <button className="quiet-danger" onClick={() => unbindArtifact(relation)}>Отвязать</button>
                  </div>
                </article>
              ))}
            </div>
          ) : <p className="artifact-empty">Для выбранного контекста пока нет доказанно связанных материалов.</p>}
          {selectedArtifacts.length > 6 && (
            <button className="show-all-artifacts" onClick={() => setShowAllArtifacts((value) => !value)}>
              {showAllArtifacts ? "Скрыть лишнее" : `Показать все (${selectedArtifacts.length})`}
            </button>
          )}
        </aside>
        </div>
      </section>

      <section className="digest-row" aria-label="Сигналы дня">
        {digest.map((item) => (
          <button
            key={item.short}
            className={item.status}
            onClick={() => setOpenDigestKey(openDigestKey === item.short ? null : item.short)}
            title={item.full}
          >
            <i />
            <span>{openDigestKey === item.short ? item.full : item.short}</span>
          </button>
        ))}
      </section>

      <section className="trust-status" aria-label="Trust Pass status">
        <div>
          <p className="eyebrow">Trust Pass</p>
          <h2>Защитные механизмы установлены</h2>
        </div>
        <table>
          <thead><tr><th>Контур</th><th>Статус</th><th>Что проверяется</th></tr></thead>
          <tbody>
            <tr><td>Crash recovery</td><td>установлен</td><td>degraded-close, singleton lock, restart backoff</td></tr>
            <tr><td>Presence gate</td><td>установлен</td><td>отсутствие закрывает эпизод и исключает его из задач</td></tr>
            <tr><td>Schedule / restart</td><td>установлен</td><td>рестарт вне окна не создаёт рабочую активность</td></tr>
            <tr><td>Privacy / evidence</td><td>установлен</td><td>редакция секретов и обязательная lineage у гипотез</td></tr>
            <tr><td>3-day validation</td><td>наблюдается</td><td>нужны три полных дня без падения и дублей</td></tr>
          </tbody>
        </table>
      </section>
      </> : (
        <section className="public-empty-day" aria-label="Live dashboard">
          <p className="eyebrow">Live data stays local</p>
          <h2>Today is not replaced with an old report.</h2>
          <p>Этот экран больше не подставляет 15 июля вместо сегодняшнего дня. Открой локальный Core на рабочем Mac, чтобы увидеть живые эпизоды, задачи и связанные материалы.</p>
          <div className="empty-actions">
            <a href={`http://127.0.0.1:43127/today?date=${startDate}`}>Open live dashboard</a>
            <button onClick={() => { setRangePreset("custom"); setStartDate(publicReportDate); setEndDate(publicReportDate); }}>Open available report</button>
          </div>
        </section>
      )}

      <footer className="public-footer">
        <a href="https://github.com/mvisl/Observer/tree/main/apps/observer-web">Dashboard Code</a>
        <a href="https://github.com/mvisl/Observer">Repository</a>
        <a href="https://github.com/mvisl/Observer/blob/main/docs/observer-claude-brief-intention-model.md">About / Methodology</a>
      </footer>
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
          <section className="snapshot-freshness" aria-label="Snapshot freshness">
            <span>{formatSnapshotDay(snapshot.date)}</span>
            <span className={Date.now() - new Date(snapshot.generatedAt).getTime() > 26 * 60 * 60 * 1000 ? "warning" : undefined}>
              {Date.now() - new Date(snapshot.generatedAt).getTime() > 26 * 60 * 60 * 1000
                ? `Stale data: last generated ${formatSnapshotDay(localDateString(new Date(snapshot.generatedAt)))}`
                : `Data generated ${formatSnapshotDay(localDateString(new Date(snapshot.generatedAt)))} at ${fmtTime(snapshot.generatedAt)}`}
            </span>
            <span>{snapshot.timelineSegments.length === 0 ? "No observed work yet" : `${snapshot.timelineSegments.length} observed segments`}</span>
          </section>
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
      {snapshot.timelineSegments.length === 0 && (
        <p className="muted">{snapshot.date === localDateString() ? "No closed context slices yet. Live observations should appear here as soon as Core writes the first episode fragment; the day report no longer waits for shutdown." : "No observed work for this local calendar day. Previous-day data is not substituted."}</p>
      )}
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
  const queryClient = useQueryClient();
  const [selectedThreadId, setSelectedThreadId] = useState<string | null>(null);
  const [showAllArtifacts, setShowAllArtifacts] = useState(false);
  const [diagnostics, setDiagnostics] = useState(false);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renamedTitle, setRenamedTitle] = useState("");
  const correction = useMutation({
    mutationFn: ({ kind, payload }: { kind: string; payload: Record<string, unknown> }) => submitCorrection(kind, payload),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["v1", "day"] })
  });
  return (
    <SnapshotState snapshot={data}>
      {(snapshot) => {
        const selectedThread = snapshot.threadSummaries.find((thread) => thread.id === selectedThreadId) ?? snapshot.threadSummaries[0];
        const relations = selectedThread
          ? snapshot.artifactRelations
            .filter((relation) => relation.taskId === selectedThread.id)
            .sort((left, right) => artifactRoleOrder.indexOf(left.role) - artifactRoleOrder.indexOf(right.role) || new Date(right.lastUsedAt).getTime() - new Date(left.lastUsedAt).getTime())
          : [];
        const visibleRelations = showAllArtifacts ? relations : relations.slice(0, 6);
        return (
          <div className="contexts-with-inspector">
            <section className="panel">
              <div className="section-head"><h2>Contexts</h2><span>Intentions and tasks</span></div>
              <div className="table-list context-list">
                {snapshot.threadSummaries.map((thread) => (
                  <button key={thread.id} className={selectedThread?.id === thread.id ? "selected" : ""} onClick={() => { setSelectedThreadId(thread.id); setShowAllArtifacts(false); }}>
                    <b>{thread.name}</b>
                    <span>{fmtDuration(thread.activeSeconds)} · {thread.episodes} episodes</span>
                  </button>
                ))}
              </div>
            </section>
            <aside className="artifact-inspector" aria-label="Linked task artifacts">
              <div className="artifact-inspector-head">
                <div><p className="eyebrow">Linked artifacts</p><h2>{selectedThread?.name ?? "Select a task"}</h2></div>
                <button className="artifact-diagnostics-toggle" onClick={() => setDiagnostics((value) => !value)} aria-pressed={diagnostics}>{diagnostics ? "Hide IDs" : "IDs"}</button>
              </div>
              <p className="artifact-inspector-note">Роли, а не список вкладок: главный материал, текущий результат, входы решения и коммуникация.</p>
              {visibleRelations.length ? <div className="artifact-list">
                {visibleRelations.map((relation) => (
                  <article className="artifact-card" key={relation.id}>
                    <div className="artifact-card-topline"><span className="artifact-source" title={relation.artifactKind}>{relation.sourceIcon}</span><span className="artifact-role">{artifactRoleLabel[relation.role]}</span><span className="artifact-confidence">{Math.round(relation.confidence * 100)}%</span></div>
                    {renamingId === relation.id ? <form className="artifact-rename" onSubmit={(event) => { event.preventDefault(); correction.mutate({ kind: "artifact_rename", payload: { artifact_id: relation.id, task_id: relation.taskId, title: renamedTitle } }); setRenamingId(null); }}><input value={renamedTitle} onChange={(event) => setRenamedTitle(event.target.value)} autoFocus /><button type="submit">Save</button></form> : relation.directLink ? <a href={relation.directLink} target="_blank" rel="noreferrer" className="artifact-title">{relation.title}</a> : <h3 className="artifact-title">{relation.title}</h3>}
                    <p>{relation.roleSummary}</p>
                    <div className="artifact-meta"><span>{fmtTime(relation.lastUsedAt)}</span><span>{relation.relatedEpisodeCount} {pluralRu(relation.relatedEpisodeCount, "эпизод", "эпизода", "эпизодов")}</span></div>
                    {diagnostics && <p className="artifact-evidence">evidence: {relation.evidenceEventIds.join(" · ")}</p>}
                    <div className="artifact-actions">
                      <button onClick={() => { setRenamingId(relation.id); setRenamedTitle(relation.title); }}>Переименовать</button>
                      {relation.role !== "primary_artifact" && <button onClick={() => correction.mutate({ kind: "artifact_primary", payload: { artifact_id: relation.id, task_id: relation.taskId } })}>Сделать главным</button>}
                      <button className="quiet-danger" onClick={() => correction.mutate({ kind: "artifact_unbind", payload: { artifact_id: relation.id, task_id: relation.taskId } })}>Отвязать</button>
                    </div>
                  </article>
                ))}
              </div> : <p className="artifact-empty">Для этой задачи пока нет материалов с доказанной связью.</p>}
              {relations.length > 6 && <button className="show-all-artifacts" onClick={() => setShowAllArtifacts((value) => !value)}>{showAllArtifacts ? "Скрыть лишнее" : `Показать все (${relations.length})`}</button>}
            </aside>
          </div>
        );
      }}
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
