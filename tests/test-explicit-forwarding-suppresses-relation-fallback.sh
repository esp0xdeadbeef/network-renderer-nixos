#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"

nix_eval_true_or_fail "explicit-forwarding-suppresses-relation-fallback" env REPO_ROOT="${repo_root}" \
INTENT_PATH="${example_root}/intent.nix" \
INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        system = "x86_64-linux";
        builtB = flake.lib.containers.buildForBox {
          boxName = "s-router-test";
          inherit system;
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        builtC = flake.lib.containers.buildForBox {
          boxName = "s-router-hetzner-anywhere";
          inherit system;
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        evalContainer = container:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ container.config ];
          }).config;
        has = flake.inputs.nixpkgs.lib.hasInfix;
        branchRules = (evalContainer builtB."b-router-upstream-selector").networking.nftables.ruleset;
        hetznerRules = (evalContainer builtC."c-router-upstream-selector").networking.nftables.ruleset;
      in
        has "iifname \"core-isp\" oifname \"policy-branch\" accept" branchRules
        && has "iifname \"core-nebula\" oifname \"pol-branch-ew\" ip saddr" branchRules
        && has "iifname \"core\" oifname \"policy-wan\" accept" hetznerRules
        && has "iifname \"core-nebula\" oifname \"pol-client-ew\" ip saddr" hetznerRules
        && !(has "iifname \"core-isp\" oifname \"pol-branch-ew\" accept" branchRules)
        && !(has "iifname \"core-nebula\" oifname \"policy-branch\" accept" branchRules)
        && !(has "iifname \"core\" oifname \"pol-client-ew\" accept" hetznerRules)
        && !(has "iifname \"core-nebula\" oifname \"policy-wan\" accept" hetznerRules)
    '

echo "PASS explicit-forwarding-suppresses-relation-fallback"
