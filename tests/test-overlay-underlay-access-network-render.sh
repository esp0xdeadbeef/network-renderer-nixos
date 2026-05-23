#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  overlay-underlay-access-network-render \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;

        render = containerModel:
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib containerModel;
            uplinks = { };
            wanUplinkName = null;
          };

        accessRender = render {
          interfaces.underlay-core-nebula = {
            sourceKind = "p2p";
            containerInterfaceName = "underlay-core-nebula";
            addresses = [
              "10.50.0.2/31"
              "fd42:dead:feed:1000::2/127"
            ];
            backingRef = {
              name = "p2p-access-client-core-nebula";
              lane = "default";
            };
            routes = [ ];
          };
        };

        coreRender = render {
          interfaces = {
            underlay-access-client = {
              sourceKind = "p2p";
              containerInterfaceName = "underlay-access-client";
              addresses = [
                "10.50.0.3/31"
                "fd42:dead:feed:1000::3/127"
              ];
              backingRef.name = "p2p-access-client-core-nebula";
              routes = [
                {
                  dst = "0.0.0.0/0";
                  via4 = "10.50.0.2";
                  proto = "default";
                  reason = "default-reachability";
                  intent.kind = "default-reachability";
                }
                {
                  dst = "::/0";
                  via6 = "fd42:dead:feed:1000::2";
                  proto = "default";
                  reason = "default-reachability";
                  intent.kind = "default-reachability";
                }
              ];
            };
            upstream = {
              sourceKind = "p2p";
              containerInterfaceName = "upstream";
              addresses = [
                "10.50.0.14/31"
                "fd42:dead:feed:1000::e/127"
              ];
              backingRef.name = "p2p-core-nebula-upstream";
              routes = [ ];
            };
          };
        };

        accessNetworks = accessRender.networks;
        coreNetworks = coreRender.networks;
        accessUnderlay = accessNetworks."10-underlay-core-nebula";
        coreUnderlay = coreNetworks."10-underlay-access-client";
        coreUpstream = coreNetworks."10-upstream";

        isDefault4 = route: (route.Destination or null) == "0.0.0.0/0";
        isDefault6 = route: (route.Destination or null) == "::/0";
        hasRoute = routes: destination: gateway:
          builtins.any
            (route:
              (route.Destination or null) == destination
              && (route.Gateway or null) == gateway
              && !(route ? Table))
            routes;
        hasRendererMetadata =
          routes:
          builtins.any
            (route:
              route ? proto
              || route ? reason
              || route ? intent
              || route ? lane
              || route ? policyOnly)
            routes;
      in
        accessNetworks ? "10-underlay-core-nebula"
        && !(accessNetworks ? "10-overlay-west")
        && !(accessNetworks ? "10-overlay-east-west")
        && (builtins.filter
          (route: isDefault4 route || isDefault6 route)
          (accessUnderlay.routes or [ ])) == [ ]
        && coreNetworks ? "10-underlay-access-client"
        && coreNetworks ? "10-upstream"
        && hasRoute
          (coreUnderlay.routes or [ ])
          "0.0.0.0/0"
          "10.50.0.2"
        && hasRoute
          (coreUnderlay.routes or [ ])
          "::/0"
          "fd42:dead:feed:1000::2"
        && !hasRendererMetadata (coreUnderlay.routes or [ ])
        && (builtins.filter
          (route: isDefault4 route || isDefault6 route)
          (coreUpstream.routes or [ ])) == [ ]
    '

echo "PASS overlay-underlay-access-network-render"
