#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

search_root="$(flake_input_path network-labs)/examples"
example_root="${search_root}/dual-wan-branch-overlay-bgp"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || fail "missing intent fixture: ${intent_path}"
[[ -f "${inventory_path}" ]] || fail "missing inventory fixture: ${inventory_path}"

nix_eval_true_or_fail "transit-endpoint-return-routes:dual-wan" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        host = flake.lib.renderer.buildHostFromPaths {
          selector = "lab-host";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        rendered = host.renderedHost.containers."s-router-core-isp-a";
        cfg =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ rendered.config ];
          }).config;
        routes = cfg.systemd.network.networks."10-ens3".routes or [ ];
        hasRoute = destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway)
            routes;
      in
        hasRoute "10.19.0.8/32" "10.10.0.9"
        && hasRoute "fd42:dead:beef:1900:0000:0000:0000:0008/128" "fd42:dead:beef:1000:0:0:0:9"
    '

nix_eval_true_or_fail "transit-endpoint-return-routes:s-router-test" \
  env REPO_ROOT="${repo_root}" \
    INTENT_PATH="$(flake_input_path network-labs)/examples/s-router-test-three-site/intent.nix" \
    INVENTORY_PATH="$(flake_input_path network-labs)/examples/s-router-test-three-site/inventory-nixos.nix" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        testHost = flake.lib.renderer.buildHostFromPaths {
          selector = "s-router-test";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        hetznerHost = flake.lib.renderer.buildHostFromPaths {
          selector = "s-router-hetzner-anywhere";
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
        };
        renderedBranchCore = testHost.renderedHost.containers."s-router-core-isp-b";
        cfgBranchCore =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ renderedBranchCore.config ];
          }).config;
        branchCoreNetworks = cfgBranchCore.systemd.network.networks;
        hasMainRoute = routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && !(builtins.hasAttr "Table" route))
            routes;
        hasMainRouteAnyNetwork = networks: destination: gateway:
          builtins.any
            (networkName: hasMainRoute (networks.${networkName}.routes or [ ]) destination gateway)
            (builtins.attrNames networks);
      in
        hasMainRouteAnyNetwork branchCoreNetworks "10.50.0.0/32" "10.10.0.15"
        && hasMainRouteAnyNetwork branchCoreNetworks "fd42:dead:beef:1000:0:0:0:0/128" "fd42:dead:beef:1000:0:0:0:f"
    '

echo "PASS transit-endpoint-return-routes"
