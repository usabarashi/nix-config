import { createRequire } from "node:module";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  advisorIdentity,
  costUsd,
  countSession,
  safeModel,
  safeProvider,
  tokenPoints,
  type QuerySource,
  type UsageSnapshot,
} from "./usage.ts";

interface Counter {
  add(value: number, attributes?: Record<string, string>): void;
}

interface Telemetry {
  tokens: Counter;
  cost: Counter;
  advisorCalls: Counter;
  sessions: Counter;
  shutdown(): Promise<void>;
}

interface PiApi {
  on(event: "session_start", handler: (event: { reason?: unknown }) => Promise<void> | void): void;
  on(event: "session_shutdown", handler: () => Promise<void> | void): void;
  on(event: "message_end", handler: (event: { message?: MessageLike }) => void): void;
  on(event: "tool_result", handler: (event: ToolResultLike) => void): void;
}

interface MessageLike {
  role?: string;
  provider?: unknown;
  model?: unknown;
  usage?: UsageSnapshot;
}

interface ToolResultLike {
  toolName?: string;
  usage?: UsageSnapshot;
  details?: unknown;
}

function modulesDir(): string | undefined {
  const fromEnv = process.env.PI_USAGE_OTEL_MODULES;
  if (fromEnv && existsSync(path.join(fromEnv, "node_modules"))) {
    return fromEnv;
  }
  const here = path.dirname(fileURLToPath(import.meta.url));
  if (existsSync(path.join(here, "node_modules"))) {
    return here;
  }
  return undefined;
}

function loadTelemetry(): Telemetry | undefined {
  const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
  const root = modulesDir();
  if (!endpoint || !root) {
    return undefined;
  }

  try {
    const require = createRequire(pathToFileURL(path.join(root, "package.json")));
    const api = require("@opentelemetry/api") as {
      diag: { setLogger: (logger: unknown, level: number) => void };
      DiagLogLevel: { NONE: number };
      DiagConsoleLogger: new () => unknown;
    };
    const metrics = require("@opentelemetry/sdk-metrics") as {
      AggregationTemporality: { CUMULATIVE: number };
      MeterProvider: new (options: unknown) => {
        getMeter(name: string): {
          createCounter(name: string, options?: { description?: string; unit?: string }): Counter;
        };
        shutdown(options?: { timeoutMillis?: number }): Promise<void>;
      };
      PeriodicExportingMetricReader: new (options: unknown) => unknown;
    };
    const exporterMod = require("@opentelemetry/exporter-metrics-otlp-http") as {
      OTLPMetricExporter: new (options: { temporalityPreference: number }) => unknown;
    };
    const resources = require("@opentelemetry/resources") as {
      resourceFromAttributes: (attributes: Record<string, string>) => unknown;
    };

    api.diag.setLogger(new api.DiagConsoleLogger(), api.DiagLogLevel.NONE);

    // Cloud Monitoring rejects DELTA writes; pin cumulative whatever the env
    // says.
    const reader = new metrics.PeriodicExportingMetricReader({
      exporter: new exporterMod.OTLPMetricExporter({
        temporalityPreference: metrics.AggregationTemporality.CUMULATIVE,
      }),
      exportIntervalMillis: 60_000,
      exportTimeoutMillis: 2_000,
    });
    const provider = new metrics.MeterProvider({
      resource: resources.resourceFromAttributes({
        "service.name": "pi-coding-agent",
      }),
      readers: [reader],
    });
    const meter = provider.getMeter("pi-usage-otel");
    return {
      tokens: meter.createCounter("pi.token.usage", {
        description: "Pi LLM tokens by type, provider, model, and query source",
        unit: "{token}",
      }),
      cost: meter.createCounter("pi.cost.usage", {
        description: "Pi LLM cost in USD from usage.cost.total",
        unit: "USD",
      }),
      advisorCalls: meter.createCounter("pi.advisor.call.count", {
        description: "Completed ask_advisor tool calls",
        unit: "{call}",
      }),
      sessions: meter.createCounter("pi.session.count", {
        description: "Pi sessions started, excluding /reload",
        unit: "{session}",
      }),
      shutdown: () => provider.shutdown({ timeoutMillis: 2_000 }),
    };
  } catch {
    return undefined;
  }
}

function recordUsage(
  telemetry: Telemetry,
  usage: UsageSnapshot | undefined,
  provider: string,
  model: string,
  querySource: QuerySource,
): void {
  const attributes = { provider, model, query_source: querySource };
  for (const point of tokenPoints(usage)) {
    telemetry.tokens.add(point.value, { ...attributes, type: point.type });
  }
  const cost = costUsd(usage);
  if (cost !== undefined) {
    telemetry.cost.add(cost, attributes);
  }
}

// Pi re-evaluates this module in place on /reload, /new, /resume, and /fork,
// so no state may live on globalThis.
export default function (pi: PiApi): void {
  let telemetry: Telemetry | undefined;

  try {
    pi.on("session_start", (event) => {
      try {
        telemetry ??= loadTelemetry();
        if (telemetry && countSession(event?.reason)) {
          telemetry.sessions.add(1);
        }
      } catch {
        telemetry = undefined;
      }
    });

    pi.on("message_end", (event) => {
      try {
        const message = event?.message;
        if (!telemetry || message?.role !== "assistant") return;
        recordUsage(
          telemetry,
          message.usage,
          safeProvider(message.provider),
          safeModel(message.model),
          "executor",
        );
      } catch {}
    });

    // The only source of advisor usage; the toolResult message is not read.
    pi.on("tool_result", (event) => {
      try {
        if (!telemetry || event?.toolName !== "ask_advisor") return;
        const identity = advisorIdentity(event.details);
        telemetry.advisorCalls.add(1, identity);
        recordUsage(telemetry, event.usage, identity.provider, identity.model, "advisor");
      } catch {}
    });

    pi.on("session_shutdown", async () => {
      const current = telemetry;
      if (!current) return;
      telemetry = undefined;
      try {
        await current.shutdown();
      } catch {}
    });
  } catch {}
}
