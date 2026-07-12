import type { DayDashboardSnapshot } from "./types";

export async function getSession(): Promise<{ authenticated: boolean }> {
  const res = await fetch("/api/v1/session", { credentials: "include" });
  if (res.status === 401) return { authenticated: false };
  if (!res.ok) throw new Error("Session check failed");
  return res.json();
}

export async function pairDevice(code: string): Promise<void> {
  const res = await fetch("/api/v1/auth/pair", {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code, deviceName: navigator.userAgent, commandId: crypto.randomUUID() })
  });
  if (!res.ok) throw new Error("Pairing code is invalid or expired");
}

export async function getDaySnapshot(date: string, diagnostics = false): Promise<DayDashboardSnapshot> {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const params = new URLSearchParams({ date, timezone, diagnostics: String(diagnostics) });
  const res = await fetch(`/api/v1/dashboard/day?${params}`, { credentials: "include" });
  if (!res.ok) throw new Error(`Dashboard snapshot failed: ${res.status}`);
  return res.json();
}

export async function getDailyMarkdown(date: string): Promise<string> {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const params = new URLSearchParams({ date, timezone });
  const res = await fetch(`/api/v1/reports/daily/markdown?${params}`, { credentials: "include" });
  if (!res.ok) throw new Error(`Daily report failed: ${res.status}`);
  return res.text();
}

export async function submitCorrection(kind: string, payload: Record<string, unknown>): Promise<void> {
  const res = await fetch(`/api/v1/corrections/${kind}`, {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...payload, commandId: crypto.randomUUID() })
  });
  if (!res.ok) throw new Error(`Correction failed: ${res.status}`);
}
