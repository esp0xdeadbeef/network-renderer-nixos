#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="${repo_root}/s88/ControlModule/render/container-networks/policy-routing"

if rg -n -e 'nft' -e 'ruleset' -e 'builtins\\.match.*iifname' -e 'forwardingRulesFromRuleset' "${target_dir}" >/tmp/container-policy-routing-rendered-firewall-parsing.txt; then
  cat /tmp/container-policy-routing-rendered-firewall-parsing.txt >&2
  echo "FAIL container-policy-routing-no-rendered-firewall-parsing: policy routing must use explicit CPM forwarding intent, not rendered nft text" >&2
  exit 1
fi

echo "PASS container-policy-routing-no-rendered-firewall-parsing"
