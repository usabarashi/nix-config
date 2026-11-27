// Pure accounting called by index.ts. Advisor usage arrives only on the
// ask_advisor tool_result (advisor call plus its screening classifier); the
// advisor appends no assistant message, so the two sources never overlap.
// Turn-gate, loop-gate, and /advisor-manual consultations carry no lifecycle
// event and are not counted.

export const TOKEN_TYPES = ["input", "output", "cacheRead", "cacheWrite"] as const;

export type TokenType = (typeof TOKEN_TYPES)[number];

export type QuerySource = "executor" | "advisor";

export interface UsageCost {
  total?: number;
}

export interface UsageSnapshot {
  input?: number;
  output?: number;
  cacheRead?: number;
  cacheWrite?: number;
  cost?: UsageCost;
}

export interface TokenPoint {
  type: TokenType;
  value: number;
}

const PROVIDER_LABEL = /^[A-Za-z0-9._:-]{1,64}$/;
const MODEL_LABEL = /^[A-Za-z0-9._:/-]{1,80}$/;

function finitePositive(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return undefined;
  }
  return value;
}

export function safeProvider(value: unknown): string {
  if (typeof value !== "string") return "unknown";
  const trimmed = value.trim();
  return PROVIDER_LABEL.test(trimmed) ? trimmed : "unknown";
}

export function safeModel(value: unknown): string {
  if (typeof value !== "string") return "unknown";
  const trimmed = value.trim();
  if (trimmed.includes("..") || trimmed.startsWith("/") || trimmed.includes("\\")) {
    return "unknown";
  }
  return MODEL_LABEL.test(trimmed) ? trimmed : "unknown";
}

export function tokenPoints(usage: UsageSnapshot | undefined): TokenPoint[] {
  if (!usage) return [];
  const points: TokenPoint[] = [];
  for (const type of TOKEN_TYPES) {
    const value = finitePositive(usage[type]);
    if (value !== undefined) {
      points.push({ type, value });
    }
  }
  return points;
}

// No fallback price table: a missing or non-finite total is omitted.
export function costUsd(usage: UsageSnapshot | undefined): number | undefined {
  return finitePositive(usage?.cost?.total);
}

export function advisorIdentity(details: unknown): { provider: string; model: string } {
  if (typeof details !== "object" || details === null) {
    return { provider: "unknown", model: "unknown" };
  }
  const advisor = (details as { advisor?: unknown }).advisor;
  if (typeof advisor !== "string") {
    return { provider: "unknown", model: "unknown" };
  }
  const slash = advisor.indexOf("/");
  if (slash <= 0 || slash === advisor.length - 1) {
    return { provider: "unknown", model: safeModel(advisor) };
  }
  return {
    provider: safeProvider(advisor.slice(0, slash)),
    model: safeModel(advisor.slice(slash + 1)),
  };
}

// /reload re-emits session_start for the same session; count it once.
export function countSession(reason: unknown): boolean {
  return reason !== "reload";
}
