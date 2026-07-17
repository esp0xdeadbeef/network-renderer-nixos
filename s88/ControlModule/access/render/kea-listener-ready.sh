#!/usr/bin/env bash
set -euo pipefail

port="${1:?UDP port is required}"
attempts="${KEA_LISTENER_ATTEMPTS:-20}"
interval="${KEA_LISTENER_INTERVAL:-0.1}"

for ((attempt = 1; attempt <= attempts; attempt++)); do
  if ss -H -u -l -n "sport = :${port}" | grep -q .; then
    exit 0
  fi
  sleep "${interval}"
done

printf 'Kea listener readiness timeout: udp-port=%s\n' "${port}" >&2
exit 1
