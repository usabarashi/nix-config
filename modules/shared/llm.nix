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
    # quality at Q4 memory, so the Q4_K_XL file (~14.2 GiB on disk) is the
    # recommended quant — plain Q4 quants of the same model carry a measurable
    # accuracy hit that QAT trains out.
    #
    # Sliding-window attention (1024-token window across most layers) keeps
    # q8 KV growth modest even at 65k context — substantially smaller than
    # a dense full-attention model of the same parameter count. `--flash-attn
    # on` is still required with quantized KV, else dequantize round-trips
    # erase the savings. `--no-mmproj` skips the bundled vision projector
    # (gemma-4 ships multimodal variants; OpenCode is text-only).
    # `--slot-save-path` only exposes /slots/X?action=save|restore — prefix
    # caches must be persisted explicitly, not on shutdown.
    #
    # Speculative decoding intentionally disabled. An external gemma-4-E2B
    # draft was measured at ~42% acceptance with `--spec-draft-n-max 4` on
    # this hardware, yielding ~17 t/s decode vs ~46 t/s baseline — the
    # draft inference cost and verify overhead outweighed the gain. The
    # E2B and 26B-A4B share family/tokenizer/template but are trained
    # independently, so they lack the in-model agreement that MTP-style
    # heads (e.g. Qwen3.6's bundled MTP) provide. Revisit only with a
    # same-family trained spec head (MTP / EAGLE-3 variant) or a
    # benchmarked draft config that demonstrably beats baseline.
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
    # `--cache-type-*`); gemma-4's SWA already keeps KV modest, and the
    # prompt cache itself rarely needs the full 8 GiB for interactive
    # use. If OpenCode begins reprocessing large repeated prefixes (long
    # agentic sessions), this is the first knob to raise back to 8192.
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
          "65536"
          "-ngl"
          "99"
          "--flash-attn"
          "on"
          "--cache-type-k"
          "q8_0"
          "--cache-type-v"
          "q8_0"
          "--cache-reuse"
          "256"
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
