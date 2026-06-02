#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  runtime-sourcefile-routes-do-not-cross-policy-tables \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        sourceFile = "/run/secrets/hetzner-lighthouse-public-ipv4";
        render =
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
            forwardingIntent.normalizedExplicitForwardPairs = [
              {
                action = "accept";
                "in" = [ "pol-client-b" ];
                "out" = [ "core-a" ];
                trafficType = "nebula";
              }
              {
                action = "accept";
                "in" = [ "pol-client-b" ];
                "out" = [ "core-b" ];
              }
              {
                action = "accept";
                "in" = [ "core-b" ];
                "out" = [ "pol-client-b" ];
              }
            ];
            containerModel = {
              networkBehavior.isUpstreamSelector = true;
              interfaces = {
                core-a = {
                  containerInterfaceName = "core-a";
                  addresses = [ "10.10.0.12/31" ];
                  interfaceClass.coreFacing = true;
                  backingRef.lane.uplink = "isp-a";
                  routes = [
                    {
                      dst = null;
                      family = 4;
                      sourceFile = sourceFile;
                      via4 = "10.10.0.12";
                      intent.kind = "overlay-underlay-endpoint";
                    }
                  ];
                };
                core-b = {
                  containerInterfaceName = "core-b";
                  addresses = [ "10.10.0.14/31" ];
                  interfaceClass.coreFacing = true;
                  backingRef.lane.uplink = "isp-b";
                  routes = [
                    {
                      dst = null;
                      family = 4;
                      sourceFile = sourceFile;
                      via4 = "10.10.0.14";
                      intent.kind = "overlay-underlay-endpoint";
                    }
                  ];
                };
                pol-client-b = {
                  containerInterfaceName = "pol-client-b";
                  addresses = [ "10.10.0.37/31" ];
                  interfaceClass.exitFacing = true;
                  backingRef.lane = {
                    access = "router-access-client";
                    uplink = "isp-b";
                    uplinks = [ "isp-b" ];
                  };
                  routes = [
                    {
                      dst = "0.0.0.0/0";
                      via4 = "10.10.0.14";
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
        polClientRules = render.networks."10-pol-client-b".routingPolicyRules or [ ];
        polClientTable =
          let
            tables = lib.unique (
              map (rule: rule.Table) (
                lib.filter (rule: builtins.isInt (rule.Table or null) && rule.Table != 254) polClientRules
              )
            );
          in
            if tables == [ ] then throw "pol-client-b has no policy table" else builtins.head tables;
        badCoreAProjection =
          builtins.any
            (
              route:
                (route.interfaceName or null) == "core-a"
                && (route.sourceFile or null) == sourceFile
                && (route.table or null) == polClientTable
            )
            render.dynamicDelegatedRoutes;
      in
        if badCoreAProjection then
          throw "ISP-A endpoint source-file route was projected into the ISP-B client policy table"
        else
          true
    '

echo "PASS runtime-sourcefile-routes-do-not-cross-policy-tables"
