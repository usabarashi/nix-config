// Pure usage accounting for the Pi OTel extension.
//
// Executor tokens come from assistant message_end. Advisor tokens come only
// from the ask_advisor tool_result `usage` field. pi-advisor-flow fills that
// field via advisorUsageForPi (advisor call + the screening classifier,
// combined once) and invokes the advisor with streamSimple, which does not
// append an assistant message to the parent session. Pi types tool-result
// usage as "not part of main LLM context accounting", so recording both
// sources does not double-count ask_advisor.
//
// Not visible here, and therefore omitted: turn-gate, loop-gate, and
// /advisor-manual consultations. Those stay in pi-advisor-flow's session
// totals because Pi has no lifecycle usage-attribution API. cacheWrite1h and
// reasoning are subsets of cacheWrite and output, so they are not separate
// series.

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

// Pi's catalog (or provider-reported) total. Missing or non-finite cost is
// omitted rather than priced from a second table.
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

// /reload tears the runtime down and emits session_start again for the same
// session. Count the session once.
export function countSession(reason: unknown): boolean {
  return reason !== "reload";
}
