#!/bin/bash
set -uo pipefail

status=0
ok() { printf '  OK    %-20s %s\n' "$1" "$2"; }
warn() { printf '  WARN  %-20s %s\n' "$1" "$2" >&2; status=1; }

if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -q '^Status: active'; then
        ok "Firewall" "ufw active"
    else
        warn "Firewall" "ufw inactive"
    fi
else
    warn "Firewall" "ufw is not installed"
fi

if [[ -r /etc/ssh/sshd_config ]]; then
    permit_root="$(awk 'tolower($1)=="permitrootlogin" {value=tolower($2)} END {print value}' /etc/ssh/sshd_config)"
    case "$permit_root" in
        no|prohibit-password) ok "SSH root login" "restricted" ;;
        yes) warn "SSH root login" "password login permitted" ;;
        *) warn "SSH root login" "not explicitly configured" ;;
    esac
fi

if command -v apt >/dev/null 2>&1; then
    held="$(apt-mark showhold 2>/dev/null | wc -l)"
    (( held == 0 )) && ok "Held packages" "none" || warn "Held packages" "${held} package(s) held"
fi

exit "$status"
