#!/usr/bin/env bash
# GAMP-ID: FS-800-HDS-030-FS-370-FS-380-SDS-020-SMS-030
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  provider-handoff-path-materialization \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        tenantSource = { family = 4; prefix = "10.44.11.2/32"; };
        ruleFor =
          rules: incomingInterface: source: table:
          lib.findFirst
            (
              rule:
              (rule.IncomingInterface or null) == incomingInterface
              && (rule.From or null) == source
              && (rule.Table or null) == table
              && (rule.Priority or null) != null
            )
            null
            rules;
        routeVia =
          routes: table: gateway:
          builtins.any
            (
              route:
              (route.Table or null) == table
              && (route.Destination or null) == "0.0.0.0/0"
              && (route.Gateway or null) == gateway
            )
            routes;
        routeViaAny =
          networkSet: table: gateway:
          builtins.any
            (network: routeVia (network.routes or [ ]) table gateway)
            (builtins.attrValues networkSet);
        renderAccess =
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
            forwardingIntent.rules = [
              {
                action = "accept";
                fromInterface = "tenant-a";
                toInterface = "downstream-selector";
                sourcePrefixes = [ tenantSource ];
              }
            ];
            containerModel = {
              unitName = "nixos-provider-handoff-access-a";
              interfaces = {
                a-tenant-a = {
                  containerInterfaceName = "tenant-a";
                  addresses = [ "10.44.11.1/24" ];
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.44.26";
                    }
                  ];
                };
                b-dead-testnet = {
                  containerInterfaceName = "testnet-host-isp";
                  addresses = [ "10.10.44.27/31" ];
                  routes = [ ];
                };
                c-downstream-selector = {
                  containerInterfaceName = "downstream-selector";
                  addresses = [ "10.10.44.59/31" ];
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.44.58";
                    }
                  ];
                };
              };
            };
          };
        renderUpstream =
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
            forwardingIntent.rules = [
              {
                action = "accept";
                fromInterface = "ens34";
                toInterface = "core-upstream-vlan4";
                sourcePrefixes = [ tenantSource ];
              }
            ];
            containerModel = {
              unitName = "nixos-upstream-selector";
              networkBehavior.isUpstreamSelector = true;
              interfaces = {
                a-policy-isp-a = {
                  containerInterfaceName = "ens34";
                  addresses = [ "10.10.44.33/31" ];
                  interfaceClass.exitFacing = true;
                  backingRef.lane = {
                    access = "provider-handoff-a";
                    uplink = "isp-a";
                    uplinks = [ "isp-a" ];
                  };
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.44.20";
                    }
                  ];
                };
                b-commercial-testnet = {
                  containerInterfaceName = "commercial-testnet";
                  addresses = [ "10.10.44.21/31" ];
                  interfaceClass.coreFacing = true;
                  backingRef.lane = {
                    uplink = "commercial";
                    uplinks = [ "commercial" ];
                  };
                  routes = [ ];
                };
                c-core-upstream-vlan4 = {
                  containerInterfaceName = "core-upstream-vlan4";
                  addresses = [ "10.10.44.35/31" ];
                  interfaceClass.coreFacing = true;
                  backingRef.lane = {
                    uplink = "isp-a";
                    uplinks = [ "isp-a" ];
                  };
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.44.34";
                    }
                  ];
                };
              };
            };
          };
        accessSourceRules = renderAccess.networks."10-tenant-a".routingPolicyRules or [ ];
        accessDownstreamRules = renderAccess.networks."10-downstream-selector".routingPolicyRules or [ ];
        accessDownstreamRoutes = renderAccess.networks."10-downstream-selector".routes or [ ];
        accessSourceRule = ruleFor accessSourceRules "tenant-a" tenantSource.prefix 2000;
        accessDownstreamRule = ruleFor accessDownstreamRules "tenant-a" tenantSource.prefix 2002;
        upstreamSourceRules = renderUpstream.networks."10-ens34".routingPolicyRules or [ ];
        upstreamCoreRules = renderUpstream.networks."10-core-upstream-vlan4".routingPolicyRules or [ ];
        upstreamCoreRoutes = renderUpstream.networks."10-core-upstream-vlan4".routes or [ ];
        upstreamSourceRule = ruleFor upstreamSourceRules "ens34" tenantSource.prefix 2000;
        upstreamCoreRule = ruleFor upstreamCoreRules "ens34" tenantSource.prefix 2002;
      in
        if accessDownstreamRule == null then
          throw "provider-handoff tenant ingress is missing downstream-selector table rule"
        else if !(routeVia accessDownstreamRoutes 2002 "10.10.44.58") then
          throw "provider-handoff downstream-selector table lacks route via downstream selector peer"
        else if accessSourceRule != null && accessSourceRule.Priority <= accessDownstreamRule.Priority && !(routeViaAny renderAccess.networks accessSourceRule.Table "10.10.44.58") then
          throw "provider-handoff selected source table does not route via downstream-selector peer"
        else if upstreamCoreRule == null then
          throw "upstream-selector ens34 ingress is missing core-upstream-vlan4 table rule"
        else if !(routeVia upstreamCoreRoutes 2002 "10.10.44.34") then
          throw "upstream-selector core-upstream-vlan4 table lacks route via isp-a core peer"
        else if upstreamSourceRule != null && upstreamSourceRule.Priority <= upstreamCoreRule.Priority then
          throw "upstream-selector source table shadows core-upstream-vlan4 table"
        else
          true
    '

echo "PASS provider-handoff-path-materialization"
