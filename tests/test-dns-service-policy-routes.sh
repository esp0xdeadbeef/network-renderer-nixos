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
        mkCfg = containerName:
          (flake.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ builtContainers.${containerName}.config ];
          }).config;
        branchCfg = mkCfg "b-router-policy";
        siteaUpstreamCfg = mkCfg "s-router-upstream-selector";
        siteaPolicyCfg = mkCfg "s-router-policy-only";
        sitecCfg = mkCfg "c-router-policy";
        hasRoute = routes: destination: gateway: table:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && (route.Table or null) == table)
            routes;
        missingRoute = routes: destination: gateway: table:
          !(hasRoute routes destination gateway table);
        hasRouteAnyNetwork = networks: destination: gateway: table:
          builtins.any
            (networkName: hasRoute (networks.${networkName}.routes or [ ]) destination gateway table)
            (builtins.attrNames networks);
        branchNetworks = branchCfg.systemd.network.networks;
        siteaUpstreamNetworks = siteaUpstreamCfg.systemd.network.networks;
        siteaPolicyNetworks = siteaPolicyCfg.systemd.network.networks;
        sitecNetworks = sitecCfg.systemd.network.networks;
        siteaMgmtRoutes = siteaPolicyNetworks."10-downstream-mgmt".routes or [ ];
        sitecMgmtRoutes = sitecNetworks."10-downstream-mgmt".routes or [ ];
      in
        hasRouteAnyNetwork branchNetworks "10.20.10.0/24" "10.50.0.11" 2000
        && hasRouteAnyNetwork branchNetworks "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:b" 2000
        && hasRouteAnyNetwork siteaUpstreamNetworks "10.20.10.0/24" "10.10.0.42" 2001
        && !(hasRouteAnyNetwork siteaUpstreamNetworks "10.20.10.0/24" "10.10.0.30" 2001)
        && hasRoute siteaMgmtRoutes "10.20.10.0/24" "10.10.0.22" 2014
        && hasRoute siteaMgmtRoutes "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:beef:1000:0:0:0:16" 2014
        && hasRoute sitecMgmtRoutes "10.90.10.0/24" "10.80.0.16" 2001
        && hasRoute sitecMgmtRoutes "fd42:dead:cafe:0010:0000:0000:0000:0000/64" "fd42:dead:cafe:1000:0:0:0:10" 2001
        && hasRoute sitecMgmtRoutes "10.90.10.0/24" "10.80.0.16" 2004
        && hasRoute sitecMgmtRoutes "fd42:dead:cafe:0010:0000:0000:0000:0000/64" "fd42:dead:cafe:1000:0:0:0:10" 2004
    ' | grep -qx true

echo "PASS dns-service-policy-routes"
