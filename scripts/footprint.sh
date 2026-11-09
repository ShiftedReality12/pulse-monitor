#!/bin/zsh
# Usage: scripts/footprint.sh <seconds> <interval> <label=pid>...
# Samples RSS (KB), ps %CPU (lifetime-decayed) and cumulative CPU time for each pid, read-only, and prints raw rows.
set -eu
seconds=$1; interval=$2; shift 2
end=$(( $(date +%s) + seconds ))
print "# label pid epoch rss_kb ps_pcpu cputime"
while true; do
    now=$(date +%s)
    for item in "$@"; do
        label=${item%%=*}; pid=${item##*=}
        row=$(ps -o rss=,%cpu=,time= -p "$pid" || true)
        print -r -- "$label $pid $now $row"
    done
    (( now + interval > end )) && break
    sleep "$interval"
done
