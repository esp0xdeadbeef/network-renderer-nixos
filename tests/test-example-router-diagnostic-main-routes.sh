#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  example-router-diagnostic-main-routes \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
          labs = flake.inputs.network-labs.outPath;
          host = flake.lib.renderer.buildHostFromPaths {
            selector = "s-router-test";
            system = "x86_64-linux";
            intentPath = labs + "/examples/s-router-overlay-dns-lane-policy/intent.nix";
            inventoryPath = labs + "/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix";
          };
          hetzContainers = flake.lib.containers.buildForBox {
            boxName = "s-router-hetzner-anywhere";
            system = "x86_64-linux";
            intentPath = labs + "/examples/s-router-overlay-dns-lane-policy/intent.nix";
            inventoryPath = labs + "/examples/s-router-overlay-dns-lane-policy/inventory-nixos.nix";
          };
          cfgFor = name:
            (flake.inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [ host.renderedHost.containers.${name}.config ];
            }).config.systemd.network.networks;
          hetzCfgFor = name:
            (flake.inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [ hetzContainers.${name}.config ];
            }).config.systemd.network.networks;
          routesFor = name:
            let
              networks = cfgFor name;
            in
            builtins.concatMap
              (networkName: map (route: route // { inherit networkName; }) (networks.${networkName}.routes or [ ]))
              (builtins.attrNames networks);
          hetzRoutesFor = name:
            let
              networks = hetzCfgFor name;
            in
            builtins.concatMap
              (networkName: map (route: route // { inherit networkName; }) (networks.${networkName}.routes or [ ]))
              (builtins.attrNames networks);
          hasMainRoute = routes: networkName: destination: gateway:
            builtins.any
              (route:
                (route.networkName or null) == networkName
                && (route.Destination or null) == destination
                && (route.Gateway or null) == gateway
                && !(route ? Table))
              routes;
          hasTableRoute = routes: networkName: destination: gateway: table:
            builtins.any
              (route:
                (route.networkName or null) == networkName
                && (route.Destination or null) == destination
                && (route.Gateway or null) == gateway
                && (route.Table or null) == table)
              routes;
          noMainRoute = routes: networkName: destination: gateway:
            !builtins.any
              (route:
                (route.networkName or null) == networkName
                && (route.Destination or null) == destination
                && (route.Gateway or null) == gateway
                && !(route ? Table))
              routes;
          noMainDefault = routes:
            !builtins.any
              (route:
                ((route.Destination or null) == "0.0.0.0/0" || (route.Destination or null) == "::/0")
                && !(route ? Table))
              routes;
          downstream = routesFor "s-router-downstream-selector";
          policy = routesFor "s-router-policy-only";
          upstream = routesFor "s-router-upstream-selector";
          branchUpstream = routesFor "b-router-upstream-selector";
          checks = {
            downstreamHostileReturn =
              hasMainRoute downstream "10-access-client" "10.20.20.0/24" "10.10.0.2";
            downstreamPolicyIngressAccessTableReturn =
              hasTableRoute downstream "10-access-client" "10.20.20.0/24" "10.10.0.2" 2001;
            downstreamPolicyIngressAccessTableReturn6 =
              hasTableRoute downstream "10-access-client" "fd42:dead:beef:20::/64" "fd42:dead:beef:1000:0:0:0:2" 2001;
            policyHostileReturn =
              hasMainRoute policy "10-down-client" "10.20.20.0/24" "10.10.0.20";
            upstreamHostileReturn =
              hasMainRoute upstream "10-pol-cli-ew" "10.20.20.0/24" "10.10.0.36";
            downstreamNoSitecViaAdminMain =
              noMainRoute downstream "10-policy-client" "10.70.10.0/24" "10.10.0.21";
            branchHostileOverlayReturn =
              hasMainRoute branchUpstream "10-pol-hostile-ew" "10.70.10.0/24" "10.50.0.16";
            downstreamNoMainDefault = noMainDefault downstream;
            policyNoMainDefault = noMainDefault policy;
            upstreamNoMainDefault = noMainDefault upstream;
          };
        in
        if builtins.all (name: checks.${name}) (builtins.attrNames checks) then
          true
        else
          throw ("example-router-diagnostic-main-routes failed: " + builtins.toJSON checks)
      '

echo "PASS example-router-diagnostic-main-routes"
