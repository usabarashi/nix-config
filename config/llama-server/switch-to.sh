#!/bin/bash
# Start/stop llama-server with the specified model.
# Called by SwiftBar plugin. Expands @llamaServer@ at build time.
set -euo pipefail

LLAMA_BIN="@llamaServer@"
PORT=18080
LOG="$HOME/.cache/llama-server/llama-server.log"
MAX_LOG_SIZE=104857600  # 100 MB

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
    read -r warmed_pid < "$HOME/.cache/llama-server/.warmed" 2>/dev/null || true
    if [ "${warmed_pid:-}" = "$pid" ]; then
        echo "$(date) warmup: already warmed (pid $pid)" >> "$LOG"
        return 0
    fi
    echo "$(date) warmup: sending request (pid $pid)..." >> "$LOG"
    curl -sS --max-time 300 -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"system","content":"You are a helpful assistant."},{"role":"user","content":"Hello"}],"max_tokens":256,"temperature":0}' \
        "http://127.0.0.1:$PORT/v1/chat/completions" >/dev/null 2>&1
    printf "%s\n" "$pid" > "$HOME/.cache/llama-server/.warmed"
    echo "$(date) warmup: done" >> "$LOG"
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
        >> "$LOG" 2>&1 &
}

# ------- dispatch -------
# SwiftBar passes parameters as param1=xxx, param2=yyy, etc.
first_param=${1:-}
first_param=${first_param#param1=}
case "${first_param:-gemma}" in
    gemma)
        start_model \
            "unsloth/gemma-4-26B-A4B-it-GGUF:UD-IQ4_NL" \
            "gemma-4-26b-a4b" \
            -c 49152 \
            --temp 0.6 --top-p 0.85 --top-k 30 --min-p 0.1 \
            -rea off \
            --no-mmproj
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