#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"

nix_eval_true_or_fail "provider-overlay-interface-not-materialized" env \
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${example_root}/intent.nix" \
  INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
        repoPath = builtins.getEnv "REPO_ROOT";
        intentPath = builtins.getEnv "INTENT_PATH";
        inventoryPath = builtins.getEnv "INVENTORY_PATH";
        flake = builtins.getFlake repoRoot;
        lib = flake.inputs.nixpkgs.lib;
        system = "x86_64-linux";
        built = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "s-router-test";
          inherit system intentPath inventoryPath;
        };
        runtimeTarget = built.runtimeTargets."espbranch.site-b.espbranch-site-b-b-router-core-nebula";
        rendered = built.renderedHost.containers."b-router-core-nebula";
        evaluated =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ rendered.config ];
          }).config;
        networks = evaluated.systemd.network.networks;
        providerRouteServices =
          lib.filterAttrs
            (name: _value: lib.hasPrefix "s88-provider-route" name)
            (evaluated.systemd.services or { });
        nftRules = evaluated.networking.nftables.ruleset or "";
        extraVethNames = builtins.attrNames (rendered.extraVeths or { });
        interfaceNames = builtins.attrNames (runtimeTarget.interfaces or { });
        hasOverlayName = name: lib.hasInfix "overlay" name || lib.hasInfix "ovly" name;
      in
        !(builtins.any hasOverlayName interfaceNames)
        && !(builtins.any hasOverlayName extraVethNames)
        && !(networks ? "10-overlay-west")
        && !(networks ? "10-overlay-east-west")
        && (builtins.length (builtins.attrNames providerRouteServices)) >= 2
        && lib.hasInfix "iifname \"nebula1\" accept" nftRules
        && lib.hasInfix "iifname \"nebula1\" oifname \"upstream\" accept" nftRules
        && lib.hasInfix "iifname \"upstream\" oifname \"nebula1\"" nftRules
    '

echo "PASS provider-overlay-interface-not-materialized"
