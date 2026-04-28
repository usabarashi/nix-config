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
      run mkdir -p "${homeDirectory}/Library/Application Support/SwiftBar/Plugins"
    '';

    # Menu-bar control plugin for the on-demand llama-server. SwiftBar
    # discovers plugins from `~/Library/Application Support/SwiftBar/Plugins`
    # by default; the file name `*.5s.sh` triggers a 5-second refresh.
    file."Library/Application Support/SwiftBar/Plugins/llama-server.5s.sh" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoPath}/config/swiftbar/llama-server.5s.sh";
      force = true;
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

    # llama-server hosts Qwen3.6-35B-A3B (MoE, 3B active) for OpenCode.
    # On-demand because the 22 GiB resident model would otherwise pin unified
    # memory; SwiftBar plugin (config/swiftbar/) exposes menu-bar Start/Stop.
    # Sparse attention (full_attention_interval=4, 10/40 layers full) keeps
    # q8 KV at 64k under ~700 MiB on Metal. `--flash-attn on` is required
    # with quantized KV, else dequantize round-trips erase the savings.
    # `--no-mmproj` skips the bundled vision projector. `--slot-save-path`
    # only exposes /slots/X?action=save|restore — prefix caches must be
    # persisted explicitly, not on shutdown. Speculative decoding is
    # unsupported: the model's Mamba SSM state cannot be rolled back on
    # draft rejection.
    llama-server = {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.llama-cpp}/bin/llama-server"
          # Bartowski mirror is a pragmatic workaround, not a permanent fix:
          # when HF migrated unsloth/Qwen3.6-35B-A3B-GGUF to Xet storage, the
          # tree API briefly returned masked `lfs.oid` (64 asterisks) instead
          # of valid SHA256, which llama.cpp's `is_valid_oid` rejects, causing
          # `get_repo_files` to drop every GGUF and report "no GGUF files
          # found". HF has since restored valid OIDs for this repo, but the
          # next Xet-induced regression could hit any mirror — durable fix
          # belongs upstream in llama.cpp (Xet-aware repo listing). Revisit
          # this pin if you want the marginally smaller UD-IQ4_XS quant.
          "-hf"
          "bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:IQ4_XS"
          "--no-mmproj"
          "--alias"
          "qwen3.6-35b-a3b"
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
          "0.6"
          "--top-p"
          "0.95"
          "--top-k"
          "20"
          "--presence-penalty"
          "1.5"
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
