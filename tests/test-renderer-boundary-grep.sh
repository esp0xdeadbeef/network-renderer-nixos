#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

check_absent() {
  local label="$1"
  shift

  local matches
  matches="$(rg -n "$@" "${repo_root}/s88" || true)"
  if [[ -n "$matches" ]]; then
    printf '%s\n%s\n' "renderer boundary violation: ${label}" "$matches" >&2
    return 1
  fi
}

check_absent \
  "provider names must not drive neutral renderer behavior" \
  'hasInfix "nebula"|stringContains "nebula"|hasInfix "wireguard"|stringContains "wireguard"|hasInfix "openvpn"|stringContains "openvpn"'

check_absent \
  "neutral renderer must not hardcode provider runtime interfaces" \
  '"nebula1"'

check_absent \
  "lane selection must come from CPM data, not local name tokens" \
  'stringContains "east-west"|stringContains "-ew"|stringContains "site-c-storage"|stringContains "storage"|stringContains "-sto"|stringContains "isp-a"|stringContains "isp-b"'

pass "renderer boundary grep"
