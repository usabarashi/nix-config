#!/bin/bash
# Start/stop llama-server with the specified model.
# Called by SwiftBar plugin. Expands @llamaServer@ at build time.
set -euo pipefail

LLAMA_BIN="@llamaServer@"
PORT=18080
LOG="$HOME/.cache/llama-server/llama-server.log"
MAX_LOG_SIZE=104857600  # 100 MB
WEBUI_CONFIG="$HOME/.config/llama-server/webui.json"
WEBUI_DEFAULTS="$HOME/.config/llama-server/webui-defaults.json"

# Generate WebUI config with today's date in the system prompt, so the model
# knows the current date and doesn't anchor to its training cutoff.
# Merges defaults from webui-defaults.json (symlink, repo-managed) with any
# existing runtime webui.json (user/MCP settings), injects the date, and
# writes the result to webui.json (regular file, writable).
webui_config() {
    local today time
    today=$(date '+%Y-%m-%d')
    time=$(date '+%H:%M')

    mkdir -p "$(dirname "$WEBUI_CONFIG")"
    /usr/bin/python3 -c "
import json, os

defaults_path = '$WEBUI_DEFAULTS'
runtime_path = '$WEBUI_CONFIG'

# Start with defaults from repo-managed symlink
if os.path.exists(defaults_path):
    with open(defaults_path) as f:
        cfg = json.load(f)
else:
    cfg = {}

# Add any runtime-only keys (e.g., mcpServers configured via Web UI)
# that don't exist in defaults — defaults always take priority.
if os.path.exists(runtime_path):
    with open(runtime_path) as f:
        existing = json.load(f)
    for k, v in existing.items():
        if k not in cfg:
            cfg[k] = v

# Inject current date as systemMessage (always wins)
cfg['systemMessage'] = 'Today is $today. The current time is approximately $time. Treat this as the current date and time for all references.'

with open(runtime_path, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
" && [ -f "$WEBUI_CONFIG" ]
}

# ------- helpers -------

# Rotate log if it exceeds MAX_LOG_SIZE
rotate_log() {
    if [ -f "$LOG" ] && [ "$(stat -f%z "$LOG" 2>/dev/null || echo 0)" -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOG" "$LOG.old"
        echo "--- log rotated at $(date) ---"
    fi
}

# Kill any process listening on our port (graceful SIGTERM first)
kill_server() {
    local pids
    pids=$(lsof -t -i :$PORT 2>/dev/null || true)
    if [ -n "$pids" ]; then
        # Graceful termination first
        kill -TERM $pids 2>/dev/null || true
        # Wait up to 10s for the port to be released
        for i in $(seq 1 10); do
            lsof -t -i :$PORT >/dev/null 2>&1 || return 0
            sleep 1
        done
        # Force kill if still hanging
        pids=$(lsof -t -i :$PORT 2>/dev/null || true)
        [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
        sleep 1
    fi
}

WARMUP_MARKER="/tmp/llama-server-warmup.${UID}"

# Warmup: pre-compile Metal pipelines and fault model pages into memory
warmup_server() {
    local pid
    echo "$(date) warmup: waiting for server..." >> "$LOG"
    for i in $(seq 1 120); do
        pid=$(lsof -tiTCP:$PORT -sTCP:LISTEN 2>/dev/null || true)
        if [ -n "$pid" ]; then
            break
        fi
        sleep 1
    done
    if [ -z "$pid" ]; then
        echo "$(date) warmup: timeout waiting for server" >> "$LOG"
        return 1
    fi
    local warmed_pid=""
    read -r warmed_pid < "$WARMUP_MARKER" 2>/dev/null || true
    if [ "${warmed_pid:-}" = "$pid" ]; then
        echo "$(date) warmup: already warmed (pid $pid)" >> "$LOG"
        return 0
    fi
    echo "$(date) warmup: sending request (pid $pid)..." >> "$LOG"
    if curl --fail -sS --max-time 300 -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"system","content":"You are a helpful assistant."},{"role":"user","content":"Hello"}],"max_tokens":256,"temperature":0}' \
        "http://127.0.0.1:$PORT/v1/chat/completions" >/dev/null 2>&1; then
        printf "%s\n" "$pid" > "$WARMUP_MARKER"
        echo "$(date) warmup: done" >> "$LOG"
        return 0
    fi
    echo "$(date) warmup: failed" >> "$LOG"
    return 1
}

# Start model by HuggingFace repo (auto-download)
start_model() {
    local hf_repo=$1
    local alias=$2
    shift 2
    kill_server
    sleep 1
    mkdir -p "$(dirname "$LOG")"
    rotate_log
    if ! webui_config; then
        echo "ERROR: failed to generate WebUI config" >> "$LOG"
        return 1
    fi
    nohup "$LLAMA_BIN" \
        -hf "$hf_repo" \
        --alias "$alias" \
        "$@" \
        -ngl 99 --flash-attn on \
        --cache-type-k q4_0 --cache-type-v q4_0 \
        --cache-reuse 0 --cache-ram 0 \
        --slot-save-path "$HOME/.cache/llama-server-slots" \
        -b 4096 -ub 1024 \
        --jinja \
        --host 127.0.0.1 --port $PORT \
        --webui-mcp-proxy --webui-config-file "$WEBUI_CONFIG" \
        --tools read_file \
        >> "$LOG" 2>&1 &
}

# Start model from local GGUF file (no HuggingFace download)
start_model_local() {
    local model_file=$1
    local alias=$2
    shift 2
    if [ ! -f "$model_file" ]; then
        echo "ERROR: model file not found: $model_file" >> "$LOG"
        exit 1
    fi
    kill_server
    sleep 1
    mkdir -p "$(dirname "$LOG")"
    rotate_log
    if ! webui_config; then
        echo "ERROR: failed to generate WebUI config" >> "$LOG"
        return 1
    fi
    nohup "$LLAMA_BIN" \
        -m "$model_file" \
        --alias "$alias" \
        "$@" \
        -ngl 99 --flash-attn on \
        --cache-type-k q4_0 --cache-type-v q4_0 \
        --cache-reuse 0 --cache-ram 0 \
        --slot-save-path "$HOME/.cache/llama-server-slots" \
        -b 4096 -ub 1024 \
        --jinja \
        --host 127.0.0.1 --port $PORT \
        --webui-mcp-proxy --webui-config-file "$WEBUI_CONFIG" \
        --tools read_file \
        >> "$LOG" 2>&1 &
}

# ------- dispatch -------
# SwiftBar passes parameters as param1=xxx, param2=yyy, etc.
first_param=${1:-}
first_param=${first_param#param1=}
# Bolt is excluded from the coding agent on purpose: `-rea off` and
# `conversational_mode` cap replies to a sentence or two, and its 64k context is
# smaller than the agent sessions this repo typically runs. Pick it by hand.
case "${first_param:-qwen}" in
    bolt)
        # Nemotron 3.5 Bolt E4B (Gemma-4-E4B based, Q4_K_M, 6.2 GB).
        # VOICE ONLY: Open WebUI Voice Mode. Do not use it from a coding agent.
        #   -rea off              keeps TTFT low by disabling thinking
        #   --chat-template-kwargs forces speech-length replies (1-2 sentences)
        start_model \
            "nvidia/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB" \
            "nemotron-bolt-e4b" \
            --hf-file "Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf" \
            -c 65536 \
            --temp 1.0 --top-p 0.95 \
            -rea off \
            --chat-template-kwargs '{"conversational_mode":true}'
        warmup_server
        ;;
    qwen)
        kill_server
        rm -f "$HOME/.cache/llama-server-slots"/*
        start_model \
            "unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-IQ4_NL" \
            "qwen3.6-35b-a3b" \
            -c 65536 \
            --spec-type draft-mtp --spec-draft-n-max 2 \
            --temp 0.6 --top-p 0.85 --top-k 30 --min-p 0.1 \
            -rea off \
            --no-mmproj
        warmup_server
        ;;
    stopped)
        kill_server
        ;;
    *)
        echo "ERROR: Unknown model: $first_param" >> "$LOG"
        exit 1
        ;;
esac

echo "Switched to model: $first_param"