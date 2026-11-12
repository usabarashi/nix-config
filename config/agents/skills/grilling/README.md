# grilling

Imported from [mattpocock/skills](https://github.com/mattpocock/skills).

- Upstream source: [`skills/productivity/grilling/SKILL.md`](https://github.com/mattpocock/skills/blob/5863806dd4e15c63174bee4e7515a4256792ecfa/skills/productivity/grilling/SKILL.md)
- Status: `SKILL.md` is a verbatim copy of the pinned upstream commit; `LICENSE` is relocated from upstream root; this `README.md` is local
- Not copied: upstream `agents/openai.yaml` (display-name metadata for OpenAI-hosted skill discovery); Claude Code and Pi do not read it
- License: MIT (see [`LICENSE`](./LICENSE)) -- Copyright (c) 2026 Matt Pocock
- Supersedes the previously vendored `grill-me` skill, which upstream renamed to `grilling` to fix an agent-grilling-itself bug (see upstream commit `e5932a7`)
- 2026-11-12 update (`e5932a7` -> `5863806`): the procedure changed from one question at a time to rounds over the decision tree's *frontier*, with a fixed per-round format, recommended answers worded so "yes" accepts them, and fact-finding delegated to sub-agents with a fresh context window instead of the user
