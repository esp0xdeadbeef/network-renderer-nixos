#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

intent_path="/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/intent.nix"
inventory_path="/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/inventory.nix"

[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

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
            modules = [ builtContainers."b-router-policy".config ];
          }).config;
        routes = cfg.systemd.network.networks."10-up-hostile-ew".routes or [ ];
        hasRoute = destination: gateway: table:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && (route.Table or null) == table)
            routes;
      in
        hasRoute "10.20.10.0/24" "10.50.0.15" 2004
        && hasRoute "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:f" 2004
    ' | grep -qx true

echo "PASS hostile-dns-east-west"
