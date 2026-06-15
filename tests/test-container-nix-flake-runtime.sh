#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"

nix_eval_true_or_fail "container-nix-flake-runtime" env REPO_ROOT="${repo_root}" \
INTENT_PATH="${example_root}/intent.nix" \
INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
        host = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        container = host.renderedHost.containers."s-router-access-client";
        evaluated = lib.nixosSystem {
          inherit (pkgs) system;
          modules = [ container.config ];
        };
      in
        lib.hasInfix "experimental-features = nix-command flakes" evaluated.config.nix.extraOptions
    '

echo "PASS container-nix-flake-runtime"
