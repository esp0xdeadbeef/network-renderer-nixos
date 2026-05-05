#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
labs_root="$(
  jq -r '
    . as $lock
    | .nodes.root.inputs["network-labs"] as $node
    | $lock.nodes[$node].locked
    | "github:\(.owner)/\(.repo)/\(.rev)"
  ' "${repo_root}/flake.lock"
)"

ruleset="$(
  nix eval --raw --impure --expr '
    let
      flake = builtins.getFlake (toString '"${repo_root}"');
      built = flake.lib.containers.buildForBox {
        intentPath = (builtins.getFlake "'"${labs_root}"'").outPath + "/examples/s-router-overlay-dns-lane-policy/intent.nix";
        inventoryPath = (builtins.getFlake "'"${labs_root}"'").outPath + "/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix";
        boxName = "s-router-hetzner-anywhere";
      };
    in
      built."c-router-upstream-selector".specialArgs.s88Firewall.ruleset
  '
)"

if grep -q 'policy-client-wan' <<<"${ruleset}"; then
  echo "firewall ruleset leaked unresolved logical port token policy-client-wan" >&2
  exit 1
fi

awk '
  match($0, /(iifname|oifname) "([^"]+)"/, m) && length(m[2]) > 15 {
    print "Linux interface name exceeds 15 characters: " m[2] > "/dev/stderr"
    failed = 1
  }
  END { exit failed }
' <<<"${ruleset}"
