#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-042
# GAMP-SCOPE: legacy-DNS diagnostic scope (projection non-interference, not policy invention)
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
cd "${repo_root}"

out="$(nix eval --json --impure --expr '
let
  renderer = builtins.getFlake (toString ./.);
  lib = renderer.inputs.nixpkgs.lib;
  # `data.<enterprise>.<site>` IS the site object; runtimeTargets hang off it.
  mkEntry = targets: { runtimeTargets = targets; };
  diag = model: hostName: import ./s88/ControlModule/render/model-contract-diagnostics.nix {
    controlPlane = model // { deploymentHosts.${hostName} = { }; };
    inherit hostName lib;
  };
  # A routing selector with no DNS service at all: nothing to be invalid about.
  selectorOnly = diag {
    control_plane_model.data.e.s = mkEntry {
      policy = { logicalNode.name = "policy"; services.dns = { }; };
    };
  } "h";
  # A node that actually serves DNS but leaves it inventory-driven.
  inventoryDns = diag {
    control_plane_model.data.e.s = mkEntry {
      core = {
        logicalNode.name = "core";
        services.dns = { forwarders = [ "192.0.2.53" ]; };
      };
    };
  } "h";
  warn = result: builtins.filter (w: lib.hasInfix "DNS_RECURSION_INTENT_ABSENT" w) result.warnings;
in {
  selectorWarns = warn selectorOnly != [ ];
  inventoryWarns = warn inventoryDns != [ ];
}
')"

selector_warns="$(printf '%s' "$out" | jq -r .selectorWarns)"
inventory_warns="$(printf '%s' "$out" | jq -r .inventoryWarns)"

fail=0
if [ "$selector_warns" = "true" ]; then
  echo "FAIL: a runtime target with no DNS service must not be reported as inventory-driven DNS"
  fail=1
fi
if [ "$inventory_warns" != "true" ]; then
  echo "FAIL: a runtime target with inventory-driven DNS must still be reported"
  fail=1
fi
[ "$fail" -eq 0 ] && echo "PASS FS-540-HDS-010-SDS-010-SMS-042 legacy-DNS diagnostic scope"
exit "$fail"
