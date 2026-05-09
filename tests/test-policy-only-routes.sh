#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      render =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          containerModel = {
            interfaces = {
              overlay-east-west = {
                containerInterfaceName = "overlay-east-west";
                sourceKind = "overlay";
                addresses = [ "fd42:dead:beef:ee::2/128" ];
                routes = [
                  {
                    dst = "::/0";
                    scope = "link";
                    policyOnly = true;
                    intent.kind = "delegated-public-egress";
                  }
                ];
              };
              upstream = {
                containerInterfaceName = "upstream";
                sourceKind = "p2p";
                addresses = [ "fd42:dead:feed:1000::4/127" ];
                routes = [
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:feed:1000::5";
                  }
                ];
              };
            };
          };
          uplinks = { };
          wanUplinkName = null;
        };
      overlayRoutes = render.networks."10-overlay-east-west".routes or [ ];
      hasPolicyOnlyTableRoute =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Scope or null) == "link"
            && (route ? Table))
          overlayRoutes;
      hasPolicyOnlyMainRoute =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Scope or null) == "link"
            && !(route ? Table))
          overlayRoutes;
      upstreamSelectorRender =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          containerModel = {
            interfaces = {
              core-nebula = {
                containerInterfaceName = "core-nebula";
                addresses = [ "fd42:dead:feed:1000::5/127" ];
                backingRef.lane = {
                  kind = "uplink";
                  uplink = "east-west";
                  uplinks = [ "east-west" ];
                };
                routes = [
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:feed:1000::4";
                    metric = 50;
                    policyOnly = true;
                    intent.kind = "delegated-public-egress";
                  }
                  {
                    dst = "fd42:dead:beef:20::/64";
                    via6 = "fd42:dead:feed:1000::4";
                  }
                ];
              };
              core-isp = {
                containerInterfaceName = "core-isp";
                addresses = [ "fd42:dead:feed:1000::7/127" ];
                backingRef.lane = {
                  kind = "uplink";
                  uplink = "wan";
                  uplinks = [ "wan" ];
                };
                routes = [
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:feed:1000::6";
                  }
                ];
              };
              policy-branch = {
                containerInterfaceName = "policy-branch";
                addresses = [ "fd42:dead:feed:1000::f/127" ];
                backingRef.lane = {
                  access = "b-router-access-branch";
                  kind = "access-uplink";
                  uplink = "wan";
                  uplinks = [ "wan" ];
                };
                routes = [
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:feed:1000::6";
                    metric = 1000;
                  }
                  {
                    dst = "fd42:dead:beef:20::/64";
                    via6 = "fd42:dead:feed:1000::4";
                  }
                ];
              };
              pol-hostile-ew = {
                containerInterfaceName = "pol-hostile-ew";
                addresses = [ "fd42:dead:feed:1000::13/127" ];
                backingRef.lane = {
                  access = "b-router-access-hostile";
                  kind = "access-uplink";
                  uplink = "east-west";
                  uplinks = [ "east-west" ];
                };
                routes = [
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:feed:1000::4";
                    metric = 50;
                    policyOnly = true;
                    intent.kind = "delegated-public-egress";
                  }
                ];
              };
            };
          };
          uplinks = { };
          wanUplinkName = null;
        };
      upstreamSelectorRoutes =
        lib.concatLists (
          map (network: network.routes or [ ]) (builtins.attrValues upstreamSelectorRender.networks)
        );
      branchHasWanDefault =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Gateway or null) == "fd42:dead:feed:1000::6"
            && (route.Table or null) == 2003)
          upstreamSelectorRoutes;
      branchLeaksOverlayDefault =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Gateway or null) == "fd42:dead:feed:1000::4"
            && (route.Table or null) == 2003)
          upstreamSelectorRoutes;
    in
      if hasPolicyOnlyTableRoute && !hasPolicyOnlyMainRoute && branchHasWanDefault && !branchLeaksOverlayDefault then
        true
      else
        throw "policy-only-routes failed: renderer must render CPM policyOnly routes only inside their intended policy tables, not as main defaults or unrelated ingress-table defaults. Remove this error only after delegated hostile public egress can select Nebula without turning overlay into a generic branch WAN default."
  ' >/dev/null

echo "PASS policy-only-routes"
