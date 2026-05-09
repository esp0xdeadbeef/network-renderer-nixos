#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_root="$(flake_input_path network-labs)"
example_root="${labs_root}/examples/s-router-overlay-dns-lane-policy"

policy_rules="$(
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${example_root}/intent.nix" \
  INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --raw --expr '
        let
          flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
          system = "x86_64-linux";
          hostBuild = flake.lib.renderer.buildHostFromPaths {
            selector = "s-router-test";
            intentPath = builtins.getEnv "INTENT_PATH";
            inventoryPath = builtins.getEnv "INVENTORY_PATH";
            inherit system;
          };
          container = hostBuild.renderedHost.containers."s-router-policy-only";
          evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ container.config ];
          };
        in
        evaluated.config.networking.nftables.ruleset
      '
)"

for uplink in a b; do
  grep -F "iifname \"downstr-client2\" oifname \"up-cl2-${uplink}\" accept comment \"allow-tenants-to-uplinks\"" \
    <<<"${policy_rules}" >/dev/null \
    || fail "missing client2 public-egress allow for up-cl2-${uplink}; renderer dropped an intent tenant-set member whose policy lane uses an abbreviated runtime interface"

  grep -F "iifname \"downstr-client2\" oifname \"up-cl2-${uplink}\" meta l4proto udp udp dport { 53 } drop comment \"deny-sitea-dns-to-uplinks\"" \
    <<<"${policy_rules}" >/dev/null \
    || fail "missing client2 UDP DNS leak block for up-cl2-${uplink}"

  grep -F "iifname \"downstr-client2\" oifname \"up-cl2-${uplink}\" meta l4proto tcp tcp dport { 53 } drop comment \"deny-sitea-dns-to-uplinks\"" \
    <<<"${policy_rules}" >/dev/null \
    || fail "missing client2 TCP DNS leak block for up-cl2-${uplink}"
done

pass "client2-policy-uplink-firewall"
