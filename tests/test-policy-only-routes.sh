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
      siteCOverlayIngressRender =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          containerModel = {
            interfaces = {
              core-nebula = {
                containerInterfaceName = "core-nebula";
                addresses = [ "fd42:dead:cafe:1000::b/127" ];
                backingRef.lane = {
                  kind = "uplink";
                  uplink = "east-west";
                  uplinks = [ "east-west" ];
                };
                routes = [
                  {
                    dst = "::/0";
                    via6 = "fd42:dead:cafe:1000::c";
                    metric = 50;
                    policyOnly = true;
                    intent = {
                      kind = "delegated-public-egress";
                      exitNode = "c-router-access-client";
                    };
                  }
                  {
                    dst = "fd42:dead:feed:70::/64";
                    via6 = "fd42:dead:cafe:1000::a";
                  }
                ];
              };
              pol-client-ew = {
                containerInterfaceName = "pol-client-ew";
                addresses = [ "fd42:dead:cafe:1000::d/127" ];
                backingRef.lane = {
                  access = "c-router-access-client";
                  kind = "access-uplink";
                  uplink = "east-west";
                  uplinks = [ "east-west" ];
                };
                routes = [
                  {
                    dst = "fd42:dead:cafe:20::/64";
                    via6 = "fd42:dead:cafe:1000::c";
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
      upstreamSelectorRules =
        lib.concatLists (
          map (network: network.routingPolicyRules or [ ]) (builtins.attrValues upstreamSelectorRender.networks)
        );
      tableFor = incomingInterface:
        let
          matches =
            builtins.filter
              (rule:
                (rule.IncomingInterface or null) == incomingInterface
                && (rule.Table or null) != 254)
              upstreamSelectorRules;
        in
        if matches == [ ] then null else (builtins.head matches).Table;
      branchTable = tableFor "policy-branch";
      branchHasWanDefault =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Gateway or null) == "fd42:dead:feed:1000::6"
            && (route.Table or null) == branchTable)
          upstreamSelectorRoutes;
      branchLeaksOverlayDefault =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Gateway or null) == "fd42:dead:feed:1000::4"
            && (route.Table or null) == branchTable)
          upstreamSelectorRoutes;
      siteCOverlayIngressRoutes =
        siteCOverlayIngressRender.networks."10-pol-client-ew".routes or [ ];
      siteCOverlayIngressRules =
        lib.concatLists (
          map (network: network.routingPolicyRules or [ ]) (builtins.attrValues siteCOverlayIngressRender.networks)
        );
      siteCTable =
        let
          matches =
            builtins.filter
              (rule:
                (rule.IncomingInterface or null) == "core-nebula"
                && (rule.Table or null) != 254)
              siteCOverlayIngressRules;
        in
        if matches == [ ] then null else (builtins.head matches).Table;
      siteCOverlayIngressDefault =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Gateway or null) == "fd42:dead:cafe:1000::c"
            && (route.Table or null) == siteCTable)
          siteCOverlayIngressRoutes;
      siteCOverlayMainDefault =
        builtins.any
          (route:
            (route.Destination or null) == "::/0"
            && (route.Gateway or null) == "fd42:dead:cafe:1000::c"
            && !(route ? Table))
          siteCOverlayIngressRoutes;
      branchIpv4Render =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          containerModel = {
            interfaces = {
              core-nebula = {
                containerInterfaceName = "core-nebula";
                addresses = [ "10.50.0.5/31" ];
                backingRef.lane = {
                  kind = "uplink";
                  uplink = "east-west";
                  uplinks = [ "east-west" ];
                };
                routes = [
                  {
                    dst = "0.0.0.0/0";
                    via4 = "10.50.0.4";
                    metric = 50;
                    policyOnly = true;
                    intent.kind = "delegated-public-egress";
                  }
                ];
              };
              pol-hostile-ew = {
                containerInterfaceName = "pol-hostile-ew";
                addresses = [ "10.50.0.17/31" ];
                backingRef.lane = {
                  access = "b-router-access-hostile";
                  kind = "access-uplink";
                  uplink = "east-west";
                  uplinks = [ "east-west" ];
                };
                routes = [ ];
              };
            };
          };
          uplinks = { };
          wanUplinkName = null;
        };
      branchIpv4Rules =
        lib.concatLists (
          map (network: network.routingPolicyRules or [ ]) (builtins.attrValues branchIpv4Render.networks)
        );
      branchIpv4Routes =
        lib.concatLists (
          map (network: network.routes or [ ]) (builtins.attrValues branchIpv4Render.networks)
        );
      branchHostileTable =
        let
          matches =
            builtins.filter
              (rule:
                (rule.IncomingInterface or null) == "pol-hostile-ew"
                && (rule.Table or null) != 254)
              branchIpv4Rules;
        in
        if matches == [ ] then null else (builtins.head matches).Table;
      branchHostileIpv4Default =
        builtins.any
          (route:
            (route.Destination or null) == "0.0.0.0/0"
            && (route.Gateway or null) == "10.50.0.4"
            && (route.Table or null) == branchHostileTable)
          branchIpv4Routes;
      branchHostileIpv4MainDefault =
        builtins.any
          (route:
            (route.Destination or null) == "0.0.0.0/0"
            && (route.Gateway or null) == "10.50.0.4"
            && !(route ? Table))
          branchIpv4Routes;
    in
      if hasPolicyOnlyTableRoute && !hasPolicyOnlyMainRoute && branchHasWanDefault && !branchLeaksOverlayDefault && siteCOverlayIngressDefault && !siteCOverlayMainDefault && branchHostileIpv4Default && !branchHostileIpv4MainDefault then
        true
      else
        throw "policy-only-routes failed: renderer must render CPM policyOnly routes only inside their intended policy tables, including site-c core-nebula overlay ingress defaults, not as main defaults or unrelated ingress-table defaults. Remove this error only after delegated hostile public egress can select Nebula and then site-c client policy without turning overlay into a generic branch WAN default."
  ' >/dev/null

echo "PASS policy-only-routes"
