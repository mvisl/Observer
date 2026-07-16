import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { NavLink, RouterProvider, createBrowserRouter, useLocation, useSearchParams } from "react-router-dom";
import { getDailyMarkdown, getDaySnapshot, getSession, pairDevice, submitCorrection } from "./api";
import type { DayDashboardSnapshot, SensorChannel, ThreadSummary, TimelineSegment } from "./types";
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
  return new Date().toISOString().slice(0, 10);
}

function localDateString(date = new Date()) {
  const offset = date.getTimezoneOffset();
  const local = new Date(date.getTime() - offset * 60_000);
  return local.toISOString().slice(0, 10);
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

type PublicNode = {
  id: string;
  name: string;
  minutes: number;
  kind: PublicNodeKind;
  question?: string;
  decisions?: number;
  unresolved?: number;
  evidenceKinds?: string[];
  status?: "neutral" | "warning";
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
  const rangeMultiplier = rangePreset === "today"
    ? 1
    : rangePreset === "7d"
      ? 2.85
      : Math.max(0.35, Math.min(4.2, rangeDays * 0.52));
  const scaledMinutes = (minutes: number, weight = 1) => Math.max(5, Math.round(minutes * rangeMultiplier * weight));
  const dateWords = formatDateWords(startDate, endDate, rangePreset);
  const observedMinutes = scaledMinutes(726);
  const coverage = rangePreset === "today" ? 94 : rangePreset === "7d" ? 82 : Math.max(41, Math.min(97, Math.round(94 - rangeDays * 2.2)));

  const root = useMemo<PublicNode>(() => ({
    id: "day",
    name: "День",
    kind: "root",
    minutes: observedMinutes,
    children: [
      {
        id: "stream-work",
        name: "Work",
        kind: "stream",
        minutes: scaledMinutes(670),
        children: [
          {
            id: "branch-libertex",
            name: "Libertex",
            kind: "branch",
            minutes: scaledMinutes(455),
            children: [
              {
                id: "intention-andrey",
                name: "Фидбек Андрея -> решения по WhatToBuy",
                kind: "intention",
                minutes: scaledMinutes(289),
                question: "Как карточкам объяснять ценность без вычислений со стороны юзера?",
                decisions: 5,
                unresolved: 1,
                evidenceKinds: ["чат", "Figma", "AI"],
                children: [
                  { id: "subtask-andrey-feedback", name: "Фидбек -> решение", kind: "subtask", minutes: scaledMinutes(39), evidenceKinds: ["чат"] },
                  { id: "subtask-dividends", name: "Dividends logic", kind: "subtask", minutes: scaledMinutes(74), evidenceKinds: ["чат", "Figma"] },
                  { id: "subtask-card-hierarchy", name: "Card hierarchy", kind: "subtask", minutes: scaledMinutes(63), evidenceKinds: ["чат", "Figma"] },
                  { id: "subtask-figma-execution", name: "Figma execution", kind: "subtask", minutes: scaledMinutes(113), evidenceKinds: ["Figma"] }
                ]
              },
              {
                id: "intention-nebius",
                name: "Nebius cover visual direction",
                kind: "intention",
                minutes: scaledMinutes(66),
                question: "Какой образ Nebius не превращается в generic neon cloud?",
                decisions: 2,
                unresolved: 1,
                evidenceKinds: ["Figma", "AI", "реакция"],
                children: [
                  { id: "subtask-nebius-prompts", name: "Prompt candidates", kind: "subtask", minutes: scaledMinutes(28), evidenceKinds: ["AI"] },
                  { id: "subtask-nebius-criterion", name: "Visual criterion", kind: "subtask", minutes: scaledMinutes(22), evidenceKinds: ["Figma"] },
                  { id: "subtask-nebius-reaction", name: "Reaction binding", kind: "subtask", minutes: scaledMinutes(16), evidenceKinds: ["камера", "текст"] }
                ]
              },
              {
                id: "intention-backlog",
                name: "Backlog / Jira prioritization",
                kind: "intention",
                minutes: scaledMinutes(100),
                question: "Какие issue требуют решения сейчас, а какие просто шумят?",
                decisions: 3,
                unresolved: 2,
                evidenceKinds: ["Jira", "чат", "web"],
                children: [
                  { id: "subtask-jira-triage", name: "Jira issue triage", kind: "subtask", minutes: scaledMinutes(34), evidenceKinds: ["Jira"] },
                  { id: "subtask-research", name: "Research for decision", kind: "subtask", minutes: scaledMinutes(42), evidenceKinds: ["web"] },
                  { id: "subtask-followup", name: "Communication follow-up", kind: "subtask", minutes: scaledMinutes(24), evidenceKinds: ["чат"] }
                ]
              }
            ]
          },
          {
            id: "branch-observer",
            name: "Observer",
            kind: "branch",
            minutes: scaledMinutes(215),
            children: [
              {
                id: "intention-observer-brain",
                name: "Brain / dashboard",
                kind: "intention",
                minutes: scaledMinutes(215),
                question: "Как объяснять день намерениями, evidence и outcome вместо окон?",
                decisions: 6,
                unresolved: 3,
                evidenceKinds: ["Codex", "dashboard", "пилюля"],
                children: [
                  { id: "subtask-public-dashboard", name: "Public dashboard", kind: "subtask", minutes: scaledMinutes(68), evidenceKinds: ["GitHub Pages"] },
                  { id: "subtask-pill-quality", name: "Pill quality", kind: "subtask", minutes: scaledMinutes(72), evidenceKinds: ["пилюля"] },
                  { id: "subtask-reporting-model", name: "Reporting model", kind: "subtask", minutes: scaledMinutes(75), evidenceKinds: ["отчёт"] }
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
        minutes: scaledMinutes(56),
        children: [
          {
            id: "branch-communication",
            name: "Общение",
            kind: "branch",
            minutes: scaledMinutes(56),
            children: [
              {
                id: "intention-family",
                name: "Family / close communication",
                kind: "intention",
                minutes: scaledMinutes(56),
                question: "Что меняет настроение/восстановление, а что остаётся личным контекстом?",
                decisions: 1,
                unresolved: 0,
                evidenceKinds: ["WhatsApp", "music", "aftermath"],
                children: [
                  { id: "subtask-wife-chat", name: "Family / wife chat", kind: "subtask", minutes: scaledMinutes(26), evidenceKinds: ["WhatsApp"] },
                  { id: "subtask-family-logistics", name: "Family logistics", kind: "subtask", minutes: scaledMinutes(18), evidenceKinds: ["чат"] },
                  { id: "subtask-boundary", name: "Boundary rule", kind: "subtask", minutes: scaledMinutes(12), evidenceKinds: ["privacy"] }
                ]
              }
            ]
          }
        ]
      }
    ]
  }), [observedMinutes, rangeMultiplier]);

  const allNodes = useMemo(() => flattenPublicNodes(root), [root]);
  const selectedNode = findPublicNode(root, selectedNodeId) ?? findPublicNode(root, "intention-andrey") ?? root;
  const selectedPath = publicNodePath(root, selectedNode.id).filter((node) => node.kind !== "root");
  const detailChildren = selectedNode.children ?? [];
  const detailTotal = Math.max(1, detailChildren.reduce((sum, child) => sum + child.minutes, 0));
  const episodes: PublicEpisode[] = [
    { id: "ep-andrey-chat", nodeId: "intention-andrey", start: "10:04", end: "10:43", startMinute: 64, endMinute: 103, label: "Andrey feedback" },
    { id: "ep-dividends", nodeId: "subtask-dividends", start: "10:50", end: "12:04", startMinute: 110, endMinute: 184, label: "Dividend logic" },
    { id: "ep-figma", nodeId: "subtask-figma-execution", start: "12:20", end: "14:13", startMinute: 200, endMinute: 313, label: "Figma execution" },
    { id: "ep-observer", nodeId: "intention-observer-brain", start: "14:25", end: "16:38", startMinute: 325, endMinute: 458, label: "Observer brain" },
    { id: "ep-nebius", nodeId: "intention-nebius", start: "16:46", end: "17:52", startMinute: 466, endMinute: 532, label: "Nebius cover" },
    { id: "ep-family", nodeId: "intention-family", start: "18:08", end: "19:04", startMinute: 548, endMinute: 604, label: "Family / music" }
  ];
  const selectedEpisode = episodes.find((episode) => episode.id === selectedEpisodeId) ?? null;
  const isMultiDay = startDate !== endDate;
  const dateColumns = Array.from({ length: Math.max(1, Math.min(14, rangeDays)) }, (_, index) => {
    const date = new Date(`${startDate}T12:00:00`);
    date.setDate(date.getDate() + index);
    return date;
  });
  const sections = (root.children ?? []).flatMap((stream) => (stream.children ?? []).map((branch) => ({ stream, branch })));
  const descendantsOf = (node: PublicNode): Set<string> => new Set(flattenPublicNodes(node).map((item) => item.id));
  const rowEpisodes = (node: PublicNode) => {
    const ids = descendantsOf(node);
    return episodes.filter((episode) => ids.has(episode.nodeId));
  };
  const mergeCloseEpisodes = (items: PublicEpisode[]) => items
    .slice()
    .sort((a, b) => a.startMinute - b.startMinute)
    .reduce<Array<{ episodes: PublicEpisode[]; startMinute: number; endMinute: number }>>((groups, episode) => {
      const previous = groups.at(-1);
      // Four pixels on a 660-minute track is roughly 0.4% of the width.
      if (previous && ((episode.startMinute - previous.endMinute) / 660) * 100 < 0.4) {
        previous.episodes.push(episode);
        previous.endMinute = Math.max(previous.endMinute, episode.endMinute);
      } else {
        groups.push({ episodes: [episode], startMinute: episode.startMinute, endMinute: episode.endMinute });
      }
      return groups;
    }, []);
  const matrixMinutes = (node: PublicNode, dayIndex: number) => {
    const daily = rowEpisodes(node).reduce((total, episode, episodeIndex) => {
      const episodeDay = (episodeIndex * 3 + node.id.length) % dateColumns.length;
      return episodeDay === dayIndex ? total + episode.endMinute - episode.startMinute : total;
    }, 0);
    return daily || Math.round(node.minutes / Math.max(1, dateColumns.length) * ((dayIndex + node.id.length) % 3 === 0 ? 0.35 : 0));
  };
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
      if (episode && episodes.some((item) => item.id === episode)) setSelectedEpisodeId(episode);
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
  }

  function toggleExpanded(node: PublicNode) {
    setExpandedIds((current) => current.includes(node.id)
      ? current.filter((id) => id !== node.id)
      : [...current, node.id]);
  }

  function activeFamily(node: PublicNode) {
    if (node.id === "stream-work") return "libertex";
    if (node.id === "stream-personal") return "personal";
    const path = publicNodePath(root, node.id);
    if (path.some((item) => item.id === "branch-observer")) return "observer";
    if (path.some((item) => item.id === "branch-communication")) return "personal";
    if (path.some((item) => item.id === "intention-nebius")) return "nebius";
    if (path.some((item) => item.id === "intention-backlog")) return "backlog";
    if (path.some((item) => item.id === "branch-libertex")) return "libertex";
    return "neutral";
  }

  return (
    <main className="public-shell public-dashboard-app">
      <header className="public-day-header">
        <div>
          <h1>{dateWords}</h1>
          <span>наблюдалось {fmtMinutes(observedMinutes)} · coverage {coverage}%</span>
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

      <section className="dashboard-workbench" aria-label="Карта дня">
        <div className="structure-pane swimlane-map">
          <div className="day-strip" aria-label="День одной полосой">
            {(root.children ?? []).map((stream) => (
              <button
                key={stream.id}
                className={`family-${activeFamily(stream)}`}
                style={{ flexGrow: stream.minutes }}
                title={`${stream.name} · ${fmtMinutes(stream.minutes)}`}
                onClick={() => selectNode(stream)}
              />
            ))}
          </div>
          {isMultiDay ? (
            <div className="swimlane-axis matrix-axis"><span>Интенция</span><div style={{ gridTemplateColumns: `repeat(${dateColumns.length}, 1fr)` }}>{dateColumns.map((date) => <b key={date.toISOString()}>{new Intl.DateTimeFormat("ru", { weekday: "short", day: "numeric" }).format(date)}</b>)}</div><span>H:MM</span></div>
          ) : (
            <div className="swimlane-axis"><span>Интенция</span><div>{Array.from({ length: 12 }, (_, hour) => <b key={hour}>{`${String(hour + 9).padStart(2, "0")}:00`}</b>)}</div><span>H:MM</span></div>
          )}
          <div className="swimlane-sections">
            {sections.map(({ stream, branch }) => {
              const intentions = [...(branch.children ?? [])].sort((a, b) => b.minutes - a.minutes);
              return (
                <section className={`swimlane-section family-${activeFamily(branch)}`} key={branch.id}>
                  <h2>{stream.name === "Личное" ? branch.name : `${branch.name} · ${fmtMinutes(branch.minutes)}`}</h2>
                  {intentions.map((node) => {
                    const visibleEpisodes = rowEpisodes(node);
                    const hasChildren = Boolean(node.children?.length);
                    const isExpanded = expandedIds.includes(node.id);
                    const renderRow = (rowNode: PublicNode, nested = false) => {
                      const rowItems = rowEpisodes(rowNode);
                      const episodeGroups = mergeCloseEpisodes(rowItems);
                      const matrixMax = Math.max(1, ...dateColumns.map((_, index) => matrixMinutes(rowNode, index)));
                      return (
                        <div className={`swimlane-row ${nested ? "subtask" : ""} ${selectedNode.id === rowNode.id ? "selected" : ""}`} key={rowNode.id}>
                          <div className="swimlane-name">
                            {!nested && hasChildren && <button className="lane-chevron" onClick={() => toggleExpanded(rowNode)} aria-label={isExpanded ? "Свернуть подзадачи" : "Раскрыть подзадачи"}>{isExpanded ? "⌄" : "›"}</button>}
                            <button onClick={() => selectNode(rowNode)} title={rowNode.name}>{rowNode.name}</button>
                          </div>
                          {isMultiDay ? (
                            <div className="swimlane-matrix" style={{ gridTemplateColumns: `repeat(${dateColumns.length}, 1fr)` }}>
                              {dateColumns.map((_, index) => {
                                const minutes = matrixMinutes(rowNode, index);
                                return <button key={index} className={`matrix-cell family-${activeFamily(rowNode)} ${selectedNode.id === rowNode.id ? "selected" : ""}`} style={{ opacity: minutes ? 0.25 + (minutes / matrixMax) * 0.75 : 0.08 }} title={`${rowNode.name} · ${fmtMinutes(minutes)} · ${new Intl.DateTimeFormat("ru", { weekday: "long", day: "numeric" }).format(dateColumns[index])}`} onClick={() => selectNode(rowNode)} />;
                              })}
                            </div>
                          ) : (
                            <div className="swimlane-track">
                              {episodeGroups.map((group) => {
                                const left = (group.startMinute / 660) * 100;
                                const width = Math.max(0.45, ((group.endMinute - group.startMinute) / 660) * 100);
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
                      );
                    };
                    return <div key={node.id}>{renderRow(node)}{isExpanded && node.children?.map((child) => renderRow(child, true))}</div>;
                  })}
                </section>
              );
            })}
          </div>
        </div>

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
          <div className="detail-grid" role="list">
            {(detailChildren.length ? detailChildren : root.children ?? []).map((child) => (
              <button key={child.id} className="detail-row" onClick={() => selectNode(child)} role="listitem">
                <span>{child.name}</span>
                <i><b style={{ width: `${Math.max(6, (child.minutes / detailTotal) * 100)}%` }} /></i>
                <strong>{fmtMinutes(child.minutes)}</strong>
              </button>
            ))}
          </div>
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
              {episodes.slice(0, 5).map((episode) => <p key={episode.id}><b>{episode.start}-{episode.end}</b> {episode.label}</p>)}
            </div>
          )}
        </section>
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
