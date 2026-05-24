#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  return-side-policy-rules-unscoped \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        render = args:
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") ({
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
          } // args);
        tableRulesFor = network: interface:
          builtins.filter
            (rule:
              (rule.IncomingInterface or null) == interface
              && builtins.isInt (rule.Table or null)
              && (rule.Table or null) != 254)
            (network.routingPolicyRules or [ ]);
        hasUnscopedTableRule = network: interface:
          builtins.any (rule: !(rule ? From)) (tableRulesFor network interface);
        hasScopedTableRule = network: interface: prefix:
          builtins.any (rule: (rule.From or null) == prefix) (tableRulesFor network interface);
        hasDestinationScopedTableRule = network: interface: prefix:
          builtins.any (rule: (rule.To or null) == prefix) (tableRulesFor network interface);
        policyRender = render {
          forwardingIntent.rules = [
            { action = "accept"; fromInterface = "downstr-client"; toInterface = "up-client-b"; }
            { action = "accept"; fromInterface = "up-client-b"; toInterface = "downstr-client"; }
          ];
          containerModel = {
            networkBehavior.isPolicy = true;
            site.tenants = [
              {
                name = "client";
                ipv4 = "10.20.20.0/24";
              }
            ];
            site.tenantPrefixOwners."4|10.20.20.0/24".owner = "router-access-client";
            interfaces = {
              downstr-client = {
                containerInterfaceName = "downstr-client";
                addresses = [ "10.10.0.21/31" ];
                interfaceClass.fabricFacing = true;
                backingRef.lane.access = "router-access-client";
                routes = [ ];
              };
              up-client-b = {
                containerInterfaceName = "up-client-b";
                addresses = [ "10.10.0.36/31" ];
                interfaceClass.exitFacing = true;
                backingRef.lane = {
                  access = "router-access-client";
                  uplink = "isp-b";
                  uplinks = [ "isp-b" ];
                };
                routes = [
                  {
                    dst = "0.0.0.0/0";
                    via4 = "10.10.0.37";
                    policyOnly = true;
                    reason = "policy-derived-default";
                    lane.access = "router-access-client";
                    lane.uplink = "isp-b";
                  }
                ];
              };
            };
          };
        };
        downstreamRender = render {
          forwardingIntent.rules = [
            { action = "accept"; fromInterface = "access-client"; toInterface = "policy-client"; }
            { action = "accept"; fromInterface = "policy-client"; toInterface = "access-client"; }
          ];
          containerModel = {
            networkBehavior = {
              isSelector = true;
              isDownstreamSelector = true;
            };
            site.tenantPrefixOwners."4|10.20.20.0/24".owner = "router-access-client";
            site.tenants = [
              {
                name = "client";
                ipv4 = "10.20.20.0/24";
              }
            ];
            interfaces = {
              access-client = {
                containerInterfaceName = "access-client";
                addresses = [ "10.10.0.3/31" ];
                interfaceClass.edgeFacing = true;
                backingRef.lane.access = "router-access-client";
                routes = [ ];
              };
              policy-client = {
                containerInterfaceName = "policy-client";
                addresses = [ "10.10.0.20/31" ];
                interfaceClass.fabricFacing = true;
                backingRef.lane.access = "router-access-client";
                routes = [
                  {
                    dst = "0.0.0.0/0";
                    via4 = "10.10.0.21";
                    policyOnly = true;
                    reason = "policy-derived-default";
                    lane.access = "router-access-client";
                    lane.uplink = "isp-b";
                  }
                ];
              };
            };
          };
        };
        accessRender = render {
          forwardingIntent.rules = [
            { action = "accept"; fromInterface = "tenant-client"; toInterface = "transit"; }
            { action = "accept"; fromInterface = "transit"; toInterface = "tenant-client"; }
          ];
          containerModel = {
            site.tenantPrefixOwners."4|10.20.20.0/24".owner = "router-access-client";
            interfaces = {
              tenant-client = {
                containerInterfaceName = "tenant-client";
                addresses = [ "10.20.20.1/24" ];
                backingRef.lane.access = "router-access-client";
                routes = [
                  {
                    dst = "10.20.20.0/24";
                    proto = "connected";
                  }
                ];
              };
              transit = {
                containerInterfaceName = "transit";
                addresses = [ "10.10.0.4/31" ];
                backingRef.lane.access = "router-access-client";
                routes = [
                  {
                    dst = "0.0.0.0/0";
                    via4 = "10.10.0.5";
                    policyOnly = true;
                    reason = "policy-derived-default";
                    lane.access = "router-access-client";
                    lane.uplink = "isp-b";
                  }
                ];
              };
            };
          };
        };
        policyUpstream = policyRender.networks."10-up-client-b";
        policyDownstream = policyRender.networks."10-downstr-client";
        selectorPolicy = downstreamRender.networks."10-policy-client";
        selectorAccess = downstreamRender.networks."10-access-client";
        accessTransit = accessRender.networks."10-transit";
        upstreamReturnRoutes = policyRender.networks."10-downstr-client".routes or [ ];
        selectorReturnRoutes = selectorAccess.routes or [ ];
        hasUpstreamReturnTenantRoute =
          builtins.any
            (route:
              (route.Destination or null) == "10.20.20.0/24"
              && (route.Gateway or null) == "10.10.0.20"
              && builtins.isInt (route.Table or null))
            upstreamReturnRoutes;
        hasSelectorReturnTenantRoute =
          builtins.any
            (route:
              (route.Destination or null) == "10.20.20.0/24"
              && (route.Gateway or null) == "10.10.0.2"
              && builtins.isInt (route.Table or null))
            selectorReturnRoutes;
      in
        if !(hasDestinationScopedTableRule policyDownstream "up-client-b" "10.20.20.0/24") then
          throw "policy upstream return path must use a destination-scoped rule into the downstream tenant table"
        else if !(hasUnscopedTableRule policyUpstream "up-client-b") then
          throw "policy upstream source-side interface lacks an unscoped iif table rule for policy selection"
        else if hasScopedTableRule policyUpstream "up-client-b" "10.20.20.0/24" then
          throw "policy upstream return interface must not be tenant-source scoped"
        else if !(hasUpstreamReturnTenantRoute) then
          throw ("policy upstream return table lacks accepted downstream tenant route: " + builtins.toJSON {
            inherit upstreamReturnRoutes;
          })
        else if !(hasScopedTableRule policyDownstream "downstr-client" "10.20.20.0/24") then
          throw "policy downstream ingress interface lost tenant-source scoping"
        else if !(hasUnscopedTableRule selectorPolicy "policy-client") then
          throw "downstream selector policy source-side interface lacks an unscoped iif table rule"
        else if hasScopedTableRule selectorPolicy "policy-client" "10.20.20.0/24" then
          throw "downstream selector policy return interface must not be tenant-source scoped"
        else if !(hasSelectorReturnTenantRoute) then
          throw ("downstream selector return table lacks local access tenant route: " + builtins.toJSON {
            inherit selectorReturnRoutes;
          })
        else if !(hasDestinationScopedTableRule accessTransit "transit" "10.20.20.0/24") then
          throw "access router return path must use a destination-scoped rule into the tenant table"
        else true
    '

echo "PASS return-side-policy-rules-unscoped"
