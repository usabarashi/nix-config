// Ring a bell on the host when control returns to the user: Pi has finished all
// automatic work for a run and will not continue on its own (`agent_settled`).
// This is the notification-only boundary, so the handler cannot change the run.
//
// Deployed to ~/.pi/agent/extensions/ by modules/shared/agents-pi.nix. Pi loads
// *.ts extensions from there with jiti, so there is no build step and no
// dependencies. Playback is best-effort: a failure never affects the session.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const AFPLAY = "/usr/bin/afplay";
const BELL = "/System/Library/Sounds/Ping.aiff";
const ERROR = "/System/Library/Sounds/Basso.aiff";

// Collapse near-simultaneous bells into one.
const MIN_BELL_INTERVAL_MS = 500;
// Bound a stuck player so children cannot accumulate.
const KILL_AFTER_MS = 5000;

let lastBellAt = 0;

function play(sound: string): boolean {
  try {
    const proc = Bun.spawn([AFPLAY, sound], {
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
    });
    // Detach so a player never holds the event loop open, and bound its
    // lifetime so a hang cannot leak a process.
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

export default function (pi: ExtensionAPI) {
  pi.on("agent_settled", (event, ctx) => {
    // Only ring for an interactive session; stay silent in print/JSON runs.
    // (Defensive: skip the guard if a context is not supplied.)
    if (ctx && ctx.mode && ctx.mode !== "tui") return;
    if (event.aborted) play(ERROR);
    else bell();
  });
}
