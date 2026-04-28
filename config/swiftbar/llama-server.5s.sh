#!/usr/bin/env bash
# <bitbar.title>llama-server</bitbar.title>
# <bitbar.author>nix-config</bitbar.author>
# <bitbar.desc>Status & control for the local llama-server (org.nix-community.home.llama-server)</bitbar.desc>
# <bitbar.dependencies>bash, curl, launchctl, footprint, lsof</bitbar.dependencies>

set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

UID_NUM=$(id -u)
LABEL="gui/${UID_NUM}/org.nix-community.home.llama-server"
HEALTH=$(curl -sS --max-time 1 http://127.0.0.1:8080/health 2>/dev/null || echo "")
PID=$(pgrep -x "llama-server" 2>/dev/null | head -1 || true)
DOWNLOADING=$(find "$HOME/.cache/huggingface/hub" -maxdepth 4 -name "*.downloadInProgress" 2>/dev/null | head -1)

STATE="stopped"
SUBSTATE=""
HOST_GB="?"
MODEL_GB="?"

if echo "$HEALTH" | grep -q '"status":"ok"'; then
    STATE="running"
    if [ -n "${PID:-}" ]; then
        # `ps -o rss=` requires entitlement on recent macOS; `footprint` does not
        # and reports physical footprint (Apple's memory-pressure metric).
        # This covers KV cache, inference buffers, heap — but NOT model weights:
        # with `-ngl 99`, llama.cpp mmaps the GGUF and Metal pins it as GPU
        # buffer in unified memory, which is excluded from process accounting.
        # Read the mmap'd blob sizes from lsof to surface the hidden bulk.
        # `-f bytes` avoids unit/locale ambiguity (default `formatted` switches
        # KB/MB/GB suffixes once the process grows past each boundary).
        MEM_BYTES=$(footprint -f bytes "$PID" 2>/dev/null | sed -nE 's/.*Footprint:[[:space:]]+([0-9]+) B.*/\1/p' | head -1)
        if [ -n "${MEM_BYTES:-}" ]; then
            HOST_GB=$(awk "BEGIN { printf \"%.1f\", ${MEM_BYTES} / 1024 / 1024 / 1024 }")
        fi
        # `lsof -Fn` is field-mode output (one path per `n`-prefixed line),
        # which is path-with-space safe (vs. `awk '$NF'`). Match both `blobs/`
        # (HF cache layout) and `snapshots/<commit>/` (symlink-resolved path,
        # depending on macOS resolution behaviour).
        MODEL_BYTES=$(lsof -p "$PID" -n -P -Fn 2>/dev/null \
            | sed -n 's/^n//p' \
            | grep -E "huggingface/hub/models--.*/(blobs|snapshots)/" \
            | sort -u \
            | while read -r f; do [ -f "$f" ] && stat -f "%z" "$f" 2>/dev/null; done \
            | awk '{ sum += $1 } END { print sum+0 }')
        if [ "${MODEL_BYTES:-0}" -gt 0 ]; then
            MODEL_GB=$(awk "BEGIN { printf \"%.1f\", ${MODEL_BYTES} / 1024 / 1024 / 1024 }")
        fi
    fi
elif [ -n "${PID:-}" ]; then
    STATE="loading"
    if [ -n "${DOWNLOADING:-}" ]; then
        SUBSTATE="downloading"
    elif echo "$HEALTH" | grep -qE 'Loading model|unavailable_error'; then
        SUBSTATE="loading model"
    else
        SUBSTATE="starting"
    fi
fi

# Menu bar line — state is encoded in the symbol shape only. SwiftBar forces
# `isTemplate = true` on `sfimage` (MenuLineParameters.swift), so `sfcolor`
# has no effect on the rendered icon. Memory size shows in the dropdown.
case "$STATE" in
    running) echo " | sfimage=brain.fill" ;;
    loading) echo " | sfimage=hourglass" ;;
    stopped) echo " | sfimage=brain" ;;
esac

echo "---"

# Dropdown
case "$STATE" in
    running)
        echo "Status: running (pid $PID)"
        echo "Host:  ${HOST_GB} GiB"
        echo "Model: ${MODEL_GB} GiB (Metal)"
        echo "Endpoint: http://127.0.0.1:8080"
        echo "---"
        echo "Stop | bash=/bin/launchctl param1=kill param2=SIGTERM param3=$LABEL terminal=false refresh=true"
        echo "Restart | bash=/bin/launchctl param1=kickstart param2=-k param3=$LABEL terminal=false refresh=true"
        ;;
    loading)
        case "$SUBSTATE" in
            downloading) echo "Status: downloading model…" ;;
            "loading model") echo "Status: loading model…" ;;
            *) echo "Status: starting…" ;;
        esac
        [ -n "${PID:-}" ] && echo "PID: $PID"
        echo "---"
        echo "Stop | bash=/bin/launchctl param1=kill param2=SIGTERM param3=$LABEL terminal=false refresh=true"
        ;;
    stopped)
        echo "Status: stopped"
        echo "---"
        echo "Start | bash=/bin/launchctl param1=kickstart param2=$LABEL terminal=false refresh=true"
        ;;
esac

echo "---"
echo "Open log | bash=/usr/bin/open param1=$HOME/Library/Logs/llama-server/stderr.log terminal=false"
echo "Refresh | refresh=true"
