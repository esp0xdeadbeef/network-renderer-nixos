#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"

nix_eval_true_or_fail "host-build-artifact-module" env REPO_ROOT="${repo_root}" \
INTENT_PATH="${example_root}/intent.nix" \
INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        host = flake.lib.renderer.buildHostFromPaths {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        etc = host.artifactModule.environment.etc;
      in
        builtins.hasAttr "network-artifacts/compiler.json" etc
        && builtins.hasAttr "network-artifacts/forwarding.json" etc
        && builtins.hasAttr "network-artifacts/control-plane.json" etc
        && builtins.hasAttr "network-artifacts/intent.json" etc
        && builtins.hasAttr "network-artifacts/inventory.json" etc
        && builtins.hasAttr "network-artifacts/rendered-host.json" etc
        && builtins.hasAttr "network-artifacts/debug-bundle.json" etc
        && builtins.hasAttr "network-renderer/network-renderer-nixos.json" etc
    '

echo "PASS host-build-artifact-module"
