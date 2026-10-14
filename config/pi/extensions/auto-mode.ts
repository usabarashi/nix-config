// Auto mode: a toggleable disposition equivalent to OpenCode's `auto` agent —
// act on reasonable assumptions instead of stopping for clarifying questions,
// while still stopping when genuinely blocked. Off by default; `/auto` toggles
// it for the session.
//
// Deployed to ~/.pi/agent/extensions/ by modules/shared/agents-pi.nix. Pi loads
// *.ts extensions from there with jiti, so there is no build step and no
// dependencies. The disposition is injected as an extra system-prompt section
// (not by replacing the prompt), so Pi can keep appending transcript deltas.

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const AUTO_GUIDANCE = `# Auto mode

Bias toward working without stopping for clarifying questions — when you'd normally pause to check, make the reasonable call and keep going; the user will redirect if needed. If the user, a skill, or the shape of the task suggests they want you to ask, do so. And even absent that signal, it's still fine to stop when you're genuinely blocked — unclear direction, missing input, a decision only the user can make.`;

const STATUS_KEY = "auto-mode";

export default function autoModeExtension(pi: ExtensionAPI) {
  let enabled = false;

  function setStatus(ctx: ExtensionContext): void {
    ctx.ui.setStatus(STATUS_KEY, enabled ? ctx.ui.theme.fg("accent", "auto") : undefined);
  }

  pi.registerCommand("auto", {
    description: "Toggle auto mode (act on reasonable assumptions; do not stop for clarifying questions)",
    handler: async (_args, ctx) => {
      enabled = !enabled;
      pi.appendEntry("auto-mode", { enabled });
      setStatus(ctx);
      ctx.ui.notify(enabled ? "Auto mode enabled" : "Auto mode disabled", "info");
    },
  });

  // Restore the toggle across resume/reload from the persisted entry.
  pi.on("session_start", async (_event, ctx) => {
    const entry = ctx.sessionManager
      .getEntries()
      .filter((e: { type: string; customType?: string }) => e.type === "custom" && e.customType === "auto-mode")
      .pop() as { data?: { enabled?: boolean } } | undefined;
    // Reset explicitly so a disabled session cannot inherit stale state.
    enabled = entry?.data?.enabled ?? false;
    setStatus(ctx);
  });

  pi.on("before_agent_start", (event) => {
    if (enabled) {
      event.systemPromptOptions.sections.auto_mode = AUTO_GUIDANCE;
    } else {
      delete event.systemPromptOptions.sections.auto_mode;
    }
  });
}
