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

REPO_ROOT="${repo_root}" \
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
    ' | grep -qx true

REPO_ROOT="${repo_root}" \
INTENT_PATH="/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/intent.nix" \
INVENTORY_PATH="/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-test/inventory.nix" \
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
        renderedUpstream = host.renderedHost.containers."c-router-upstream-selector";
        renderedBranchCore = host.renderedHost.containers."s-router-core-isp-b";
        cfgUpstream =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ renderedUpstream.config ];
          }).config;
        cfgBranchCore =
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ renderedBranchCore.config ];
          }).config;
        iotRoutes = cfgUpstream.systemd.network.networks."10-policy-iot-wan".routes or [ ];
        mgmtStorageRoutes = cfgUpstream.systemd.network.networks."10-pol-mgt-sto".routes or [ ];
        mgmtRoutes = cfgUpstream.systemd.network.networks."10-policy-mgmt-wan".routes or [ ];
        branchOverlayRoutes = cfgBranchCore.systemd.network.networks."10-overlay-west".routes or [ ];
        hasRoute = routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && (route.Table or null) == 2000)
            routes;
        hasMainRoute = routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && !(builtins.hasAttr "Table" route))
            routes;
      in
        (!hasRoute iotRoutes "10.80.0.4/32" "10.80.0.22")
        && (!hasRoute mgmtStorageRoutes "10.80.0.4/32" "10.80.0.26")
        && hasRoute mgmtRoutes "10.80.0.4/32" "10.80.0.28"
        && hasMainRoute branchOverlayRoutes "10.50.0.0/32" "100.96.10.2"
        && hasMainRoute branchOverlayRoutes "fd42:dead:feed:1000:0:0:0:0/128" "fd42:dead:beef:ee::2"
    ' | grep -qx true

echo "PASS transit-endpoint-return-routes"
