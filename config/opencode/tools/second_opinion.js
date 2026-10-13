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

export default {
  description: TOOL_DESCRIPTION,
  args: {
    question: {
      type: "string",
      minLength: 1,
      maxLength: 20_000,
      description:
        "A focused, neutrally framed engineering question with relevant context, constraints, and the current proposal.",
    },
  },
  async execute({ question }, context) {
    return executeCodex(question, context.worktree ?? context.directory);
  },
};

async function executeCodex(question, directory) {
  const launch = resolveCodexLaunch();
  if (typeof launch === "string") {
    return `second opinion unavailable: ${launch}`;
  }
  const { codexHome, codexSandbox } = launch;

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
        // The credential is read from an auth.json file: the isolated copy the
        // wrapper stages under cloud-restricted, or the user's own ~/.codex
        // under --no-sandbox. The login Keychain is intentionally not used:
        // the legacy Keychain API rewrites the whole keychain database even on
        // reads, which a read-only-Keychain Seatbelt profile cannot permit.
        'cli_auth_credentials_store="file"',
        "--config",
        'shell_environment_policy.inherit="none"',
        "--config",
        'web_search="live"',
        "--sandbox",
        codexSandbox,
        prompt,
      ],
      cwd: directory,
      env: childEnvironment(codexHome),
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });
  } catch (error) {
    return `second opinion unavailable: ${safeError(error)}`;
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
      return `second opinion unavailable: timed out after ${timeoutMs}ms`;
    }
    if (exitCode !== 0) {
      const detail = truncate(stderr.trim() || stdout.trim() || `exit code ${exitCode}`);
      return `second opinion unavailable: ${detail}`;
    }

    const result = stdout.trim();
    if (!result) {
      return "second opinion unavailable: Codex returned no final answer";
    }
    return truncate(result);
  } catch (error) {
    return `second opinion unavailable: ${safeError(error)}`;
  } finally {
    clearTimeout(timer);
  }
}

// Resolve how Codex should be launched for the current opencode session.
// The OPENCODE_CODEX_OUTER_SANDBOX marker is a trusted launch assertion set by
// the wrapper, not proof of containment. Returns an error string when the
// session is unsupported, otherwise { codexHome, codexSandbox }.
function resolveCodexLaunch() {
  const outerSandbox = process.env.OPENCODE_CODEX_OUTER_SANDBOX;
  const isolatedHome = process.env.OPENCODE_CODEX_HOME;

  if (outerSandbox === "cloud-restricted") {
    // The wrapper staged an isolated credential and the cloud-restricted
    // Seatbelt already contains the whole process tree, so Codex relies on
    // that outer boundary rather than applying its own.
    if (!isolatedHome) {
      return "isolated Codex home is not configured";
    }
    return { codexHome: isolatedHome, codexSandbox: "danger-full-access" };
  }

  if (outerSandbox === "none") {
    // No outer Seatbelt is known to contain this process, so do not trust an
    // inherited credential path as evidence of one, nor reuse it: pin a
    // read-only inner sandbox that enforces the tool's non-mutating contract
    // and read the user's own ~/.codex (an inherited CODEX_HOME is dropped so
    // a stale staging path cannot shadow it). A nested launch inside a
    // sandboxed session keeps the cloud-restricted marker instead (see the
    // wrapper) and never reaches this branch.
    return { codexHome: undefined, codexSandbox: "read-only" };
  }

  return "OpenCode is not running under a supported sandbox (cloud-restricted or --no-sandbox)";
}

// An isolated home staged by a wrapper is used as-is; otherwise drop any
// inherited CODEX_HOME so Codex resolves its default $HOME/.codex (the
// credential source the wrapper itself copies for cloud-restricted).
function childEnvironment(codexHome) {
  const env = { ...process.env };
  if (codexHome) {
    env.CODEX_HOME = codexHome;
  } else {
    delete env.CODEX_HOME;
  }
  return env;
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
