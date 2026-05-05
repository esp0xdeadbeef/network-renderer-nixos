#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

nix_eval_true_or_fail "hostile-dns-east-west" env REPO_ROOT="${repo_root}" \
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
        networks = cfg.systemd.network.networks;
        hasRoute = destination: gateway: table:
          builtins.any
            (networkName:
              builtins.any
                (route:
                  (route.Destination or null) == destination
                  && (route.Gateway or null) == gateway
                  && (route.Table or null) == table)
                (networks.${networkName}.routes or [ ]))
            (builtins.attrNames networks);
        networkHasRoute = networkName: destination: gateway: table:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && (route.Table or null) == table)
            (networks.${networkName}.routes or [ ]);
      in
        hasRoute "10.20.10.0/24" "10.50.0.17" 2004
        && hasRoute "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:11" 2004
        && networkHasRoute "10-up-hostile-ew" "10.90.10.1" "10.50.0.17" 2001
        && !(networkHasRoute "10-downstr-hostile" "10.90.10.1" "10.50.0.17" 2001)
    '

echo "PASS hostile-dns-east-west"
