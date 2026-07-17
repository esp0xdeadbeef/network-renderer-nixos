#!/usr/bin/env bash
set -euo pipefail

interface="${1:?interface name is required}"
operstate_root="${OPERSTATE_ROOT:-/sys/class/net}"
attempts="${WAIT_INTERFACE_ATTEMPTS:-80}"
interval="${WAIT_INTERFACE_INTERVAL:-0.25}"

for ((attempt = 1; attempt <= attempts; attempt++)); do
  state=""
  if ip link show "${interface}" >/dev/null 2>&1 \
    && [[ -r "${operstate_root}/${interface}/operstate" ]]; then
    read -r state <"${operstate_root}/${interface}/operstate"
  fi
  if [[ "${state}" == "up" ]]; then
    exit 0
  fi
  sleep "${interval}"
done

printf 'interface readiness timeout: interface=%s state=not-up\n' "${interface}" >&2
exit 1
