#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
trap 'rm -f "${result_json}"' EXIT

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --json \
  --expr '
    let
      flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
      lib = flake.inputs.nixpkgs.lib;
      upstreamSelector = import (builtins.getEnv "REPO_ROOT" + "/s88/ControlModule/firewall/policy/upstream-selector.nix") {
        inherit lib;
        interfaceView.interfaceEntries = [
          {
            name = "core-nebula";
            sourceKind = "p2p";
            iface.interfaceClass.coreFacing = true;
          }
          {
            name = "core-wan";
            sourceKind = "p2p";
            iface.interfaceClass.coreFacing = true;
          }
        ];
        forwardingIntent = {
          authoritativeUpstreamSelectorForwarding = true;
          normalizedExplicitForwardPairs = [
            {
              action = "accept";
              "in" = [ "core-nebula" ];
              "out" = [ "core-wan" ];
              sourcePrefixes = [ "10.19.0.8/32" ];
              comment = "explicit-cpm-forward";
            }
          ];
        };
      };
    in
      upstreamSelector.forwardRules
  ' >"${result_json}"

if ! _jq -e '
  any(
    .[];
    contains("iifname \"core-nebula\"")
    and contains("oifname \"core-wan\"")
    and contains("ip saddr 10.19.0.8/32")
    and contains("accept comment \"explicit-cpm-forward\"")
  )
' "${result_json}" >/dev/null; then
  echo "FAIL upstream-selector-explicit-forwarding-projection: explicit CPM forwarding pair was filtered or rewritten" >&2
  _jq -S . "${result_json}" >&2
  exit 1
fi

pass "upstream-selector-explicit-forwarding-projection"
