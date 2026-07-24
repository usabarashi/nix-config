#!/bin/bash
# SwiftBar plugin for llama-server — 5s refresh.
# Expands @switchTo@ at build time.
set -euo pipefail

SWITCH_TO="@switchTo@"
PORT=18080

# PID-keyed warmup marker. First request after server start pays a one-time
# cost (Metal pipeline compile, mmap'd weights page in from SSD) that makes
# it ~2-4x slower. Fire a throwaway request once per server lifetime so the
# user's first real request is already warm. Fire-and-forget: never block.
WARMUP_MARKER="/tmp/llama-server-warmup.${UID}"

# ------- helpers -------

get_pid() {
    lsof -tiTCP:$PORT -sTCP:LISTEN 2>/dev/null | head -1 || true
}

is_running() {
    local pid
    pid=$(get_pid)
    [ -n "$pid" ] || return 1
    local health
    health=$(curl -sS --max-time 2 "http://127.0.0.1:$PORT/health" 2>/dev/null || true)
    [ -n "$health" ]
}

# Process exists (by command-line match) but port not yet listening = transitioning
is_transitioning() {
    pgrep -qf '(^|/)[l]lama-server([[:space:]]|$)' >/dev/null 2>&1 && [ -z "$(get_pid)" ]
}

get_cpu() {
    local pid=$1
    ps -o %cpu= -p "$pid" 2>/dev/null | awk '{printf "%.1f", $1}' || true
}

get_model_alias() {
    curl -sS --max-time 2 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null \
        | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo ""
}

up() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# ------- main -------

PID=$(get_pid)

if is_running; then
    # Re-fetch PID — the process may have cycled between initial fetch and
    # health check above. Use the confirmed-listening PID for all downstream
    # operations (CPU, warmup).
    PID=$(get_pid)
    # Warmup: one throwaway request per server PID to pre-compile Metal
    # pipelines and fault model pages into memory.
    if [ -n "${PID:-}" ]; then
        read -r warmed_pid < "$WARMUP_MARKER" 2>/dev/null || true
        if [ "${warmed_pid:-}" != "$PID" ]; then
            printf "%s\n" "$PID" > "$WARMUP_MARKER"
            (curl -sS --max-time 60 -H "Content-Type: application/json" \
                -d '{"messages":[{"role":"user","content":"ping"}],"max_tokens":16,"temperature":0}' \
                "http://127.0.0.1:$PORT/v1/chat/completions" >/dev/null 2>&1 &)
        fi
    fi

    ALIAS=$(get_model_alias)
    CPU=$(get_cpu "$PID")

    if [ -n "$ALIAS" ]; then
        case "$ALIAS" in
            gemma*) DISPLAY="GEMMA 4 26B" ;;
            qwen*)  DISPLAY="QWEN3.6 35B" ;;
            *)      DISPLAY=$(echo "$ALIAS" | grep -oE '^[[:alpha:]]+' | tr '[:lower:]' '[:upper:]') ;;
        esac
    else
        DISPLAY="?"
    fi

    echo "$DISPLAY | sfimage=brain.fill"
    echo "---"
    echo "$DISPLAY"
    echo "Memory: ~18 GB | size=12"
    echo "CPU: ${CPU}% | size=12"
    echo "Port: ${PORT} | size=12"
    echo "Open Web UI | href=http://127.0.0.1:${PORT}"
    echo "---"

    # Gray out the currently active model
    case "$ALIAS" in
        *gemma*) qwen_gray="" ; gemma_gray="color=gray" ;;
        *qwen*)  qwen_gray="color=gray" ; gemma_gray="" ;;
        *)       qwen_gray="" ; gemma_gray="" ;;
    esac
    echo "Switch to Qwen3.6 35B | bash=$SWITCH_TO param1=qwen terminal=false refresh=5s ${qwen_gray}"
    echo "Switch to Gemma 4 26B | bash=$SWITCH_TO param1=gemma terminal=false refresh=5s ${gemma_gray}"
    echo "Stop | bash=$SWITCH_TO param1=stopped terminal=false refresh=5s"

elif is_transitioning; then
    echo " | sfimage=hourglass"
    echo "---"
    echo "Starting..."
    echo "---"
    # All actions grayed out during transition
    all="color=gray"
    echo "Start Qwen3.6 35B | bash=$SWITCH_TO param1=qwen terminal=false refresh=5s $all"
    echo "Start Gemma 4 26B | bash=$SWITCH_TO param1=gemma terminal=false refresh=5s $all"
    echo "Stop | bash=$SWITCH_TO param1=stopped terminal=false refresh=5s $all"

else
    echo " | sfimage=brain"
    echo "---"
    echo "Stopped"
    echo "---"
    echo "Start Qwen3.6 35B | bash=$SWITCH_TO param1=qwen terminal=false refresh=5s"
    echo "Start Gemma 4 26B | bash=$SWITCH_TO param1=gemma terminal=false refresh=5s"
fi
