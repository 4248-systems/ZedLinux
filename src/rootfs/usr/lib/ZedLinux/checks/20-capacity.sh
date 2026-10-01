#!/bin/bash
set -uo pipefail

status=0
ok() { printf '  OK    %-20s %s\n' "$1" "$2"; }
warn() { printf '  WARN  %-20s %s\n' "$1" "$2" >&2; status=1; }

while read -r use mount; do
    use="${use%%%}"
    if (( use >= 90 )); then
        warn "Filesystem $mount" "${use}% used"
    else
        ok "Filesystem $mount" "${use}% used"
    fi
done < <(df -P -x tmpfs -x devtmpfs -x squashfs | awk 'NR > 1 {print $5, $6}')

memory_pct="$(free | awk '/^Mem:/{printf "%.0f", ($2-$7)/$2*100}')"
if (( memory_pct >= 90 )); then
    warn "Memory" "${memory_pct}% in use"
else
    ok "Memory" "${memory_pct}% in use"
fi

swap_total="$(free | awk '/^Swap:/{print $2}')"
swap_used="$(free | awk '/^Swap:/{print $3}')"
if (( swap_total == 0 )); then
    ok "Swap" "not configured"
elif (( swap_used * 100 / swap_total >= 50 )); then
    warn "Swap" "$((swap_used * 100 / swap_total))% in use"
else
    ok "Swap" "$((swap_used * 100 / swap_total))% in use"
fi

exit "$status"
