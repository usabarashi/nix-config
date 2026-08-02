const DEFAULT_MODEL = "opencode-go/kimi-k3";
const DEFAULT_MAX_CHARS = 300_000;
const DEFAULT_TIMEOUT_MS = 300_000;

/**
 * Instruction prose sent to the advisor model (before appending the transcript).
 */
const ADVISOR_INSTRUCTIONS =
  "You are an advisor to an AI coding tool. Below is the" +
  " transcript of a session. " +
  "The tool is being consulted mid-turn, so judge from the transcript as-is.\n\n" +
  "Review the conversation carefully. Identify:\n" +
  "1. Risks in the current approach\n2. Better alternatives\n3. Missed edge cases or requirements\n4. Incorrect assumptions\n\n" +
  "Be concise and decisive. Do NOT call any tools. Return only your analysis.\n\n";

function safeErrorString(err) {
  if (!err || typeof err === "string") return String(err);
  const collected = [];
  if (err.name) collected.push(`name=${err.name}`);
  if (err.message) collected.push(`message=${err.message}`);
  if (err.status) collected.push(`status=${err.status}`);
  if (err.success !== undefined) collected.push(`success=${err.success}`);
  if (err.data !== undefined) {
    try { collected.push(`data=${JSON.stringify(err.data)}`); }
    catch { collected.push(`data=${String(err.data)}`); }
  }
  if (err.errors?.length) {
    try { collected.push(`errors=${JSON.stringify(err.errors)}`); }
    catch { collected.push(`errors=${String(err.errors)}`); }
  }
  if (err.detail) collected.push(`detail=${err.detail}`);
  if (err.error) collected.push(`error=${safeErrorString(err.error)}`);
  if (!collected.length) {
    try {
      const s = JSON.stringify(err, Object.getOwnPropertyNames(err));
      if (s !== "{}") collected.push(s);
    } catch {}
  }
  return collected.length ? collected.join(" | ") : String(err);
}

/**
 * Parse an integer from an env var and clamp it to [min, max].
 * Returns `defaultVal` on missing/invalid/out-of-range.
 */
function clampEnvInt(name, defaultVal, min, max) {
  const raw = process.env[name];
  if (raw === undefined || raw === null) return defaultVal;
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n)) return defaultVal;
  if (n < min || n > max) return defaultVal;
  return n;
}

/**
 * Safe JSON.stringify that never throws.
 * Truncates output beyond `maxLen` chars to bound memory for large tool IO.
 */
function safeJSON(value, maxLen = 2000) {
  let s;
  try { s = JSON.stringify(value); }
  catch { s = String(value); }
  if (s.length > maxLen) return s.slice(0, maxLen) + `\n[...truncated (+${s.length - maxLen} more chars)]`;
  return s;
}

/**
 * Unwrap an SDK call result, converting both `{ error }` and thrown exceptions
 * into a uniform `{ ok, data, error }` shape.
 */
async function unwrapSDK(promise, label) {
  try {
    const result = await promise;
    if (result?.error) return { ok: false, data: undefined, error: `${label}: ${safeErrorString(result.error)}` };
    return { ok: true, data: result?.data, error: undefined };
  } catch (e) {
    return { ok: false, data: undefined, error: `${label}: ${safeErrorString(e)}` };
  }
}

/**
 * Bounded transcript serialization.
 * Never builds the full transcript in memory; stops collecting once maxChars
 * is reached and returns a head + truncation banner + tail.
 */
function serializeTranscript(messages, maxChars) {
  const parts = [];
  let totalLen = 0;
  let limitReached = false;

  for (const msg of messages) {
    if (limitReached) break;
    const role = msg.info?.role === "assistant" ? "assistant" : "user";
    let block = `## ${role}\n`;
    for (const p of msg.parts ?? []) {
      if (p.type === "text" && p.text) {
        block += p.text + "\n";
      } else if (p.type === "tool") {
        const s = p.state ?? {};
        if (s.status === "completed") {
          block += `\n### tool: ${p.tool}\ninput: ${safeJSON(s.input)}\noutput: ${s.output ?? ""}\n`;
        } else if (s.status === "error") {
          block += `\n### tool: ${p.tool} (error)\ninput: ${safeJSON(s.input)}\nerror: ${s.error ?? ""}\n`;
        }
      }
    }
    block += "\n";

    if (totalLen + block.length > maxChars * 2) {
      limitReached = true;
      // Push a truncated placeholder so tail-scanning still sees this message boundary
      parts.push(`## ${role}\n[...message truncated...]\n`);
      totalLen += 80; // placeholder cost
    } else {
      parts.push(block);
      totalLen += block.length;
    }
  }

  if (totalLen <= maxChars) return { text: parts.join(""), truncated: false };

  // Head: first message's role line (preamble)
  const firstNewline = parts[0]?.indexOf("\n") ?? -1;
  let head = firstNewline > 0 ? parts[0].slice(0, firstNewline) : "";
  const headMax = Math.floor(maxChars / 4);
  if (head.length > headMax) head = head.slice(0, headMax) + "\n[...]\n";

  const banner = `\n[...truncated (was ${totalLen} chars, trimmed to ${maxChars})]\n`;
  let tail = "";
  let remaining = maxChars - head.length - banner.length;

  for (let i = parts.length - 1; i >= 0 && remaining > 0; i--) {
    const part = parts[i];
    if (part.length <= remaining) {
      tail = part + tail;
      remaining -= part.length;
    } else if (remaining > 80) {
      tail = part.slice(0, remaining) + "\n[...]\n";
      break;
    }
  }

  return { text: head + banner + tail, truncated: true };
}

// ---------------------------------------------------------------------------
// Plugin entry
// ---------------------------------------------------------------------------

export const AdvisorPlugin = async ({ client }) => {
  return {
    tool: {
      advisor: {
        description: "Consult a stronger advisor model before committing to an approach, when stuck on a recurring error, or before declaring completion.",
        args: {},
        async execute(_args, context) {
          return await executeAdvisor(client, context.sessionID, context.directory);
        },
      },
    },
  };
};

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function executeAdvisor(client, sessionID, directory) {
  const modelStr = process.env.OPENCODE_ADVISOR_MODEL ?? DEFAULT_MODEL;
  const maxCharsNum = clampEnvInt("OPENCODE_ADVISOR_MAX_CHARS", DEFAULT_MAX_CHARS, 10_000, 1_000_000);
  const timeoutMs = clampEnvInt("OPENCODE_ADVISOR_TIMEOUT_MS", DEFAULT_TIMEOUT_MS, 1_000, 1_800_000);

  const slash = modelStr.indexOf("/");
  if (slash <= 0 || slash >= modelStr.length - 1 || modelStr.indexOf("/", slash + 1) !== -1) {
    return "advisor unavailable: invalid OPENCODE_ADVISOR_MODEL";
  }
  const providerID = modelStr.slice(0, slash);
  const modelID = modelStr.slice(slash + 1);

  // Overall operation timeout (covers all SDK calls)
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);

  try {
    // Fetch transcript
    const msgResult = await unwrapSDK(client.session.messages({
      path: { id: sessionID },
      signal: ac.signal,
    }), "session.messages");
    if (!msgResult.ok || !msgResult.data?.length) {
      return msgResult.ok
        ? "advisor unavailable: session has no messages"
        : `advisor unavailable: ${msgResult.error}`;
    }
    const messages = msgResult.data;

    // Serialize (bounded: never builds the full string before truncation)
    const { text: transcriptText, truncated: isTruncated } = serializeTranscript(messages, maxCharsNum);
    const truncatedLabel = isTruncated ? " (truncated)" : "";
    const transcript = ADVISOR_INSTRUCTIONS.replace(
      "Below is the transcript",
      `Below is the${truncatedLabel} transcript`,
    ) + "<transcript>\n" + transcriptText + "\n</transcript>";

    // ---- Step 1: Try SDK path (session.create + session.prompt + session.delete) ----
    const sdkResult = await trySDKPrompt(client, directory, providerID, modelID, transcript, ac.signal, timeoutMs);
    if (sdkResult.ok) {
      return sdkResult.guidance;
    }

    // ---- Step 2: SDK path failed - return the error ----
    return `advisor unavailable: ${sdkResult.error}`;
  } catch (err) {
    return `advisor unavailable: ${safeErrorString(err)}`;
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------
// SDK prompt path
// ---------------------------------------------------------------------------

/**
 * Try session.create + session.prompt + session.delete.
 * Accepts an overall `signal` from executeAdvisor for lifecycle-wide timeout.
 * Returns { ok: true, guidance } or { ok: false, error }.
 */
async function trySDKPrompt(client, directory, providerID, modelID, transcript, overallSignal, timeoutMs) {
  const disableMap = { advisor: false };
  const FALLBACK_TOOL_IDS = ["bash","edit","write","patch","task","webfetch","skill","todowrite","read","grep","glob","list"];
  const idsResult = await unwrapSDK(client.tool.ids({ query: { directory }, signal: overallSignal }), "tool.ids");
  const toolIDs = idsResult.ok && Array.isArray(idsResult.data) ? idsResult.data : FALLBACK_TOOL_IDS;
  for (const id of toolIDs) disableMap[id] = false;

  const createResult = await unwrapSDK(client.session.create({ query: { directory }, signal: overallSignal }), "session.create");
  if (!createResult.ok || !createResult.data?.id) {
    return { ok: false, error: createResult.ok ? "session.create: no session ID in response" : createResult.error };
  }
  const advSessionID = createResult.data.id;

  const promptAc = new AbortController();
  const promptTimer = setTimeout(() => promptAc.abort(), timeoutMs);
  // Chain: if overall signal fires, also abort the prompt
  overallSignal.addEventListener("abort", () => promptAc.abort(), { once: true });

  try {
    const promptResult = await unwrapSDK(client.session.prompt({
      path: { id: advSessionID },
      query: { directory },
      signal: promptAc.signal,
      body: {
        model: { providerID, modelID },
        system:
          "You are an advisor to an AI coding tool. You are being consulted mid-turn, " +
          "so judge from the transcript as-is.\n\n" +
          "Review the conversation carefully. Identify:\n" +
          "1. Risks in the current approach\n2. Better alternatives\n3. Missed edge cases or requirements\n4. Incorrect assumptions\n\n" +
          "Be concise and decisive. Do NOT call any tools. Return only your analysis.",
        tools: disableMap,
        parts: [{ type: "text", text: transcript }],
      },
    }), "");

    if (!promptResult.ok) {
      const label = promptAc.signal.aborted ? "timeout" : "error";
      return { ok: false, error: `session.prompt ${label}: ${promptResult.error.replace(/^: /, "")}` };
    }

    let guidance = "";
    if (promptResult.data?.parts) {
      for (const part of promptResult.data.parts) {
        if (part.type === "text" && part.text) guidance += part.text + "\n";
      }
    }
    const result = guidance.trim();
    if (!result) return { ok: false, error: "advisor returned no text" };
    return { ok: true, guidance: result };
  } finally {
    clearTimeout(promptTimer);
    const delAc = new AbortController();
    const delTimer = setTimeout(() => delAc.abort(), 10_000);
    const delResult = await unwrapSDK(client.session.delete({ path: { id: advSessionID }, signal: delAc.signal }), "");
    if (!delResult.ok) console.warn("advisor: session.delete failed", delResult.error.replace(/^: /, ""));
    clearTimeout(delTimer);
  }
}

// (no fallback; SDK session.prompt is the canonical path for all providers)
