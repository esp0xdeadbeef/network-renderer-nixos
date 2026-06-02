#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  dynamic-sourcefile-policy-table-lane-selection \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        sourceFile = "/run/secrets/access-node-ipv6-prefix-hostile";
        render =
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
            forwardingIntent.rules = [
              {
                action = "accept";
                fromInterface = "pol-hostile-ew";
                toInterface = "core-nebula";
                sourceFiles = [ sourceFile ];
                family = 6;
                relationId = "runtime-routed-prefix-public-egress";
              }
              {
                action = "accept";
                fromInterface = "core-nebula";
                toInterface = "pol-hostile-ew";
                sourceFiles = [ sourceFile ];
                family = 6;
                relationId = "runtime-routed-prefix-return";
              }
              {
                action = "accept";
                fromInterface = "pol-hostile-ew";
                toInterface = "core-a";
              }
              {
                action = "accept";
                fromInterface = "core-a";
                toInterface = "pol-hostile-ew";
              }
            ];
            containerModel = {
              networkBehavior.isUpstreamSelector = true;
              interfaces = {
                core-a = {
                  containerInterfaceName = "core-a";
                  interfaceClass.coreFacing = true;
                  addresses = [ "fd42:dead:beef:1000::d/127" ];
                  backingRef.lane.uplink = "isp-a";
                  routes = [
                    {
                      dst = "::/0";
                      via6 = "fd42:dead:beef:1000::c";
                      metric = 1000;
                      policyOnly = true;
                      lane.uplink = "isp-a";
                      intent.kind = "default-reachability";
                    }
                  ];
                };
                core-nebula = {
                  containerInterfaceName = "core-nebula";
                  interfaceClass.coreFacing = true;
                  addresses = [ "fd42:dead:beef:1000::27/127" ];
                  backingRef.lane = {
                    uplink = "east-west";
                    uplinks = [ "east-west" ];
                  };
                  routes = [
                    {
                      dst = "::/0";
                      via6 = "fd42:dead:beef:1000::26";
                      metric = 2000;
                      policyOnly = true;
                      lane.uplink = "east-west";
                      intent.kind = "default-reachability";
                    }
                  ];
                };
                pol-hostile-ew = {
                  containerInterfaceName = "pol-hostile-ew";
                  interfaceClass.exitFacing = true;
                  addresses = [ "fd42:dead:beef:1000::25/127" ];
                  backingRef.lane = {
                    access = "router-access-hostile";
                    uplink = "east-west";
                    uplinks = [ "east-west" ];
                  };
                  routes = [
                    {
                      family = 6;
                      sourceFile = sourceFile;
                      via6 = "fd42:dead:beef:1000::26";
                      intent.kind = "runtime-routed-prefix-return";
                    }
                  ];
                };
              };
            };
          };
        routeTablesWithDefault =
          gateway:
          lib.unique (
            map (route: route.Table) (
              lib.filter
                (
                  route:
                  (route.Destination or null) == "::/0"
                  && (route.Gateway or null) == gateway
                  && builtins.isInt (route.Table or null)
                )
                (
                  (render.networks."10-core-a".routes or [ ])
                  ++ (render.networks."10-core-nebula".routes or [ ])
                )
            )
          );
        coreATables = routeTablesWithDefault "fd42:dead:beef:1000::c";
        coreNebulaTables = routeTablesWithDefault "fd42:dead:beef:1000::26";
        sourceFileRulesForIngress =
          lib.filter
            (
              rule:
              (rule.interfaceName or null) == "pol-hostile-ew"
              && (rule.sourceFile or null) == sourceFile
              && builtins.isInt (rule.table or null)
              && (rule.table or null) != 254
            )
            (render.dynamicPolicySourceRules or [ ]);
        badWanRule =
          builtins.any (rule: builtins.elem rule.table coreATables) sourceFileRulesForIngress;
        hasEastWestRule =
          builtins.any (rule: builtins.elem rule.table coreNebulaTables) sourceFileRulesForIngress;
      in
      if badWanRule then
        throw "hostile delegated-prefix sourceFile selected a policy table with a WAN/core-a default"
      else if !hasEastWestRule then
        throw "hostile delegated-prefix sourceFile did not select the east-west/core-nebula policy table"
      else
        true
    '

echo "PASS dynamic-sourcefile-policy-table-lane-selection"
