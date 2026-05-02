#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-test-three-site"

nix_eval_true_or_fail "host-build-container-selection" env REPO_ROOT="${repo_root}" \
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
          disabled = {
            s-router-access-client2 = true;
          };
          containerDefaults = {
            additionalCapabilities = [
              "CAP_NET_ADMIN"
              "CAP_NET_RAW"
              "CAP_SYS_ADMIN"
            ];
            allowedDevices = [
              "/dev/net/tun"
            ];
          };
        };
        containers = host.renderedHost.containers;
        accessClient = containers."s-router-access-client";
      in
        !(builtins.hasAttr "s-router-access-client2" containers)
        && builtins.elem "CAP_NET_ADMIN" accessClient.additionalCapabilities
        && builtins.elem "CAP_NET_RAW" accessClient.additionalCapabilities
        && builtins.elem "CAP_SYS_ADMIN" accessClient.additionalCapabilities
        && builtins.length (
          builtins.filter (cap: cap == "CAP_NET_ADMIN") accessClient.additionalCapabilities
        ) == 1
        && builtins.elem "/dev/net/tun" accessClient.allowedDevices
    '

echo "PASS host-build-container-selection"
