import { tool } from "@opencode-ai/plugin";

const DEFAULT_TIMEOUT_MS = 300_000;
const MAX_TIMEOUT_MS = 1_800_000;
const MAX_OUTPUT_CHARS = 1_000_000;

const TOOL_DESCRIPTION =
  "Get an independent, repository-aware engineering second opinion from Codex CLI. " +
  "Proactively use this once, without waiting for the user to ask, when a consequential design or " +
  "implementation choice has meaningful trade-offs, a non-trivial change needs an independent " +
  "correctness or security review, repeated attempts have not resolved a problem, or material " +
  "uncertainty remains before declaring completion. First form your own preliminary view and pass " +
  "a focused, neutral question. Do not use for routine low-risk edits, simple factual questions, " +
  "decisions already settled by decisive evidence, or as a substitute for normal tests and inspection.";

export const CodexSecondOpinionPlugin = async () => ({
  tool: {
    codex_second_opinion: tool({
      description: TOOL_DESCRIPTION,
      args: {
        question: tool.schema
          .string()
          .min(1)
          .max(20_000)
          .describe(
            "A focused, neutrally framed engineering question with relevant context, constraints, and the current proposal.",
          ),
      },
      async execute({ question }, context) {
        return executeCodex(question, context.worktree ?? context.directory);
      },
    }),
  },
});

async function executeCodex(question, directory) {
  if (process.env.OPENCODE_CODEX_OUTER_SANDBOX !== "cloud-restricted") {
    return "codex second opinion unavailable: OpenCode is not running inside the cloud-restricted outer sandbox";
  }

  const timeoutMs = readTimeout();
  const prompt = [
    "Provide an independent engineering second opinion on the question below.",
    "Inspect the repository and supporting evidence as needed instead of relying only on the supplied summary.",
    "Return a clear recommendation, repository evidence, risks, alternatives, assumptions, unknowns, and confidence.",
    "Do not modify tracked files or external systems, install dependencies, or run broad expensive tests.",
    "Use bounded primary-source research only when repository evidence cannot settle a compatibility, security, behavior, or versioned API fact.",
    "",
    "<question>",
    question,
    "</question>",
  ].join("\n");

  let processHandle;
  try {
    processHandle = Bun.spawn({
      cmd: [
        "codex",
        "exec",
        "--ignore-user-config",
        "--ephemeral",
        "--cd",
        directory,
        "--config",
        'approval_policy="never"',
        "--config",
        'web_search="live"',
        "--sandbox",
        "danger-full-access",
        prompt,
      ],
      cwd: directory,
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });
  } catch (error) {
    return `codex second opinion unavailable: ${safeError(error)}`;
  }

  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    processHandle.kill();
  }, timeoutMs);

  try {
    const [exitCode, stdout, stderr] = await Promise.all([
      processHandle.exited,
      new Response(processHandle.stdout).text(),
      new Response(processHandle.stderr).text(),
    ]);

    if (timedOut) {
      return `codex second opinion unavailable: timed out after ${timeoutMs}ms`;
    }
    if (exitCode !== 0) {
      const detail = truncate(stderr.trim() || stdout.trim() || `exit code ${exitCode}`);
      return `codex second opinion unavailable: ${detail}`;
    }

    const result = stdout.trim();
    if (!result) {
      return "codex second opinion unavailable: Codex returned no final answer";
    }
    return truncate(result);
  } catch (error) {
    return `codex second opinion unavailable: ${safeError(error)}`;
  } finally {
    clearTimeout(timer);
  }
}

function readTimeout() {
  const raw = process.env.OPENCODE_CODEX_TIMEOUT_MS;
  if (raw === undefined) return DEFAULT_TIMEOUT_MS;

  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value) || value < 1_000 || value > MAX_TIMEOUT_MS) {
    return DEFAULT_TIMEOUT_MS;
  }
  return value;
}

function truncate(value) {
  if (value.length <= MAX_OUTPUT_CHARS) return value;
  return `${value.slice(0, MAX_OUTPUT_CHARS)}\n[...truncated]`;
}

function safeError(error) {
  if (error instanceof Error) return error.message;
  return String(error);
}
