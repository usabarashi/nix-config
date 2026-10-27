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

probe_health() {
    curl -sS -o /dev/null -w '%{http_code}' --max-time 2 \
        "http://127.0.0.1:$PORT/health" 2>/dev/null || true
}

# State predicates. HEALTH_CODE is probed once per render; a 200 is what makes
# the server "running", because it can become ready between the lsof and health
# probes (requiring the PID too would then report Stopped).
is_running() {
    [ "${HEALTH_CODE:-}" = "200" ]
}

# Process exists (by command-line match) but health is not ready = transitioning.
# Match on our own --port so an unrelated llama-server on another port cannot make
# this report a transition that is not happening for this instance. The launcher
# always passes `--port $PORT` as a separate argument (see switch-to.sh).
# NOTE: `pgrep -f` matches the flattened command line, not a parsed argv, and a
# server that stays unhealthy while alive shows "Starting..." forever (there is
# no error state).
is_transitioning() {
    [ "${HEALTH_CODE:-}" != "200" ] &&
        pgrep -qf "(^|/)[l]lama-server[[:space:]]+(.*[[:space:]])?--port[[:space:]]+${PORT}([[:space:]]|$)" >/dev/null 2>&1
}

get_cpu() {
    local pid=$1
    ps -o %cpu= -p "$pid" 2>/dev/null | awk '{printf "%.1f", $1}' || true
}

get_model_alias() {
    # Tolerate optional whitespace in the JSON and never fail the whole render.
    curl -sS --max-time 2 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null \
        | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 | sed -E 's/.*"([^"]*)"$/\1/' || true
}

up() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# ------- main -------

# Probe health first, then the PID: health decides the display state, the PID only
# feeds CPU/warmup, so a late-starting listener still renders as running.
HEALTH_CODE=$(probe_health)
PID=$(get_pid)

if is_running; then
    # Warmup: one throwaway request per server PID to pre-compile Metal
    # pipelines and fault model pages into memory. The marker is written before
    # the request fires, so a failed warmup is not retried until the PID
    # changes. Warmup is skipped when the marker cannot be written, otherwise
    # every 5s render would fire another 60s request.
    if [ -n "${PID:-}" ]; then
        if [ -r "$WARMUP_MARKER" ]; then
            read -r warmed_pid 2>/dev/null < "$WARMUP_MARKER" || true
        fi
        if [ "${warmed_pid:-}" != "$PID" ]; then
            if printf "%s\n" "$PID" 2>/dev/null > "$WARMUP_MARKER"; then
                (curl -sS --max-time 60 -H "Content-Type: application/json" \
                    -d '{"messages":[{"role":"user","content":"ping"}],"max_tokens":16,"temperature":0}' \
                    "http://127.0.0.1:$PORT/v1/chat/completions" >/dev/null 2>&1 &)
            fi
        fi
    fi

    ALIAS=$(get_model_alias)
    CPU=$(get_cpu "$PID")

    if [ -n "$ALIAS" ]; then
        case "$ALIAS" in
            *bolt*) DISPLAY="BOLT E4B" ; MEM="~7 GB" ;;
            *qwen*) DISPLAY="QWEN3.6 35B" ; MEM="~18 GB" ;;
            *)      DISPLAY=$(echo "$ALIAS" | grep -oE '^[[:alpha:]]+' | tr '[:lower:]' '[:upper:]' || true)
                    DISPLAY=${DISPLAY:-MODEL} ; MEM="?" ;;
        esac
    else
        DISPLAY="?"
        MEM="?"
    fi

    echo "$DISPLAY | sfimage=brain.fill"
    echo "---"
    echo "$DISPLAY"
    echo "Memory: ${MEM} | size=12"
    echo "CPU: ${CPU}% | size=12"
    echo "Port: ${PORT} | size=12"
    echo "Open Web UI | href=http://127.0.0.1:${PORT}"
    echo "---"

    # Gray out the currently active model
    case "$ALIAS" in
        *bolt*) qwen_gray="" ; bolt_gray="color=gray" ;;
        *qwen*)  qwen_gray="color=gray" ; bolt_gray="" ;;
        *)       qwen_gray="" ; bolt_gray="" ;;
    esac
    echo "Switch to Qwen3.6 35B | bash=$SWITCH_TO param1=qwen terminal=false refresh=5s ${qwen_gray}"
    echo "Switch to Bolt E4B | bash=$SWITCH_TO param1=bolt terminal=false refresh=5s ${bolt_gray}"
    echo "Stop | bash=$SWITCH_TO param1=stopped terminal=false refresh=5s"

elif is_transitioning; then
    echo " | sfimage=hourglass"
    echo "---"
    echo "Starting..."
    echo "---"
    # Start actions are useless while a launch is in flight. Stop, however, only
    # works while the port is bound (switch-to stops by port), so keep it
    # readable exactly when a listener exists: otherwise a server whose health
    # never reaches 200 would have no way out.
    all="color=gray"
    if [ -n "${PID:-}" ]; then stop_all=""; else stop_all="color=gray"; fi
    echo "Open Web UI (starting...) | href=http://127.0.0.1:${PORT} $all"
    echo "Start Qwen3.6 35B | bash=$SWITCH_TO param1=qwen terminal=false refresh=5s $all"
    echo "Start Bolt E4B | bash=$SWITCH_TO param1=bolt terminal=false refresh=5s $all"
    echo "Stop | bash=$SWITCH_TO param1=stopped terminal=false refresh=5s $stop_all"

else
    echo " | sfimage=brain"
    echo "---"
    echo "Stopped"
    echo "---"
    echo "Start Qwen3.6 35B | bash=$SWITCH_TO param1=qwen terminal=false refresh=5s"
    echo "Start Bolt E4B | bash=$SWITCH_TO param1=bolt terminal=false refresh=5s"
    all="color=gray"
    echo "Open Web UI | href=http://127.0.0.1:${PORT} $all"
fi
