#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

examples_root="$(flake_input_path network-labs)/examples"
intent_path="${examples_root}/s-router-test-three-site/intent.nix"
inventory_path="${examples_root}/s-router-test-three-site/inventory-nixos.nix"

REPO_ROOT="${repo_root}" \
INTENT_PATH="${intent_path}" \
INVENTORY_PATH="${inventory_path}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        builtContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        cfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers."b-router-access-hostile".config ];
          }).config;
        script =
          builtins.readFile cfg.systemd.services."radvd-generate-tenant-hostile".serviceConfig.ExecStart;
        tenantNetwork = cfg.systemd.network.networks."10-tenant-hostile";
        addresses = tenantNetwork.address or [ ];
      in
        builtins.match ".*2a01:4f8:1c17:b337::/64.*" script != null
        && !(builtins.elem "2a01:4f8:1c17:b337::1/64" addresses)
    ' | grep -qx true

pass "hostile-gua-advertisements"
