#!/bin/sh
# Log rotation wrapper for llama-server. Invoked by launchd with the real
# llama-server binary (and its arguments) as positional parameters.
#
# Rotation policy: keep the last 5 generations as gzip-compressed files
# (stderr.log.1.gz ... stderr.log.5.gz). When the active log exceeds
# MAX_BYTES, the oldest generation is dropped, the rest shift up by one,
# and the active log is compressed into .1.gz and truncated in place.
# Truncation is safe because launchd opens stderr.log in append mode, so
# llama-server's subsequent writes seek to EOF (0 after truncation).
#
# Disk ceiling: 5 generations × ~2 MB compressed ≈ 10 MB. Reset to fresh
# log on every llama-server start that crosses the threshold.

set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG="$HOME/Library/Logs/llama-server/stderr.log"
MAX_BYTES=$((10 * 1024 * 1024))

# `stat ... || echo 0` collapses the missing-file path and the size-check into
# a single race-free read: a delete between an `[ -f ]` test and `stat` would
# otherwise leave the comparison with an empty string and abort the script
# under `set -e` before `exec "$@"` runs, blocking the launchd start.
filesize=$(stat -f %z "$LOG" 2>/dev/null || echo 0)
if [ "$filesize" -gt "$MAX_BYTES" ]; then
    [ -f "$LOG.5.gz" ] && rm -f "$LOG.5.gz"
    for i in 4 3 2 1; do
        [ -f "$LOG.$i.gz" ] && mv "$LOG.$i.gz" "$LOG.$((i+1)).gz"
    done
    gzip -c "$LOG" > "$LOG.1.gz" && : > "$LOG"
fi

exec "$@"
