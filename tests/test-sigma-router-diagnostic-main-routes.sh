#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  sigma-router-diagnostic-main-routes \
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
            intentPath = labs + "/labs/lab-s-sigma/s-router-test-three-site/intent.nix";
            inventoryPath = labs + "/labs/lab-s-sigma/s-router-test-three-site/inventory.nix";
          };
          hetzContainers = flake.lib.containers.buildForBox {
            boxName = "s-router-hetzner-anywhere";
            system = "x86_64-linux";
            intentPath = labs + "/labs/lab-s-sigma/s-router-test-three-site/intent.nix";
            inventoryPath = labs + "/labs/lab-s-sigma/s-router-test-three-site/inventory.nix";
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
          downstream = routesFor "nixos-router-downstream";
          policy = routesFor "nixos-router-policy";
          upstream = routesFor "nixos-router-upstream";
          hetzUpstream = hetzRoutesFor "hetz-router-upstream";
          checks = {
            downstreamHostileReturn =
              hasMainRoute downstream "10-access-hostile" "10.20.70.0/24" "10.10.0.6";
            policyHostileReturn =
              hasMainRoute policy "10-downstr-hostile" "10.20.70.0/24" "10.10.0.24";
            upstreamHostileReturn =
              hasMainRoute upstream "10-pol-hostile-ew" "10.20.70.0/24" "10.10.0.38";
            downstreamNoSitecViaAdminMain =
              noMainRoute downstream "10-policy-admin" "10.90.10.0/24" "10.10.0.19";
            hetzSitecOverlayReturn =
              hasMainRoute hetzUpstream "10-pol-dmz-ew" "10.90.10.0/24" "10.80.0.14";
            hetzNoSitecViaWanMain =
              noMainRoute hetzUpstream "10-policy-dmz-wan" "10.90.10.0/24" "10.80.0.16";
            downstreamNoMainDefault = noMainDefault downstream;
            policyNoMainDefault = noMainDefault policy;
            upstreamNoMainDefault = noMainDefault upstream;
          };
        in
        if builtins.all (name: checks.${name}) (builtins.attrNames checks) then
          true
        else
          throw ("sigma-router-diagnostic-main-routes failed: " + builtins.toJSON checks)
      '

echo "PASS sigma-router-diagnostic-main-routes"
