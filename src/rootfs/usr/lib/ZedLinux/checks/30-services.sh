#!/bin/bash
set -uo pipefail

status=0
ok() { printf '  OK    %-20s %s\n' "$1" "$2"; }
warn() { printf '  WARN  %-20s %s\n' "$1" "$2" >&2; status=1; }

if ! command -v systemctl >/dev/null 2>&1; then
    warn "Service manager" "systemctl is unavailable"
    exit "$status"
fi

failed="$(systemctl --failed --no-legend 2>/dev/null | grep -c . || true)"
if (( failed == 0 )); then
    ok "Failed services" "none"
else
    warn "Failed services" "${failed} unit(s); run systemctl --failed"
fi

for service in ssh fail2ban; do
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        if systemctl is-active --quiet "$service"; then
            ok "Service $service" "enabled and active"
        else
            warn "Service $service" "enabled but inactive"
        fi
    fi
done

exit "$status"
