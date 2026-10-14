// Goal command: `/goal <objective>` sets a session goal that steers the agent
// across turns (injected as a system-prompt section); `/goal` shows it and
// `/goal clear` removes it. Off by default.
//
// Deployed to ~/.pi/agent/extensions/ by modules/shared/agents-pi.nix. Pi loads
// *.ts extensions from there with jiti, so there is no build step and no
// dependencies. The goal is injected as an extra system-prompt section (not by
// replacing the prompt), so Pi can keep appending transcript deltas.

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "goal";

export default function goalExtension(pi: ExtensionAPI) {
  let goal: string | undefined;

  function setStatus(ctx: ExtensionContext): void {
    const label = goal ? `🎯 ${goal.length > 40 ? `${goal.slice(0, 39)}…` : goal}` : undefined;
    ctx.ui.setStatus(STATUS_KEY, label ? ctx.ui.theme.fg("accent", label) : undefined);
  }

  function persist(): void {
    pi.appendEntry("goal", { goal });
  }

  pi.registerCommand("goal", {
    description: "Set, show, or clear the session goal (steers the agent across turns)",
    handler: async (args, ctx) => {
      const arg = (args ?? "").trim();
      if (!arg) {
        ctx.ui.notify(goal ? `Goal: ${goal}` : "No goal set. Usage: /goal <objective> | /goal clear", "info");
        return;
      }
      if (arg === "clear" || arg === "none" || arg === "off") {
        goal = undefined;
        persist();
        setStatus(ctx);
        ctx.ui.notify("Goal cleared", "info");
        return;
      }
      goal = arg;
      persist();
      setStatus(ctx);
      ctx.ui.notify(`Goal set: ${goal}`, "info");
    },
  });

  // Restore across resume/reload from the persisted entry.
  pi.on("session_start", async (_event, ctx) => {
    const entry = ctx.sessionManager
      .getEntries()
      .filter((e: { type: string; customType?: string }) => e.type === "custom" && e.customType === "goal")
      .pop() as { data?: { goal?: string } } | undefined;
    // Reset explicitly (a cleared goal in a resumed session must not resurrect
    // a stale in-memory value).
    goal = entry?.data?.goal;
    setStatus(ctx);
  });

  pi.on("before_agent_start", (event) => {
    if (goal) {
      event.systemPromptOptions.sections.session_goal = `# Session goal

${goal}

Keep this goal in mind across turns and prefer actions that advance it.`;
    } else {
      delete event.systemPromptOptions.sections.session_goal;
    }
  });
}
