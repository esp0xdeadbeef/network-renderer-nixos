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
        model:
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          containerModel = model;
          uplinks = { };
          wanUplinkName = null;
          forwardingIntent = model.forwardingIntent or null;
          firewallRuleset = model.firewallRuleset or null;
        };
      default4 = gateway: {
        dst = "0.0.0.0/0";
        via4 = gateway;
      };
      default6 = gateway: {
        dst = "::/0";
        via6 = gateway;
      };
      selectorRender =
        render {
          interfaces = {
            access-branch = {
              containerInterfaceName = "access-branch";
              addresses = [ "10.50.0.1/31" "fd42:dead:feed:1000::1/127" ];
            };
            access-hostile = {
              containerInterfaceName = "access-hostile";
              addresses = [ "10.50.0.3/31" "fd42:dead:feed:1000::3/127" ];
            };
            policy-branch = {
              containerInterfaceName = "policy-branch";
              addresses = [ "10.50.0.6/31" "fd42:dead:feed:1000::6/127" ];
              routes = [
                (default4 "10.50.0.7")
                (default6 "fd42:dead:feed:1000::7")
              ];
            };
            policy-hostile = {
              containerInterfaceName = "policy-hostile";
              addresses = [ "10.50.0.8/31" "fd42:dead:feed:1000::8/127" ];
              routes = [
                (default4 "10.50.0.9")
                (default6 "fd42:dead:feed:1000::9")
              ];
            };
          };
        };
      policyRender =
        render {
          interfaces = {
            downstream-branch = {
              containerInterfaceName = "downstream-branch";
              addresses = [ "10.50.0.7/31" "fd42:dead:feed:1000::7/127" ];
            };
            downstream-hostile = {
              containerInterfaceName = "downstream-hostile";
              addresses = [ "10.50.0.9/31" "fd42:dead:feed:1000::9/127" ];
            };
            upstream-branch = {
              containerInterfaceName = "upstream-branch";
              addresses = [ "10.51.0.2/31" "fd42:dead:feed:1100::2/127" ];
              routes = [
                (default4 "10.51.0.3")
                (default6 "fd42:dead:feed:1100::3")
              ];
            };
            up-hostile = {
              containerInterfaceName = "up-hostile";
              addresses = [ "10.52.0.2/31" "fd42:dead:feed:1200::2/127" ];
              routes = [
                (default4 "10.52.0.3")
                (default6 "fd42:dead:feed:1200::3")
              ];
            };
          };
        };
      upstreamSelectorRender =
        render {
          interfaces = {
            core-a = {
              containerInterfaceName = "core-a";
              addresses = [ "10.10.0.11/31" "fd42:dead:beef:1000::b/127" ];
              routes = [
                (default4 "10.10.0.10")
                (default6 "fd42:dead:beef:1000::a")
              ];
            };
            pol-mgmt-a = {
              containerInterfaceName = "pol-mgmt-a";
              addresses = [ "10.10.0.45/31" "fd42:dead:beef:1000::2d/127" ];
            };
            policy-mgmt-wan = {
              containerInterfaceName = "policy-mgmt-wan";
              addresses = [ "10.10.0.47/31" "fd42:dead:beef:1000::2f/127" ];
            };
          };
        };
      upstreamSelectorLongNameRender =
        render {
          interfaces = {
            core = {
              containerInterfaceName = "core";
              addresses = [ "10.80.0.11/31" "fd42:dead:cafe:1000::b/127" ];
              routes = [
                (default4 "10.80.0.10")
                (default6 "fd42:dead:cafe:1000::a")
              ];
            };
            policy-mgmt-wan = {
              containerInterfaceName = "policy-mgmt-wan";
              addresses = [ "10.80.0.29/31" "fd42:dead:cafe:1000::1d/127" ];
            };
          };
        };
      upstreamSelectorSplitRender =
        render {
          forwardingIntent = {
            rules = [
              {
                action = "accept";
                fromInterface = "core-isp";
                toInterface = "policy-hostile";
              }
              {
                action = "accept";
                fromInterface = "policy-hostile";
                toInterface = "core-isp";
              }
            ];
          };
          interfaces = {
            core-nebula = {
              containerInterfaceName = "core-nebula";
              routes = [
                {
                  dst = "::/1";
                  via6 = "fd42:dead:feed:1000::6";
                }
              ];
            };
            core-isp = {
              containerInterfaceName = "core-isp";
              routes = [
                (default4 "10.50.0.8")
                (default6 "fd42:dead:feed:1000::8")
              ];
            };
            pol-hostile-ew = {
              containerInterfaceName = "pol-hostile-ew";
              routes = [
                {
                  dst = "10.70.10.0/24";
                  via4 = "10.50.0.16";
                }
              ];
            };
            policy-hostile = {
              containerInterfaceName = "policy-hostile";
              routes = [
                {
                  dst = "10.70.10.0/24";
                  via4 = "10.50.0.18";
                }
              ];
            };
          };
        };
      upstreamSelectorServiceIngressRender =
        render {
          forwardingIntent = {
            rules = [
              {
                action = "accept";
                fromInterface = "core-nebula";
                toInterface = "policy-dmz-wan";
              }
              {
                action = "accept";
                family = 6;
                fromInterface = "core-nebula";
                toInterface = "core";
              }
            ];
          };
          interfaces = {
            core-nebula = {
              containerInterfaceName = "core-nebula";
              addresses = [ "10.80.0.11/31" "fd42:dead:cafe:1000::b/127" ];
              routes = [
                (default4 "10.80.0.4")
                (default6 "fd42:dead:cafe:1000::4")
                {
                  dst = "10.90.10.1";
                  via4 = "10.80.0.14";
                }
                {
                  dst = "10.20.70.0/24";
                  via4 = "10.80.0.10";
                }
                {
                  dst = "fd42:dead:beef:70::/64";
                  via6 = "fd42:dead:cafe:1000::a";
                }
              ];
            };
            policy-dmz-wan = {
              containerInterfaceName = "policy-dmz-wan";
              addresses = [ "10.80.0.14/31" "fd42:dead:cafe:1000::e/127" ];
              routes = [
                {
                  dst = "10.90.10.1";
                  via4 = "10.80.0.15";
                }
                {
                  dst = "10.20.70.0/24";
                  via4 = "10.80.0.14";
                }
                {
                  dst = "fd42:dead:beef:70::/64";
                  via6 = "fd42:dead:cafe:1000::e";
                }
              ];
            };
            core = {
              containerInterfaceName = "core";
              addresses = [ "10.80.0.5/31" "fd42:dead:cafe:1000::5/127" ];
            };
          };
        };
      remoteOverlayEgressRender =
        render {
          forwardingIntent = {
            rules = [
              {
                action = "accept";
                fromInterface = "nebula-core";
                sourcePrefixes = [
                  { family = 4; prefix = "10.89.0.0/32"; }
                  { family = 6; prefix = "fd42:dead:cafe:1900::/128"; }
                ];
                toInterface = "core";
              }
              {
                action = "accept";
                fromInterface = "nebula-core";
                toInterface = "pol-dmz-ew";
              }
              {
                action = "accept";
                sourcePrefixes = [
                  { family = 4; prefix = "10.90.10.0/24"; }
                  { family = 6; prefix = "fd42:dead:cafe:10::/64"; }
                ];
                fromInterface = "pol-dmz-ew";
                toInterface = "nebula-core";
              }
              {
                action = "accept";
                fromInterface = "pol-dmz-ew";
                toInterface = "core";
              }
              {
                action = "accept";
                fromInterface = "core";
                sourcePrefixes = [
                  { family = 4; prefix = "10.20.70.0/24"; }
                  { family = 6; prefix = "fd42:dead:beef:70::/64"; }
                ];
                toInterface = "policy-dmz-wan";
              }
              {
                action = "accept";
                fromInterface = "policy-dmz-wan";
                sourcePrefixes = [
                  { family = 4; prefix = "10.20.70.0/24"; }
                  { family = 6; prefix = "fd42:dead:beef:70::/64"; }
                ];
                toInterface = "core";
              }
            ];
          };
          interfaces = {
            core = {
              containerInterfaceName = "core";
              addresses = [ "10.80.0.5/31" "fd42:dead:cafe:1000::5/127" ];
              interfaceClass.coreFacing = true;
              backingRef.lane = {
                kind = "uplink";
                uplink = "wan";
                uplinks = [ "wan" ];
              };
              routes = [
                {
                  dst = "0.0.0.0/0";
                  via4 = "10.80.0.4";
                  metric = 1000;
                }
                {
                  dst = "::/0";
                  via6 = "fd42:dead:cafe:1000::4";
                  metric = 1000;
                }
              ];
            };
            nebula-core = {
              containerInterfaceName = "nebula-core";
              addresses = [ "10.80.0.11/31" "fd42:dead:cafe:1000::b/127" ];
              interfaceClass.coreFacing = true;
              backingRef.lane = {
                kind = "uplink";
                uplink = "east-west";
                uplinks = [ "east-west" ];
              };
              routes = [
                {
                  dst = "0.0.0.0/0";
                  via4 = "10.80.0.10";
                  metric = 2000;
                  policyOnly = true;
                  intent.kind = "default-reachability";
                }
                {
                  dst = "0.0.0.0/0";
                  via4 = "10.80.0.14";
                  metric = 2000;
                  policyOnly = true;
                  lane = { access = null; uplink = "east-west"; };
                  intent.kind = "default-reachability";
                }
                {
                  dst = "::/0";
                  via6 = "fd42:dead:cafe:1000::a";
                  metric = 2000;
                  policyOnly = true;
                  intent.kind = "default-reachability";
                }
                {
                  dst = "::/0";
                  via6 = "fd42:dead:cafe:1000::e";
                  metric = 2000;
                  policyOnly = true;
                  lane = { access = null; uplink = "east-west"; };
                  intent.kind = "default-reachability";
                }
              ];
            };
            pol-dmz-ew = {
              containerInterfaceName = "pol-dmz-ew";
              addresses = [ "10.80.0.15/31" "fd42:dead:cafe:1000::f/127" ];
              interfaceClass.exitFacing = true;
              backingRef.lane = {
                access = "hetz-router-access-dmz";
                kind = "access-uplink";
                uplink = "east-west";
                uplinks = [ "east-west" ];
              };
            };
            policy-dmz-wan = {
              containerInterfaceName = "policy-dmz-wan";
              addresses = [ "10.80.0.17/31" "fd42:dead:cafe:1000::11/127" ];
              interfaceClass.exitFacing = true;
              backingRef.lane = {
                access = "hetz-router-access-dmz";
                kind = "access-uplink";
                uplink = "wan";
                uplinks = [ "wan" ];
              };
              routes = [
                {
                  dst = "10.20.70.0/24";
                  via4 = "10.80.0.16";
                }
                {
                  dst = "fd42:dead:beef:70::/64";
                  via6 = "fd42:dead:cafe:1000::10";
                }
              ];
            };
          };
          networkBehavior = {
            isSelector = true;
            isUpstreamSelector = true;
            keepInterfaceRoutesInMain = true;
          };
        };
      selectorPolicyBranch = selectorRender.networks."10-policy-branch".routes or [ ];
      selectorPolicyHostile = selectorRender.networks."10-policy-hostile".routes or [ ];
      selectorBranchRules = selectorRender.networks."10-access-branch".routingPolicyRules or [ ];
      selectorHostileRules = selectorRender.networks."10-access-hostile".routingPolicyRules or [ ];
      policyUpstreamBranch = policyRender.networks."10-upstream-branch".routes or [ ];
      policyUpHostile = policyRender.networks."10-up-hostile".routes or [ ];
      policyBranchRules = policyRender.networks."10-downstream-branch".routingPolicyRules or [ ];
      policyHostileRules = policyRender.networks."10-downstream-hostile".routingPolicyRules or [ ];
      upstreamCoreRoutes = upstreamSelectorRender.networks."10-core-a".routes or [ ];
      upstreamPolicyRoutes = upstreamSelectorRender.networks."10-pol-mgmt-a".routes or [ ];
      upstreamPolicyRules = upstreamSelectorRender.networks."10-pol-mgmt-a".routingPolicyRules or [ ];
      upstreamLongPolicyRules =
        upstreamSelectorLongNameRender.networks."10-policy-mgmt-wan".routingPolicyRules or [ ];
      upstreamLongCoreRoutes =
        upstreamSelectorLongNameRender.networks."10-core".routes or [ ];
      splitNebulaRoutes = upstreamSelectorSplitRender.networks."10-core-nebula".routes or [ ];
      splitWanRoutes = upstreamSelectorSplitRender.networks."10-core-isp".routes or [ ];
      splitHostileEwRules =
        upstreamSelectorSplitRender.networks."10-pol-hostile-ew".routingPolicyRules or [ ];
      splitHostileWanRules =
        upstreamSelectorSplitRender.networks."10-policy-hostile".routingPolicyRules or [ ];
      serviceIngressPolicyRules =
        upstreamSelectorServiceIngressRender.networks."10-policy-dmz-wan".routingPolicyRules or [ ];
      serviceIngressPolicyTable = tableForIngress "policy-dmz-wan" serviceIngressPolicyRules;
      serviceIngressPolicyRoutes =
        upstreamSelectorServiceIngressRender.networks."10-policy-dmz-wan".routes or [ ];
      serviceIngressCoreRoutes =
        upstreamSelectorServiceIngressRender.networks."10-core-nebula".routes or [ ];
      serviceIngressWanRoutes =
        upstreamSelectorServiceIngressRender.networks."10-core".routes or [ ];
      remoteOverlayRoutes =
        lib.concatLists (
          map (network: network.routes or [ ]) (builtins.attrValues remoteOverlayEgressRender.networks)
        );
      remoteOverlayRules =
        lib.concatLists (
          map (network: network.routingPolicyRules or [ ]) (builtins.attrValues remoteOverlayEgressRender.networks)
        );
      remoteOverlayTable = tableForIngress "nebula-core" remoteOverlayRules;
      remoteOverlayDmzEwTable = tableForIngress "pol-dmz-ew" remoteOverlayRules;
      remoteOverlayReturn4Table = tableForRoute remoteOverlayRoutes "10.20.70.0/24" "10.80.0.16";
      remoteOverlayReturn6Table = tableForRoute remoteOverlayRoutes "fd42:dead:beef:70::/64" "fd42:dead:cafe:1000::10";
      routesAllHaveTable =
        expectedTable: routes:
        builtins.length routes > 0
        && builtins.all (route: (route.Table or null) == expectedTable) routes;
      hasIngressRule =
        expectedIf: expectedTable: rules:
        builtins.any (
          rule:
          (rule.IncomingInterface or null) == expectedIf
          && (rule.Table or null) == expectedTable
        ) rules;
      tableForIngress =
        expectedIf: rules:
        let
          matches = builtins.filter (
            rule:
            (rule.IncomingInterface or null) == expectedIf
            && (rule.SuppressPrefixLength or null) == null
            && (rule.Table or null) != null
          ) rules;
        in
        if matches == [ ] then null else (builtins.head matches).Table;
      tableForRoute =
        routes: expectedDestination: expectedGateway:
        let
          matches = builtins.filter (
            route:
            (route.Destination or null) == expectedDestination
            && (route.Gateway or null) == expectedGateway
            && (route.Table or null) != null
          ) routes;
        in
        if matches == [ ] then null else (builtins.head matches).Table;
      hasDestinationIngressRule =
        expectedIf: expectedDestination: expectedTable: rules:
        builtins.any (
          rule:
          (rule.IncomingInterface or null) == expectedIf
          && (rule.To or null) == expectedDestination
          && (rule.Table or null) == expectedTable
          && (rule.SuppressPrefixLength or null) == null
        ) rules;
      hasUnscopedIngressRule =
        expectedIf: rules:
        builtins.any (
          rule:
          (rule.IncomingInterface or null) == expectedIf
          && (rule.From or null) == null
          && (rule.To or null) == null
          && (rule.SuppressPrefixLength or null) == null
        ) rules;
      hostileEwTable = tableForIngress "pol-hostile-ew" splitHostileEwRules;
      hostileWanTable = tableForIngress "policy-hostile" splitHostileWanRules;
      hasRoute = routes: destination: gateway: table:
        builtins.any (
          route:
          (route.Destination or null) == destination
          && (route.Gateway or null) == gateway
          && (route.Table or null) == table
        ) routes;
      hasRouteMetric = routes: destination: gateway: table: metric:
        builtins.any (
          route:
          (route.Destination or null) == destination
          && (route.Gateway or null) == gateway
          && (route.Table or null) == table
          && (route.Metric or null) == metric
        ) routes;
      lacksRoute = routes: destination: gateway: table:
        !(hasRoute routes destination gateway table);
    in
    routesAllHaveTable 2000 selectorPolicyBranch
    && routesAllHaveTable 2001 selectorPolicyHostile
    && hasIngressRule "access-branch" 2000 selectorBranchRules
    && hasIngressRule "access-hostile" 2001 selectorHostileRules
    && routesAllHaveTable 2000 policyUpstreamBranch
    && routesAllHaveTable 2001 policyUpHostile
    && hasIngressRule "downstream-branch" 2000 policyBranchRules
    && hasIngressRule "downstream-hostile" 2001 policyHostileRules
    && routesAllHaveTable 2000 upstreamCoreRoutes
    && routesAllHaveTable 2001 upstreamPolicyRoutes
    && hasIngressRule "pol-mgmt-a" 2001 upstreamPolicyRules
    && routesAllHaveTable 2001 upstreamLongCoreRoutes
    && hasIngressRule "policy-mgmt-wan" 2001 upstreamLongPolicyRules
    && hasIngressRule "policy-mgmt-wan" 12001 upstreamLongPolicyRules
    && hostileEwTable != null
    && hostileWanTable != null
    && hasRoute splitNebulaRoutes "::/1" "fd42:dead:feed:1000::6" hostileEwTable
    && !(hasRoute splitWanRoutes "::/0" "fd42:dead:feed:1000::8" hostileEwTable)
    && hasRoute splitWanRoutes "0.0.0.0/0" "10.50.0.8" hostileWanTable
    && hasRoute splitWanRoutes "::/0" "fd42:dead:feed:1000::8" hostileWanTable
    && !(hasRoute splitNebulaRoutes "10.70.10.0/24" "10.50.0.16" hostileWanTable)
    && hasRoute splitNebulaRoutes "10.70.10.0/24" "10.50.0.18" hostileWanTable
    && hasRoute serviceIngressPolicyRoutes "0.0.0.0/0" "10.80.0.15" serviceIngressPolicyTable
    && hasRouteMetric serviceIngressPolicyRoutes "0.0.0.0/0" "10.80.0.15" serviceIngressPolicyTable 50
    && lacksRoute serviceIngressWanRoutes "0.0.0.0/0" "10.80.0.4" serviceIngressPolicyTable
    && hasRoute serviceIngressWanRoutes "::/0" "fd42:dead:cafe:1000::4" serviceIngressPolicyTable
    && hasRoute serviceIngressCoreRoutes "10.20.70.0/24" "10.80.0.10" serviceIngressPolicyTable
    && hasRoute serviceIngressCoreRoutes "10.80.0.10/31" "10.80.0.10" serviceIngressPolicyTable
    && hasRoute serviceIngressCoreRoutes "fd42:dead:beef:70::/64" "fd42:dead:cafe:1000::a" serviceIngressPolicyTable
    && hasRoute remoteOverlayRoutes "0.0.0.0/0" "10.80.0.14" remoteOverlayTable
    && hasRoute remoteOverlayRoutes "::/0" "fd42:dead:cafe:1000::e" remoteOverlayTable
    && lacksRoute remoteOverlayRoutes "0.0.0.0/0" "10.80.0.4" remoteOverlayTable
    && lacksRoute remoteOverlayRoutes "::/0" "fd42:dead:cafe:1000::4" remoteOverlayTable
    && remoteOverlayDmzEwTable != null
    && hasRoute remoteOverlayRoutes "10.20.70.0/24" "10.80.0.10" remoteOverlayDmzEwTable
    && hasRoute remoteOverlayRoutes "fd42:dead:beef:70::/64" "fd42:dead:cafe:1000::a" remoteOverlayDmzEwTable
    && remoteOverlayReturn4Table != null
    && remoteOverlayReturn6Table != null
    && hasRoute remoteOverlayRoutes "10.20.70.0/24" "10.80.0.16" remoteOverlayReturn4Table
    && hasRoute remoteOverlayRoutes "fd42:dead:beef:70::/64" "fd42:dead:cafe:1000::10" remoteOverlayReturn6Table
    && hasDestinationIngressRule "core" "10.20.70.0/24" remoteOverlayReturn4Table remoteOverlayRules
    && hasDestinationIngressRule "core" "fd42:dead:beef:70::/64" remoteOverlayReturn6Table remoteOverlayRules
    && !(hasUnscopedIngressRule "core" remoteOverlayRules)
  ' >/dev/null || {
    echo "FAIL lane-route-scoping" >&2
    exit 1
  }

echo "PASS lane-route-scoping"
