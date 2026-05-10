#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

labs_root="$(flake_input_path network-labs)"

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
      CASE_LABEL="${label}" \
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
        label = builtins.getEnv "CASE_LABEL";
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
        networkForInterface = renderedName: networks."10-${renderedName}" or { };
        tableForInterface =
          renderedName:
          let
            rules = (networkForInterface renderedName).routingPolicyRules or [ ];
            policyRules = builtins.filter (rule: (rule.Table or 254) != 254) rules;
          in
          if policyRules == [ ] then null else (builtins.head policyRules).Table;
        routesForTable =
          table:
          if table == null then
            [ ]
          else
            lib.concatLists (
              lib.mapAttrsToList
                (_: network: builtins.filter (route: (route.Table or null) == table) (network.routes or [ ]))
                networks
            );
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
        hasDefaultVia =
          renderedName: gateway:
          builtins.any
            (route: isDefault route && (route.Gateway or null) == gateway)
            (routesForTable (tableForInterface renderedName));
        hasRouteVia =
          renderedName: destination: gateway:
          builtins.any
            (route: (route.Destination or null) == destination && (route.Gateway or null) == gateway)
            (routesForTable (tableForInterface renderedName));
        exampleReturnRouteChecks =
          if label != "example" then
            { }
          else
            {
              core_returns_sitec_dmz_prefix_v4 =
                hasRouteVia "core" "10.90.10.0/24" "10.80.0.18";
              core_returns_sitec_dmz_access_transit_v4 =
                hasRouteVia "core" "10.80.0.2/31" "10.80.0.18";
              core_returns_sitec_dmz_prefix_v6 =
                hasRouteVia "core" "fd42:dead:cafe:10::/64" "fd42:dead:cafe:1000:0:0:0:12";
              core_returns_sitec_dmz_access_transit_v6 =
                hasRouteVia "core" "fd42:dead:cafe:1000:0:0:0:2/127" "fd42:dead:cafe:1000:0:0:0:12";
            };
        checks = {
          at_least_one_core_interface_rendered = coreNetworks != { };
          policy_lane_main_defaults_absent =
            badPolicyLaneDefaults == [ ];
        } // exampleReturnRouteChecks;
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks badPolicyLaneDefaults;
        debug = {
          polAdminBTable = tableForInterface "pol-admin-b";
          polAdminBRoutes = routesForTable (tableForInterface "pol-admin-b");
          polMgmtBTable = tableForInterface "pol-mgmt-b";
          polMgmtBRoutes = routesForTable (tableForInterface "pol-mgmt-b");
        };
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

echo "PASS upstream-selector-core-main-routes"
