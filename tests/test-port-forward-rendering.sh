#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_dir="$(flake_input_path network-labs)/examples/single-wan"
intent_path="${example_dir}/intent.nix"
inventory_path="${example_dir}/inventory-nixos.nix"

core_rules="$(
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --raw --expr '
      let
        repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        flake = builtins.getFlake repoRoot;
        system = "x86_64-linux";
        hostBuild = flake.lib.renderer.buildHostFromPaths {
          selector = "lab-host";
          inherit system intentPath inventoryPath;
        };
        container = hostBuild.renderedHost.containers.s-router-core-wan;
        evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ container.config ];
        };
      in
      evaluated.config.networking.nftables.ruleset
    '
)"

policy_rules="$(
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --raw --expr '
      let
        repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        flake = builtins.getFlake repoRoot;
        system = "x86_64-linux";
        hostBuild = flake.lib.renderer.buildHostFromPaths {
          selector = "lab-host";
          inherit system intentPath inventoryPath;
        };
        container = hostBuild.renderedHost.containers.s-router-policy;
        evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ container.config ];
        };
      in
      evaluated.config.networking.nftables.ruleset
    '
)"

grep -q 'dnat to 10.20.10.10' <<<"${core_rules}" \
  || fail "missing jump-host DNAT target in core rules"
grep -q 'tcp dport 22 dnat to 10.20.10.10' <<<"${core_rules}" \
  || fail "missing jump-host TCP port-forward rule"
grep -q 'dnat to 10.20.15.10' <<<"${core_rules}" \
  || fail "missing admin-web DNAT target in core rules"
grep -q 'tcp dport 80 dnat to 10.20.15.10' <<<"${core_rules}" \
  || fail "missing admin-web HTTP port-forward rule"
grep -q 'tcp dport 443 dnat to 10.20.15.10' <<<"${core_rules}" \
  || fail "missing admin-web HTTPS port-forward rule"
grep -q 'allow-wan-to-admin-web' <<<"${policy_rules}" \
  || fail "missing admin-web forward rule on policy-only"
grep -q 'iifname "ens3" oifname "ens7" meta l4proto tcp tcp dport { 80, 443 } accept comment "allow-wan-to-admin-web"' <<<"${policy_rules}" \
  || fail "missing WAN ingress rule for admin-web on first uplink"
grep -q 'iifname "ens4" oifname "ens7" meta l4proto tcp tcp dport { 80, 443 } accept comment "allow-wan-to-admin-web"' <<<"${policy_rules}" \
  || fail "missing WAN ingress rule for admin-web on second uplink"
grep -q 'iifname "ens5" oifname "ens7" meta l4proto tcp tcp dport { 80, 443 } accept comment "allow-wan-to-admin-web"' <<<"${policy_rules}" \
  || fail "missing WAN ingress rule for admin-web on third uplink"

pass "port-forward-rendering"
