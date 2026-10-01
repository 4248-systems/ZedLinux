#!/bin/bash
set -uo pipefail

status=0
ok() { printf '  OK    %-20s %s\n' "$1" "$2"; }
warn() { printf '  WARN  %-20s %s\n' "$1" "$2" >&2; status=1; }

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    ok "Operating system" "${PRETTY_NAME:-unknown}"
else
    warn "Operating system" "/etc/os-release is missing"
fi

kernel="$(uname -r)"
[[ -n "$kernel" ]] && ok "Kernel" "$kernel" || warn "Kernel" "could not identify kernel"

if command -v timedatectl >/dev/null 2>&1; then
    sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
    [[ "$sync" == "yes" ]] && ok "Clock synchronization" "synchronized" || warn "Clock synchronization" "not synchronized"
fi

exit "$status"
