#!/usr/bin/env bash
# <bitbar.title>llama-server</bitbar.title>
# <bitbar.author>nix-config</bitbar.author>
# <bitbar.desc>Status & control for the local llama-server (org.nix-community.home.llama-server)</bitbar.desc>
# <bitbar.dependencies>bash, curl, launchctl</bitbar.dependencies>

set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

UID_NUM=$(id -u)
LABEL="gui/${UID_NUM}/org.nix-community.home.llama-server"
HEALTH=$(curl -sS --max-time 1 http://127.0.0.1:8080/health 2>/dev/null || echo "")
PID=$(pgrep -f "llama-server" 2>/dev/null | head -1 || true)

STATE="stopped"
MEM_GB="?"

if echo "$HEALTH" | grep -q '"status":"ok"'; then
    STATE="running"
    if [ -n "${PID:-}" ]; then
        MEM_KB=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ' || true)
        if [ -n "${MEM_KB:-}" ]; then
            MEM_GB=$(awk "BEGIN { printf \"%.1f\", ${MEM_KB} / 1024 / 1024 }")
        fi
    fi
elif echo "$HEALTH" | grep -qE 'Loading model|unavailable_error'; then
    STATE="loading"
fi

# Menu bar line — SF Symbol "brain.fill" only. Memory size is shown in the
# dropdown, not on the menu bar itself.
case "$STATE" in
    running) echo " | sfimage=brain.fill sfcolor=#FF2D55" ;;
    loading) echo " | sfimage=brain.fill sfcolor=#FF2D55" ;;
    stopped) echo " | sfimage=brain.fill sfcolor=#8E8E93" ;;
esac

echo "---"

# Dropdown
case "$STATE" in
    running)
        echo "Status: running (pid $PID)"
        echo "Memory: ${MEM_GB} GiB RSS"
        echo "Endpoint: http://127.0.0.1:8080"
        echo "---"
        echo "Stop | bash=/bin/launchctl param1=kill param2=SIGTERM param3=$LABEL terminal=false refresh=true"
        echo "Restart | bash=/bin/launchctl param1=kickstart param2=-k param3=$LABEL terminal=false refresh=true"
        ;;
    loading)
        echo "Status: loading model…"
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
