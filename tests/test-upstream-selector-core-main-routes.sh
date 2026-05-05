#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-overlay-dns-lane-policy"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  upstream-selector-core-main-routes \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        builtContainers = flake.lib.containers.buildForBox {
          boxName = "s-router-hetzner-anywhere";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        cfg = (lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ builtContainers."c-router-upstream-selector".config ];
        }).config;
        networks = cfg.systemd.network.networks;
        coreNebulaRoutes = networks."10-core-nebula".routes or [ ];
        badDefault4 =
          route:
          (route.Destination or null) == "0.0.0.0/0"
          && (route.Gateway or null) == "10.80.0.4"
          && !(route ? Table);
        badDefault6 =
          route:
          ((route.Destination or null) == "::/0"
            || (route.Destination or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0")
          && (route.Gateway or null) == "fd42:dead:cafe:1000:0:0:0:4"
          && !(route ? Table);
        checks = {
          core_nebula_main_default_to_wan_core_v4_absent =
            !(builtins.any badDefault4 coreNebulaRoutes);
          core_nebula_main_default_to_wan_core_v6_absent =
            !(builtins.any badDefault6 coreNebulaRoutes);
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks coreNebulaRoutes;
      }
    '

assert_json_checks_ok upstream-selector-core-main-routes "${result_json}"

echo "PASS upstream-selector-core-main-routes"
