#!/bin/bash
# Unified notification script for LLM coding agents.
# Usage: bash notify.sh --app <name> --event <notification|stop>
#
# Auto-detects IDE/terminal environment and adds click-to-open action:
#   VSCode, Terminal.app

set -euo pipefail

# --- Parse arguments ---
APP=""
EVENT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)   [[ $# -ge 2 ]] || { echo "Error: --app requires a value" >&2; exit 1; }
                 APP="$2"; shift 2 ;;
        --event) [[ $# -ge 2 ]] || { echo "Error: --event requires a value" >&2; exit 1; }
                 EVENT="$2"; shift 2 ;;
        *)       shift ;;
    esac
done

if [[ -z "$APP" ]]; then
    echo "Error: --app argument is required" >&2
    exit 1
fi
if [[ -z "$EVENT" ]]; then
    echo "Error: --event argument is required" >&2
    exit 1
fi

# --- Read hook input from stdin ---
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

# Guard against recursive stop hooks
if [[ "$EVENT" = "stop" ]]; then
    STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // empty' 2>/dev/null || echo "")
    if [[ "$STOP_HOOK_ACTIVE" = "true" ]]; then
        exit 0
    fi
fi

PROJECT_DIR="$PWD"
SESSION_SHORT="${SESSION_ID:0:8}"

# --- Gather project info ---
GIT_TOPLEVEL=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "${GIT_TOPLEVEL:-}" ]]; then
    REPO_NAME=$(basename "$GIT_TOPLEVEL")
else
    REPO_NAME=$(basename "$PROJECT_DIR")
fi
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# --- Determine message and sound by event type ---
case "$EVENT" in
    notification)
        TITLE="${APP} - Attention"
        SOUND="Ping"
        ;;
    stop)
        TITLE="${APP} - Complete"
        SOUND="Funk"
        ;;
    *)
        echo "Error: Unknown event type: $EVENT" >&2
        exit 1
        ;;
esac

# --- Build subtitle: git info or directory ---
if [[ -n "$BRANCH" ]]; then
    SUBTITLE="${REPO_NAME} @ ${BRANCH}"
else
    SUBTITLE="${PROJECT_DIR}"
fi
MESSAGE="Session: ${SESSION_SHORT}"

# --- Detect IDE/terminal environment ---
# Priority: VSCode (extension or terminal) > Terminal.app
detect_ide() {
    if [[ -n "${VSCODE_PID:-}" || "${TERM_PROGRAM:-}" = "vscode" ]]; then
        echo "vscode"
    elif [[ "${TERM_PROGRAM:-}" = "Apple_Terminal" ]]; then
        echo "terminal"
    else
        echo "unknown"
    fi
}

IDE=$(detect_ide)

# --- Build click action arguments for terminal-notifier ---
#   -open    : opens a URL/URI scheme (VSCode URI targets specific project window)
#   -activate: brings an app to foreground by Bundle ID (Terminal.app)
CLICK_ACTION=()
case "$IDE" in
    vscode)   CLICK_ACTION=("-open" "vscode://file${PROJECT_DIR// /%20}") ;;
    terminal) CLICK_ACTION=("-activate" "com.apple.Terminal") ;;
esac

# --- Build terminal-notifier arguments ---
NOTIFY_ARGS=(
    -title "$TITLE"
    -subtitle "$SUBTITLE"
    -message "$MESSAGE"
    -sound "$SOUND"
    -group "${APP// /-}-${SESSION_SHORT}"
    "${CLICK_ACTION[@]}"
)

# --- Send notification ---
terminal-notifier "${NOTIFY_ARGS[@]}"
