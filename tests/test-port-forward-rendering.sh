#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

fixture_dir="${repo_root}/tests/fixtures/passing/s-router-test"
intent_path="${fixture_dir}/intent.nix"
inventory_path="${fixture_dir}/inventory.nix"

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
          selector = "s-router-test";
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

pass "port-forward-rendering"
