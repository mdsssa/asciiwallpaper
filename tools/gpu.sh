#!/bin/bash
# Samples the Mac's GPU utilization without sudo or Activity Monitor.
# Usage: tools/gpu.sh [seconds]
set -u
DURATION="${1:-10}"
total=0
count=0
min=999
max=0
printf "Sampling GPU for %s s...\n" "$DURATION"
for ((i = 0; i < DURATION; i++)); do
    line=$(ioreg -r -c IOAccelerator -d 1 -w 0 2>/dev/null \
        | sed -n 's/.*"Device Utilization %"=\([0-9][0-9]*\).*/\1/p' | head -1)
    if [ -z "$line" ]; then
        line=$(ioreg -r -c IOAccelerator -d 1 -w 0 2>/dev/null \
            | sed -n 's/.*"Renderer Utilization %"=\([0-9][0-9]*\).*/\1/p' | head -1)
    fi
    if [ -z "$line" ]; then
        echo "No GPU utilization data from IORegistry on this Mac." >&2
        exit 1
    fi
    printf "  %2s%%\n" "$line"
    total=$((total + line))
    count=$((count + 1))
    [ "$line" -lt "$min" ] && min=$line
    [ "$line" -gt "$max" ] && max=$line
    sleep 1
done
awk -v t="$total" -v c="$count" -v lo="$min" -v hi="$max" \
    'BEGIN { printf "average %.1f%%  min %d%%  max %d%%\n", t / c, lo, hi }'
