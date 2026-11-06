#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"

nix_eval_true_or_fail "container-nix-disabled" env REPO_ROOT="${repo_root}" \
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
        cfg = evaluated.config;
        services = cfg.systemd.services;
      in
        # Containers never build, substitute or garbage-collect Nix packages: the
        # host supplies the closure read-only. Rendering nix support inside each
        # scope only added per-container nix-daemon/nix-gc/nix-optimise services
        # with no modelled effect, so the renderer disables it and must keep it
        # disabled.
        cfg.nix.enable == false
        && !(services ? nix-daemon)
        && !(services ? nix-gc)
        && !(services ? nix-optimise)
    '

echo "PASS container-nix-disabled"
