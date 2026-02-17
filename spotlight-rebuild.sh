#!/bin/bash
# spotlight-rebuild.sh — Rebuild Spotlight index with progress monitoring
# Run with: sudo bash spotlight-rebuild.sh [volume]
# Default volume: /

VOLUME="${1:-/}"

if [ "$EUID" -ne 0 ]; then
    echo "Run with sudo: sudo bash $0 $VOLUME"
    exit 1
fi

echo "=== Spotlight Index Rebuild — $(date) ==="
echo "Volume: $VOLUME"
echo ""

# Get baseline index size
IDX_DIR="/private/var/db/Spotlight-V100/BootVolume"
if [ -d "$IDX_DIR" ]; then
    OLD_SIZE=$(du -sh "$IDX_DIR" 2>/dev/null | awk '{print $1}')
    echo "Current index size: $OLD_SIZE"
fi

echo ""
echo "Erasing and rebuilding index..."
mdutil -E "$VOLUME"
echo ""
echo "Rebuild started. Monitoring progress..."
echo "(Ctrl+C to stop monitoring — rebuild continues in background)"
echo ""

# Wait for indexing to actually start
sleep 3

SPINNER='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
START_TIME=$(date +%s)

while true; do
    # Get current status
    STATUS=$(mdutil -s "$VOLUME" 2>/dev/null | tail -1 | xargs)
    MDS_CPU=$(ps aux 2>/dev/null | grep '[m]ds_stores' | awk '{total += $3} END {print total+0}')
    MDW_CPU=$(ps aux 2>/dev/null | grep '[m]dworker' | awk '{total += $3} END {printf "%.0f", total}')
    MDW_COUNT=$(ps aux 2>/dev/null | grep '[m]dworker' | wc -l | xargs)

    # Get current index size
    if [ -d "$IDX_DIR" ]; then
        CUR_SIZE=$(du -sh "$IDX_DIR" 2>/dev/null | awk '{print $1}')
    else
        CUR_SIZE="--"
    fi

    # Elapsed time
    NOW=$(date +%s)
    ELAPSED=$(( NOW - START_TIME ))
    MINS=$(( ELAPSED / 60 ))
    SECS=$(( ELAPSED % 60 ))

    # Spinner
    IDX=$(( ELAPSED % ${#SPINNER} ))
    CHAR="${SPINNER:$IDX:1}"

    # Print status line (overwrite previous)
    printf "\r  %s  [%02d:%02d]  Index: %s  |  mds_stores: %s%%  |  mdworker: %s%% (%s workers)  |  %s    " \
        "$CHAR" "$MINS" "$SECS" "$CUR_SIZE" "$MDS_CPU" "$MDW_CPU" "$MDW_COUNT" "$STATUS"

    # Check if indexing is done
    if echo "$STATUS" | grep -qi "Indexing enabled\.$" && [ "$ELAPSED" -gt 30 ]; then
        # mds_stores drops to near 0 when done
        MDS_INT=${MDS_CPU%%.*}
        if [ "${MDS_INT:-0}" -lt 5 ] && [ "${MDW_COUNT:-0}" -lt 2 ]; then
            echo ""
            echo ""
            echo "=== Rebuild complete! ==="
            echo "  Time: ${MINS}m ${SECS}s"
            if [ -d "$IDX_DIR" ]; then
                NEW_SIZE=$(du -sh "$IDX_DIR" 2>/dev/null | awk '{print $1}')
                echo "  Old index: ${OLD_SIZE:-unknown}"
                echo "  New index: $NEW_SIZE"
            fi
            echo "  Status: $(mdutil -s "$VOLUME" 2>/dev/null | tail -1 | xargs)"
            echo ""
            echo "  Test it: mdfind -name 'some file'"
            exit 0
        fi
    fi

    sleep 2
done
