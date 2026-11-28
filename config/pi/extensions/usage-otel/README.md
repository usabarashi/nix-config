# usage-otel

Pi extension that reports LLM usage as OpenTelemetry metrics over OTLP/HTTP.
Pi loads `index.ts` from this directory through the `pi.extensions` field in
`package.json`; the npm dependencies are built by `packages/pi-usage-otel`
because this tree is read-only inside the Seatbelt sandbox.

## What is sent

| Metric | Unit | Labels |
|---|---|---|
| `pi.token.usage` | `{token}` | `type` = `input` \| `output` \| `cacheRead` \| `cacheWrite`, `provider`, `model`, `query_source` = `executor` \| `advisor` |
| `pi.cost.usage` | `USD` | `provider`, `model`, `query_source` |
| `pi.advisor.call.count` | `{call}` | `provider`, `model` |
| `pi.session.count` | `{session}` | none |

`provider` and `model` are the only free-form labels. Each is length- and
charset-checked (`[A-Za-z0-9._:-]` for `provider`, `[A-Za-z0-9._:/-]` for
`model`), and absolute paths, `..`, and backslashes become `unknown`, so a model
id such as `meta-llama/llama-3.3-70b-instruct:free` survives while an absolute
path does not. That is a shape filter, not proof of provenance: a *relative*
path-like string, or a prompt word without spaces, still fits the charset. No
session id, message text, tool argument, or cwd is ever read, and nothing is
sent as an unlabelled attribute.

`exportIntervalMillis` is 60s. Every metric is a counter exported with
`AggregationTemporality.CUMULATIVE`; the wrapper also sets
`OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative` so an inherited
environment cannot flip the stream to delta.

## Lifecycle

Pi rebinds a fresh instance on `/reload`, `/new`, `/resume`, and `/fork`,
re-evaluating this module in the same process. The extension therefore keeps no
state on `globalThis`: an "already loaded" guard would survive into the next
instance and leave it without handlers. Each instance builds its own
`MeterProvider` in `session_start` and shuts it down in `session_shutdown` (2s
cap), which also attempts a final collection and export.

Consequences of that lifecycle:

- Counters restart from zero in each new provider, so a reload or session
  switch looks like a cumulative reset to the collector. Nothing is double
  counted. A sample accumulated since the last 60s export is lost only if that
  final export times out or fails.
- `/reload` does not increment `pi.session.count` (`countSession` skips
  `reason === "reload"`).

## Accounting

Executor tokens come from `message_end` for assistant messages. Advisor tokens
come only from the `ask_advisor` `tool_result` `usage` field, which
pi-advisor-flow fills with the advisor call plus its screening classifier
(`advisorUsageForPi`), and `details.advisor` names the model. Pi keeps that field
on nested calls, so codemode's `ask_advisor` is counted too. Advisor responses
are produced with `streamSimple` and never become parent-session assistant
messages, so recording both sources does not count a call twice. Turn-gate,
loop-gate, and `/advisor-manual` consultations never reach a lifecycle event and
are not measured here.

## Known limitations

- **Seatbelt cannot pin the collector.** `sandbox-exec` rejects an IP literal in
  a `remote` filter (`host must be * or localhost in network address`), so both
  profiles grant TCP 4318 to `*`. Any process in either sandbox can reach any
  remote host on that one port, and the grant is not OTLP-specific. If
  collector-only egress is a requirement, add a loopback forward (for example
  `launchd` + `socat`, or `ssh -L 4318:...`) and delete the `*:4318` rule; the
  profiles already allow `localhost:*`.
- **One cumulative series per label set.** These are best-effort totals for a
  single running Pi. Two Pi processes at once write overlapping cumulative
  intervals into the same Cloud Monitoring series, which collides even when the
  writes are accepted (the sum of two cumulative streams is not total usage).
  The fix is a writer identity in the backend or a single aggregating writer; a
  per-process label here would multiply the series count.
- **Export failures are silent.** `diag` is set to `NONE` on purpose, so a
  rejected descriptor (for example an unexpected `USD` unit) or an unreachable
  collector shows up only as missing data.
- The endpoint defaults to `http://192.168.1.201:4318`. The collector admits
  sources by firewall rule, so a Mac outside that set (another VLAN, or a DHCP
  address no longer covered) sees a silent drop: Pi keeps running and the
  points are lost. See "Operating it".

## Checking it locally

```bash
node --test usage.test.ts        # pure accounting/label logic
npx tsc --noEmit -p tsconfig.json
```

The pure functions in `usage.ts` carry the testable behavior; `index.ts` only
wires Pi events to them.

## Operating it

The collector allows this Mac by source address. If its firewall rule does not
cover the Mac's VLAN (or its DHCP address), TCP 4318 is dropped rather than
refused and the export fails silently:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.1.201:4318/v1/metrics   # 405 = reachable
```

The exporter retries on its 60s interval, so no Pi restart is needed after a
network fix.

Cloud Monitoring side: the four descriptors are
`workload.googleapis.com/pi.{token.usage,cost.usage,advisor.call.count,session.count}`
and each carries the unit and labels listed above (`USD` is accepted as-is).
Read them with `ALIGN_RATE`, not by summing the cumulative value:

| symptom | meaning |
|---|---|
| no `pi.*` descriptors at all | nothing reached the collector: endpoint, firewall, collector down, or no service-account key |
| every descriptor except `pi.cost.usage` | the `USD` unit was rejected by the descriptor creation |
| descriptor exists, no recent points | Pi not running, or the export is failing (see the collector's log) |
