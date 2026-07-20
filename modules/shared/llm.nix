{
  pkgs,
  config,
  homeDirectory,
  repoPath,
  ...
}:

{
  home = {
    packages = with pkgs; [
      llama-cpp
      swiftbar
    ];

    activation.createLlmDirectories = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${homeDirectory}/Library/Logs/llama-server"
      run mkdir -p "${homeDirectory}/Library/Logs/llm"
      run mkdir -p "${homeDirectory}/Library/Logs/swiftbar"
      run mkdir -p "${homeDirectory}/.cache/llama-server-slots"
      run mkdir -p "${homeDirectory}/.config/llama-server"
      run mkdir -p "${homeDirectory}/Library/Application Support/SwiftBar/Plugins"
    '';

    # Menu-bar control plugin for the on-demand llama-server. SwiftBar
    # discovers plugins from `~/Library/Application Support/SwiftBar/Plugins`
    # by default; the file name `*.5s.sh` triggers a 5-second refresh.
    file."Library/Application Support/SwiftBar/Plugins/llama-server.5s.sh" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/swiftbar/llama-server.5s.sh";
      force = true;
    };

    # Log-rotation wrapper invoked by the llama-server launchd agent. Lives
    # under `~/.config/` (no spaces) because launchd's home-manager-generated
    # `/bin/sh -c "wait4path ... && exec ..."` joins ProgramArguments by
    # spaces; a path with embedded whitespace would split incorrectly.
    #
    # Source is a path literal (NOT mkOutOfStoreSymlink) so the wrapper is
    # copied into the Nix store. macOS TCC blocks launchd-spawned shells
    # from traversing into `~/Documents/` (where the repo lives), causing
    # `Operation not permitted` on exec; `/nix/store` is unrestricted.
    file.".config/llama-server/wrapper.sh" = {
      source = ../../config/llama-server/wrapper.sh;
      executable = true;
    };
  };

  launchd.agents = {
    # Auto-start SwiftBar on login so the menu-bar control plugin is always
    # available without manually opening the .app each session.
    swiftbar = {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.swiftbar}/Applications/SwiftBar.app/Contents/MacOS/SwiftBar"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        StandardOutPath = "${homeDirectory}/Library/Logs/swiftbar/stdout.log";
        StandardErrorPath = "${homeDirectory}/Library/Logs/swiftbar/stderr.log";
      };
    };

    # llama-server hosts Gemma 4 26B-A4B (MoE, 3.8B active) QAT for OpenCode.
    # On-demand via SwiftBar plugin (config/swiftbar/) to keep unified memory
    # free when idle. QAT (quantization-aware training) preserves bf16-class
    # quality at Q4 memory; the UD-Q4_K_XL file (~13.3 GiB loaded) is the
    # only main-model quant in the repo and fits this 32 GiB machine.
    #
    # Model selection — benchmarked 2026-07-20 on this Mac14,9 (M2 Pro,
    # 32 GiB, llama.cpp b9608) against the current 30B-class coding field:
    # - GLM-4.7-Flash UD-Q4_K_XL (30B-A3B, MLA; SWE-bench 59.2 vs gemma's
    #   stronger LCB): 37.8 t/s decode short ctx collapsing to 12.5 t/s at
    #   17k ctx (llama.cpp's Metal MLA path scales poorly), pp 92 t/s at
    #   17k, and ~3 GiB heavier. Better agentic scores on paper, clearly
    #   slower on this hardware.
    # - Qwen3-Coder-Next (80B-A3B): smallest usable quant exceeds the
    #   memory budget — excluded.
    # - gemma-4 26B-A4B: 55 t/s short ctx, 37.8 t/s at 20k ctx, pp 218
    #   t/s at 20k — fastest of the class here, and the QAT quant keeps
    #   quality at bf16 level.
    #
    # KV cache stays f16/f16 — do NOT quantize on this backend. Measured:
    # q8_0 KV dequant collapses decode as context grows (44 -> 6.4 t/s at
    # 20k ctx) and is even slower at short ctx (44 vs 55 t/s). Mixed K/V
    # types (e.g. K=f16,V=q8_0) disable the Metal flash-attention fast
    # path and tank prompt processing to ~30 t/s; keep both identical.
    # f16 KV costs ~0.22 MiB/token (1024-token SWA on most layers plus
    # unified-KV global layers), so `-c 49152` allocates ~10.6 GiB KV;
    # model + KV + buffers ~= 25 GiB sits just under Metal's 25.56 GiB
    # working-set limit. `-c 65536` with f16 KV would exceed it. If other
    # GPU workloads (external displays, games) start competing for that
    # budget, drop to `-c 40960` to reclaim ~1.9 GiB.
    # `--no-mmproj` skips the bundled vision projector (gemma-4 ships
    # multimodal variants; OpenCode is text-only). `--slot-save-path`
    # only exposes /slots/X?action=save|restore — prefix caches must be
    # persisted explicitly, not on shutdown.
    #
    # Speculative decoding uses the official MTP drafter
    # (mtp-gemma-4-26B-A4B-it.gguf, smart Q4_0, auto-discovered by `-hf`
    # on llama.cpp >= the 2026-06-07 MTP merge). Measured here with
    # `--spec-draft-n-max 4`: acceptance ~0.75-0.8 on code/tool output,
    # +13-18% decode (66 t/s short ctx, 42.6 t/s at 20k ctx). The MTP
    # head shares the target's KV cache and the target verifies every
    # drafted token, so output distribution is unchanged. Do NOT
    # substitute an external draft model: a gemma-4-E2B draft measured
    # ~42% acceptance and ~17 t/s vs ~46 t/s baseline — independently
    # trained drafts lack in-model agreement and lose on this
    # bandwidth-bound hardware.
    #
    # Reasoning controls: gemma-4 has interleaved thinking. `-rea on`
    # forces thinking on (vs. model-default auto, the only non-default
    # here). `--reasoning-format auto` keeps the default extraction mode
    # explicit; when the model emits recognized thought tags they are
    # separated into the API `reasoning_content` field (vs. mixed into
    # `content`), which lets OpenCode fold them in its UI.
    # `--reasoning-budget 4096` caps per-turn thinking tokens to bound
    # latency on simple queries — unrestricted (-1) lets the model run
    # away on trivial questions before producing visible output.
    #
    # `--cache-ram 4096` caps the host-memory prompt cache below its
    # 8192 MiB default to leave ~4 GiB of system headroom on this 32 GiB
    # machine. This is distinct from KV cache (sized by `-c` and
    # `--cache-type-*`). With f16 KV, checkpoint state runs ~0.22
    # MiB/token, so 4096 MiB holds ~18k tokens of cached prefixes —
    # ample for interactive use. If OpenCode begins reprocessing large
    # repeated prefixes (long agentic sessions), this is the first knob
    # to raise back to 8192.
    #
    # Sampling defaults follow the gemma-4 model card (temp=1.0, top_p=0.95,
    # top_k=64) — these differ markedly from Qwen3 conventions, in particular
    # presence_penalty is unset (gemma is sensitive to repetition penalties).
    llama-server = {
      enable = true;
      config = {
        ProgramArguments = [
          # Wrapper rotates `~/Library/Logs/llama-server/stderr.log` (5
          # gzip'd generations, 10 MiB threshold) on each start, then
          # `exec`s its arguments. See `config/llama-server/wrapper.sh`.
          "${homeDirectory}/.config/llama-server/wrapper.sh"
          "${pkgs.llama-cpp}/bin/llama-server"
          "-hf"
          "unsloth/gemma-4-26B-A4B-it-qat-GGUF:Q4_K_XL"
          "--no-mmproj"
          "--alias"
          "gemma-4-26b-a4b"
          "-c"
          "49152"
          "-ngl"
          "99"
          "--flash-attn"
          "on"
          "--cache-type-k"
          "f16"
          "--cache-type-v"
          "f16"
          "--cache-reuse"
          "256"
          "--spec-type"
          "draft-mtp"
          "--spec-draft-n-max"
          "4"
          "--cache-ram"
          "4096"
          "--slot-save-path"
          "${homeDirectory}/.cache/llama-server-slots"
          "-rea"
          "on"
          "--reasoning-format"
          "auto"
          "--reasoning-budget"
          "4096"
          "--host"
          "127.0.0.1"
          "--port"
          "8080"
          "--temp"
          "1.0"
          "--top-p"
          "0.95"
          "--top-k"
          "64"
          "--min-p"
          "0.00"
          "--jinja"
        ];
        RunAtLoad = false;
        KeepAlive = false;
        ThrottleInterval = 30;
        StandardOutPath = "${homeDirectory}/Library/Logs/llama-server/stdout.log";
        StandardErrorPath = "${homeDirectory}/Library/Logs/llama-server/stderr.log";
      };
    };

    # Monthly HF cache visibility snapshot. Logs total + per-model size so
    # growth is easy to spot. Auto-deletion is intentionally NOT done: the
    # HF cache uses a `blobs/` + `snapshots/` symlink layout where blunt
    # mtime-based pruning can break references for revisions still in use.
    # Cleanup is manual via `huggingface-cli delete-cache` or by removing
    # whole `models--<org>--<repo>` dirs (each is self-contained).
    llm-disk-snapshot = {
      enable = true;
      config = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            out="${homeDirectory}/Library/Logs/llm/disk-snapshot-$(/bin/date +%Y-%m).log"
            {
              echo "=== $(/bin/date) ==="
              /usr/bin/du -sh "${homeDirectory}/.cache/huggingface/hub" 2>&1 || true
              /usr/bin/du -sh "${homeDirectory}/.cache/huggingface/hub/models--"* 2>/dev/null || true
            } >> "$out"
          ''
        ];
        StartCalendarInterval = [
          {
            Day = 1;
            Hour = 4;
            Minute = 0;
          }
        ];
        StandardOutPath = "/dev/null";
        StandardErrorPath = "/dev/null";
      };
    };
  };
}
