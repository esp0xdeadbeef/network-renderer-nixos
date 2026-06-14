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
        host = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        etc = host.artifactModule.environment.etc;
        runtimeTargetNames = host.runtimeTargetNames or [ ];
      in
        builtins.hasAttr "network-artifacts/compiler.json" etc
        && builtins.hasAttr "network-artifacts/forwarding.json" etc
        && builtins.hasAttr "network-artifacts/control-plane.json" etc
        && builtins.hasAttr "network-artifacts/intent.json" etc
        && builtins.hasAttr "network-artifacts/inventory.json" etc
        && builtins.hasAttr "network-artifacts/rendered-host.json" etc
        && builtins.hasAttr "network-artifacts/debug-bundle.json" etc
        && builtins.hasAttr "network-renderer/network-renderer-nixos.json" etc
        && runtimeTargetNames != [ ]
        && builtins.all (name: builtins.hasAttr name host.runtimeTargets) runtimeTargetNames
    '

nix_eval_true_or_fail "host-module-api" env REPO_ROOT="${repo_root}" \
EXAMPLE_ROOT="${example_root}" \
INTENT_PATH="${example_root}/intent.nix" \
INVENTORY_PATH="${example_root}/inventory-nixos.nix" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        module = flake.lib.renderer.hostModule {
          inherit lib;
          system = "x86_64-linux";
          outPath = builtins.getEnv "EXAMPLE_ROOT";
          hostName = "s-router-test";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
          selectorFile = "tests/test-host-build-artifact-module.sh";
          containerDefaults = {
            autoStart = true;
            additionalCapabilities = [
              "CAP_NET_ADMIN"
              "CAP_NET_RAW"
            ];
          };
        };
        evaluated = lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ module ];
        };
        config = evaluated.config;
        etc = config.environment.etc;
        containerNames = builtins.attrNames (config.containers or { });
        accessClient = config.containers."s-router-access-client" or { };
      in
        builtins.hasAttr "network-artifacts/compiler.json" etc
        && builtins.hasAttr "network-artifacts/rendered-host.json" etc
        && builtins.hasAttr "network-renderer/network-renderer-nixos.json" etc
        && config.networking.useNetworkd == true
        && config.systemd.network.enable == true
        && config.networking.useDHCP == false
        && containerNames != [ ]
        && (accessClient.autoStart or false) == true
        && builtins.elem "CAP_NET_ADMIN" (accessClient.additionalCapabilities or [ ])
        && builtins.elem "CAP_NET_RAW" (accessClient.additionalCapabilities or [ ])
    '

echo "PASS host-build-artifact-module"
