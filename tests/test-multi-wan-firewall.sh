#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_root="$(flake_input_path network-labs)"
example_dir="${labs_root}/examples/multi-wan"
intent_path="${example_dir}/intent.nix"
inventory_path="${example_dir}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix: ${inventory_path}"

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
          containerNames = builtins.attrNames hostBuild.renderedHost.containers;
          policyNames = builtins.filter (name: builtins.match ".*s-router-policy$" name != null) containerNames;
          container =
            if builtins.length policyNames >= 1 then
              hostBuild.renderedHost.containers.${builtins.head policyNames}
            else
              throw "multi-wan policy container not found";
          evaluated = flake.inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ container.config ];
          };
        in
        evaluated.config.networking.nftables.ruleset
      '
)"

grep -q 'allow-tenants-to-uplinks' <<<"${policy_rules}" \
  || fail "missing allow-tenants-to-uplinks in multi-wan policy rules"

rule_count="$(grep -c 'allow-tenants-to-uplinks' <<<"${policy_rules}")"
[[ "${rule_count}" -ge 4 ]] \
  || fail "expected multiple multi-wan forward rules, got ${rule_count}"

pass "multi-wan-firewall"
