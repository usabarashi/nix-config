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

    # llama-server hosts Qwen3.6-35B-A3B (MoE, 3B active) for OpenCode.
    # On-demand because the 22 GiB resident model would otherwise pin unified
    # memory; SwiftBar plugin (config/swiftbar/) exposes menu-bar Start/Stop.
    # Sparse attention (full_attention_interval=4, 10/40 layers full) keeps
    # q8 KV at 64k under ~700 MiB on Metal. `--flash-attn on` is required
    # with quantized KV, else dequantize round-trips erase the savings.
    # `--no-mmproj` skips the bundled vision projector. `--slot-save-path`
    # only exposes /slots/X?action=save|restore — prefix caches must be
    # persisted explicitly, not on shutdown.
    #
    # MTP (Multi Token Prediction) speculative decoding via `--spec-type
    # draft-mtp` (llama.cpp b9190+, PR ggml-org/llama.cpp#22673). The MTP
    # head loads from the same GGUF but llama.cpp allocates it as a separate
    # model with its own context/KV; recurrent-state rollback landed in the
    # same PR, which is what makes this viable for Qwen3.6's Mamba/SSM
    # layers. Memory delta is NOT free: the extra KV alone is ~67 MiB
    # (1 MTP layer at 65k q8), but PR user data shows a Qwen3.6-27B Q6 run
    # going from 22.47 -> 24.96 GiB (+2.49 GiB) with MTP enabled, attributed
    # to the second-context allocation plus runtime buffers. Treat resident
    # memory as the gating signal, not theoretical KV math.
    #
    # `--spec-draft-n-max 2` chosen for Apple Silicon UMA: PR's Strix Point
    # APU sweep (closest UMA analog) shows n=2 -> 1.199x, n=3 -> 1.153x.
    # MoE A3B's already-cheap baseline decode amortizes MTP less than dense
    # models do, and deeper drafts add verification cost on UMA. Note:
    # parallel decoding with MTP is "not fully optimized" per the PR, so
    # OpenCode-subagent concurrent calls may not see single-stream gains.
    # Prompt processing takes a hit (D2H embedding transfers); watch long
    # prefills.
    llama-server = {
      enable = true;
      config = {
        ProgramArguments = [
          # Wrapper rotates `~/Library/Logs/llama-server/stderr.log` (5
          # gzip'd generations, 10 MiB threshold) on each start, then
          # `exec`s its arguments. See `config/llama-server/wrapper.sh`.
          "${homeDirectory}/.config/llama-server/wrapper.sh"
          "${pkgs.llama-cpp}/bin/llama-server"
          # unsloth MTP GGUF: contains both the base model and the MTP head
          # in one file. UD-IQ4_XS matches the prior bartowski IQ4_XS quant
          # in resident size (~18 GiB). The earlier Xet-OID regression that
          # forced the bartowski mirror was resolved upstream on HF; if it
          # returns, the symptom is `get_repo_files` reporting "no GGUF
          # files found" and the fix is either a mirror or a direct URL.
          "-hf"
          "unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-IQ4_XS"
          "--spec-type"
          "draft-mtp"
          "--spec-draft-n-max"
          "2"
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
