#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
lab_inventory="$(mktemp --suffix=.nix)"
trap 'rm -f "${result_json}" "${eval_stderr}" "${lab_inventory}"' EXIT

labs_root="$(flake_input_path network-labs)"

cat >"${lab_inventory}" <<EOF
import ${labs_root}/labs/lab-s-sigma/s-router-test-three-site/getResolvedInventory.nix { renderer = "nixos"; }
EOF

run_case() {
  local label="$1"
  local box_name="$2"
  local container_name="$3"
  local intent_path="$4"
  local inventory_path="$5"

  [[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
  [[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

  nix_eval_json_or_fail \
    "upstream-selector-core-main-routes:${label}" \
    "${result_json}" \
    "${eval_stderr}" \
    env REPO_ROOT="${repo_root}" \
      BOX_NAME="${box_name}" \
      CONTAINER_NAME="${container_name}" \
      INTENT_PATH="${intent_path}" \
      INVENTORY_PATH="${inventory_path}" \
      nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib;
        builtContainers = flake.lib.containers.buildForBox {
          boxName = builtins.getEnv "BOX_NAME";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        cfg = (lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ builtContainers.${builtins.getEnv "CONTAINER_NAME"}.config ];
        }).config;
        networks = cfg.systemd.network.networks;
        coreNetworks = lib.filterAttrs (name: _: lib.hasPrefix "10-core-" name) networks;
        isMainTable =
          route:
          !(route ? Table) || route.Table == 254;
        isDefault =
          route:
          (route.Destination or null) == "0.0.0.0/0"
          || (route.Destination or null) == "::/0"
          || (route.Destination or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";
        badPolicyLaneDefault =
          networkName: route:
          lib.hasPrefix "10-pol-" networkName
          && isMainTable route
          && isDefault route;
        badPolicyLaneDefaults = lib.concatLists (
          lib.mapAttrsToList
            (networkName: network:
              map
                (route: { inherit networkName route; })
                (builtins.filter (badPolicyLaneDefault networkName) (network.routes or [ ])))
            networks
        );
        checks = {
          at_least_one_core_interface_rendered = coreNetworks != { };
          policy_lane_main_defaults_absent =
            badPolicyLaneDefaults == [ ];
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks badPolicyLaneDefaults;
      }
    '

  assert_json_checks_ok "upstream-selector-core-main-routes:${label}" "${result_json}"
}

run_case \
  example \
  s-router-hetzner-anywhere \
  c-router-upstream-selector \
  "${labs_root}/examples/s-router-overlay-dns-lane-policy/intent.nix" \
  "${labs_root}/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix"

run_case \
  lab-sigma \
  s-router-test \
  s-router-upstream-selector \
  "${labs_root}/labs/lab-s-sigma/s-router-test-three-site/intent.nix" \
  "${lab_inventory}"

echo "PASS upstream-selector-core-main-routes"
