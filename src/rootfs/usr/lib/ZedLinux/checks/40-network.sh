#!/bin/bash
set -uo pipefail

status=0
ok() { printf '  OK    %-20s %s\n' "$1" "$2"; }
warn() { printf '  WARN  %-20s %s\n' "$1" "$2" >&2; status=1; }

route="$(ip route show default 2>/dev/null | head -n 1)"
if [[ -n "$route" ]]; then
    ok "Default route" "$route"
else
    warn "Default route" "none configured"
fi

up_interfaces="$(ip -o link show up 2>/dev/null | grep -vc 'LOOPBACK' || true)"
if (( up_interfaces > 0 )); then
    ok "Network interfaces" "${up_interfaces} non-loopback interface(s) up"
else
    warn "Network interfaces" "no non-loopback interfaces are up"
fi

if getent hosts deb.debian.org >/dev/null 2>&1; then
    ok "DNS resolution" "deb.debian.org resolves"
else
    warn "DNS resolution" "deb.debian.org does not resolve"
fi

exit "$status"
