#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="${repo_root}/s88/ControlModule/firewall/mapping/policy-endpoints"

if rg -n 'builtins\.match.*--access-|builtins\.match.*--uplink-|hasInfix.*--access-|hasInfix.*--uplink-|hasPrefix "uplink-"|removePrefix "uplink-"' "${target_dir}" >/tmp/policy-endpoint-link-parsing.txt; then
  cat /tmp/policy-endpoint-link-parsing.txt >&2
  echo "FAIL policy-endpoint-no-generated-link-parsing: endpoint mapping must use CPM lane metadata, not generated p2p link-name tokens" >&2
  exit 1
fi

echo "PASS policy-endpoint-no-generated-link-parsing"
