#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="$(flake_input_path network-labs)/examples/s-router-test-three-site"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

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
        lib = flake.inputs.nixpkgs.lib;
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
        siteaPolicyRules = siteaPolicyCfg.networking.nftables.ruleset;
        siteaMgmtRoutes = siteaPolicyNetworks."10-downstream-mgmt".routes or [ ];
        siteaMgmtWanReturnRoutes = siteaUpstreamNetworks."10-pol-mgmt-a".routes or [ ];
        siteaMgmtEastWestReturnRoutes = siteaUpstreamNetworks."10-pol-mgt-ew".routes or [ ];
        sitecMgmtRoutes = sitecNetworks."10-downstream-mgmt".routes or [ ];
      in
        hasRouteAnyNetwork branchNetworks "10.20.10.0/24" "10.50.0.13" 2000
        && hasRouteAnyNetwork branchNetworks "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:d" 2000
        && hasRouteAnyNetwork siteaUpstreamNetworks "10.20.10.0/24" "10.10.0.44" 2002
        && !(hasRouteAnyNetwork siteaUpstreamNetworks "10.20.10.0/24" "10.10.0.30" 2001)
        && hasRoute siteaMgmtWanReturnRoutes "10.20.10.0/24" "10.10.0.46" 2000
        && hasRoute siteaMgmtWanReturnRoutes "10.10.0.8/31" "10.10.0.46" 2000
        && hasRoute siteaMgmtWanReturnRoutes "fd42:dead:beef:10::/64" "fd42:dead:beef:1000:0:0:0:2e" 2000
        && hasRoute siteaMgmtWanReturnRoutes "fd42:dead:beef:1000:0:0:0:8/127" "fd42:dead:beef:1000:0:0:0:2e" 2000
        && hasRoute siteaMgmtEastWestReturnRoutes "10.50.0.0/31" "10.10.0.44" 2002
        && hasRoute siteaMgmtEastWestReturnRoutes "10.50.0.2/31" "10.10.0.44" 2002
        && hasRoute siteaMgmtEastWestReturnRoutes "fd42:dead:feed:1000:0:0:0:0/127" "fd42:dead:beef:1000:0:0:0:2c" 2002
        && hasRoute siteaMgmtEastWestReturnRoutes "fd42:dead:feed:1000:0:0:0:2/127" "fd42:dead:beef:1000:0:0:0:2c" 2002
        && hasRoute siteaMgmtRoutes "10.20.10.0/24" "10.10.0.24" 2004
        && hasRoute siteaMgmtRoutes "fd42:dead:beef:0010:0000:0000:0000:0000/64" "fd42:dead:beef:1000:0:0:0:18" 2004
        && lib.hasInfix "iifname \"downstr-client\" oifname \"downstream-mgmt\" meta l4proto udp udp dport { 53 } accept comment \"allow-sitea-tenants-to-mgmt-dns\"" siteaPolicyRules
        && lib.hasInfix "iifname \"downstr-client\" oifname \"downstream-mgmt\" meta l4proto tcp tcp dport { 53 } accept comment \"allow-sitea-tenants-to-mgmt-dns\"" siteaPolicyRules
        && hasRoute sitecMgmtRoutes "10.90.10.0/24" "10.80.0.16" 2002
        && hasRoute sitecMgmtRoutes "fd42:dead:cafe:0010:0000:0000:0000:0000/64" "fd42:dead:cafe:1000:0:0:0:10" 2002
    ' | grep -qx true

echo "PASS dns-service-policy-routes"
