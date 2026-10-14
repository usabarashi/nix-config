// Ring a bell on the host when the agent hands control back to the user: a
// permission request, the end of a turn (session idle), or an error.
//
// Auto-loaded from ~/.config/opencode/plugins/ (deployed by
// modules/shared/agents-opencode.nix). The audio mach services this needs are
// already granted by config/agents/cloud-restricted.sb; playback is
// best-effort, so a failure never affects the session.
//
// NOTE: this requires OPENCODE_PURE to be unset. The cloud-restricted wrapper
// sets OPENCODE_PURE=1, which disables all external plugins; see the wrapper
// (packages/opencode-sandboxed/default.nix) for the policy.

const AFPLAY = "/usr/bin/afplay";
const BELL = "/System/Library/Sounds/Ping.aiff";
const ERROR = "/System/Library/Sounds/Basso.aiff";

// Collapse near-simultaneous bells into one. Errors are never suppressed.
const MIN_BELL_INTERVAL_MS = 500;
// Bound a stuck player so children cannot accumulate.
const KILL_AFTER_MS = 5000;

let lastBellAt = 0;

function play(sound) {
  try {
    const proc = Bun.spawn([AFPLAY, sound], {
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
    });
    // Detach so a player never holds the server's event loop open, and bound
    // its lifetime so a hang cannot leak a process.
    proc.unref?.();
    const timer = setTimeout(() => {
      try {
        proc.kill();
      } catch {
        // Already exited.
      }
    }, KILL_AFTER_MS);
    timer.unref?.();
    return true;
  } catch {
    // Audio is best-effort; ignore a missing or failed player.
    return false;
  }
}

function bell() {
  if (Date.now() - lastBellAt < MIN_BELL_INTERVAL_MS) return;
  // Only open the throttle window once a player actually launched.
  if (play(BELL)) lastBellAt = Date.now();
}

// Subagents run as child sessions and emit their own session.idle, which would
// chime mid-turn. Only a root session (no parentID) means the turn is really
// over for the user. session.idle carries no parentID, so look it up. If the
// lookup fails, prefer notifying over staying silent.
async function isRootSession(client, sessionID) {
  if (!sessionID) return true;
  try {
    const { data } = await client.session.get({ path: { id: sessionID } });
    return !data?.parentID;
  } catch {
    return true;
  }
}

export default async ({ client }) => ({
  event: async ({ event }) => {
    // The event bus does not await or catch hook rejections, so never throw.
    try {
      switch (event.type) {
        case "permission.asked":
          bell();
          break;
        case "session.idle":
          if (await isRootSession(client, event.properties?.sessionID)) bell();
          break;
        case "session.error":
          play(ERROR);
          break;
      }
    } catch {
      // A notification failure must never disrupt the session.
    }
  },
});
