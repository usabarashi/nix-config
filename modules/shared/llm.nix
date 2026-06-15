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
    # No MTP head: gemma-4 does not ship multi-token-prediction weights, so
    # `--spec-type draft-mtp` is removed. A draft-model speculative path
    # (e.g. gemma-4-E2B via `--model-draft`) is possible but A4B's 3.8B
    # active decode is already fast enough for OpenCode interactive use on
    # M2 Pro; revisit if long-form generation feels slow.
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
          "--slot-save-path"
          "${homeDirectory}/.cache/llama-server-slots"
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
